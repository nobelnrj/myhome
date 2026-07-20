import Foundation
import MultipeerConnectivity
import UIKit

/// SYNC-04 — the production `SyncTransport` conformer.
///
/// This is the ONLY file that touches MultipeerConnectivity. Everything above it
/// talks to the `SyncTransport` protocol, so MC's well-known flakiness (stale
/// objects after disconnect, off-main delegate callbacks, dual-connect races) is
/// contained entirely here.
///
/// Design:
///   - Encrypted `MCSession` (`encryptionPreference: .required`) — the link refuses
///     to form unencrypted (T-19-01).
///   - Both phones advertise AND browse; `PeerInvitePolicy.shouldInvite` decides who
///     invites so exactly one side connects (no dual-connect race).
///   - Fresh MC objects built every `start()` — MC objects go stale after a
///     disconnect and must never be reused across start/stop cycles.
///   - All delegate callbacks arrive OFF-main; each is `nonisolated`, extracts only
///     Sendable values, then hops to `@MainActor` before touching any state or
///     firing `onEvent`. The class is NOT `@unchecked Sendable`.
@MainActor
final class MultipeerSyncTransport: NSObject, SyncTransport {

    // MARK: - SyncTransport surface

    var onEvent: ((SyncTransportEvent) -> Void)?

    var isConnected: Bool {
        !(session?.connectedPeers.isEmpty ?? true)
    }

    var connectedPeerName: String? {
        session?.connectedPeers.first?.displayName
    }

    // MARK: - Errors

    enum TransportError: Error {
        case notConnected
    }

    // MARK: - Identity

    /// Persistent per-install ID (created once). Combined with the device name it
    /// yields a stable, tie-breakable MCPeerID display name.
    private static let installIDKey = "sync.installID"

    private var installID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.installIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Self.installIDKey)
        return fresh
    }

    /// The display name for THIS device's current session. Set fresh in `start()` so
    /// the browser tie-break compares against a live local name.
    private var myDisplayName: String = ""

    // MARK: - MC objects (rebuilt every start, torn down every stop)

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: - Sendable box for non-Sendable values that must cross the hop

    /// Carries a non-Sendable value (the advertiser's `invitationHandler`) across a
    /// MainActor hop. We control the single call site, so the unchecked assertion is
    /// sound. The transport class itself is never marked `@unchecked Sendable`.
    private struct UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
    }

    // MARK: - Lifecycle

    func start() {
        // Rebuild fresh MC objects — never reuse stale ones across start/stop.
        stop()

        let name = PeerInvitePolicy.displayName(
            deviceName: UIDevice.current.name,
            installID: installID
        )
        myDisplayName = name
        let peerID = MCPeerID(displayName: name)

        let session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: PeerInvitePolicy.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: PeerInvitePolicy.serviceType
        )
        browser.delegate = self
        self.browser = browser

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
    }

    func send(_ envelope: SyncEnvelope) throws {
        guard let session, !session.connectedPeers.isEmpty else {
            throw TransportError.notConnected
        }
        let data = try SyncEnvelope.encode(envelope)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - MainActor event fan-out

    private func emit(_ event: SyncTransportEvent) {
        onEvent?(event)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSyncTransport: MCSessionDelegate {

    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        let peerName = peerID.displayName
        let stateRaw = state.rawValue
        Task { @MainActor in
            switch MCSessionState(rawValue: stateRaw) ?? .notConnected {
            case .connecting:
                self.emit(.connecting(peerName: peerName))
            case .connected:
                self.emit(.connected(peerName: peerName))
            case .notConnected:
                self.emit(.disconnected)
            @unknown default:
                self.emit(.disconnected)
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        // `data` is Sendable; decode on the hop and drop malformed frames.
        Task { @MainActor in
            do {
                let envelope = try SyncEnvelope.decode(data)
                self.emit(.received(envelope))
            } catch {
                // Never crash on hostile/corrupt bytes — drop and report.
                self.emit(.failed(message: "Ignored malformed sync message"))
            }
        }
    }

    // Unused stream / resource callbacks — minimal bodies.

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        // Accept — the link is .required-encrypted; a 2-phone household trusts first contact.
        certificateHandler(true)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerSyncTransport: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // `invitationHandler` is non-Sendable → box it across the hop.
        let box = UncheckedSendableBox(value: invitationHandler)
        Task { @MainActor in
            // Accept using our live session (a 2-phone household trusts first contact;
            // encryption is .required so the link is private).
            box.value(true, self.session)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.emit(.failed(message: "Could not advertise for sync (\(message)). "
                + "Local Network permission may be denied — check Settings → Privacy → Local Network."))
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSyncTransport: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let remoteName = peerID.displayName
        // Box the non-Sendable peerID + browser so the invite happens on the hop
        // where we can read `myDisplayName` and `session`.
        let peerBox = UncheckedSendableBox(value: peerID)
        let browserBox = UncheckedSendableBox(value: browser)
        Task { @MainActor in
            guard let session = self.session else { return }
            // Deterministic tie-break: only the "lower" name invites. The other side
            // invites us — exactly one connection forms.
            if PeerInvitePolicy.shouldInvite(
                localDisplayName: self.myDisplayName,
                remoteDisplayName: remoteName
            ) {
                browserBox.value.invitePeer(
                    peerBox.value,
                    to: session,
                    withContext: nil,
                    timeout: 15
                )
            }
            // else: do nothing — the remote peer invites us.
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        // Discovery-level loss; the session delegate reports the real disconnect.
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.emit(.failed(message: "Could not browse for sync (\(message)). "
                + "Local Network permission may be denied — check Settings → Privacy → Local Network."))
        }
    }
}
