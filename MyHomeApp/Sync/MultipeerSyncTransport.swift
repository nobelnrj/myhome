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

    // MARK: - SYNC-06 allowlist gate state

    /// The trusted paired install IDs both MC gate callbacks consult (via `PeerAllowlistPolicy`)
    /// BEFORE any session forms. Set from `PairedDevicesStore`; empty ⇒ default-deny.
    var allowlist: Set<String> = []

    /// While true, the gate is relaxed so a pairing handshake can proceed with an
    /// as-yet-untrusted peer. Toggled by `beginPairing()`/`endPairing()`; auto-cancels.
    var isPairingMode = false

    /// displayName → claimed install ID, learned pre-session from `discoveryInfo`/invite
    /// `context` (both UNTRUSTED). Used at `.connected` to tell a trusted peer from a pairing
    /// candidate. Cleared in `stop()`.
    private var peerIIDByName: [String: String] = [:]

    /// Time-boxed pairing auto-cancel (RESEARCH: 2-minute window). Mirrors the
    /// `SyncCoordinator.scheduleRetry` Task.sleep idiom.
    private var pairingTimeoutTask: Task<Void, Never>?

    /// Pairing-window duration before the gate snaps back to default-deny.
    private static let pairingWindow: TimeInterval = 120

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

        // SYNC-06 — advertise THIS device's install ID so the browser can gate BEFORE
        // inviting. Keep the dict TINY (iid only): an oversized discoveryInfo silently kills
        // discovery with no error (RESEARCH Pitfall 2). A 36-char UUID is far under budget.
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["iid": InstallIdentity.current()],
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
        peerIIDByName.removeAll()   // learned iids are per-discovery; never outlive a session
    }

    // MARK: - SYNC-06 pairing window

    /// Enter the time-boxed pairing window: relax the allowlist gate so an as-yet-untrusted
    /// peer can form a candidate session. Auto-cancels after `pairingWindow` seconds (idiom
    /// mirrors `SyncCoordinator.scheduleRetry`), snapping the gate back to default-deny and
    /// tearing down any candidate session so no stale relaxed link survives the window.
    func beginPairing() {
        isPairingMode = true
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pairingWindow))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isPairingMode = false
            // Tear down any candidate session formed under the relaxed gate; a genuine
            // trusted peer (now in the allowlist) reconnects via the normal retry loop.
            self.session?.disconnect()
        }
    }

    /// Leave the pairing window immediately (e.g. right after "Codes match" + allowlist add).
    func endPairing() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        isPairingMode = false
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
                // SYNC-06 — a session that formed while pairing with an UN-allowlisted peer
                // is a trust CANDIDATE, not a trusted peer. Surface it as `.pairingCandidate`
                // (not `.connected`) so SyncCoordinator pushes NO snapshot to it — this closes
                // the pairing-window auto-push hole (RESEARCH Pitfall 1 / T-25-03). A peer that
                // IS in the allowlist (or any non-pairing session) surfaces as `.connected`.
                if let iid = self.peerIIDByName[peerName],
                   self.isPairingMode, !self.allowlist.contains(iid) {
                    self.emit(.pairingCandidate(peerName: peerName, peerIID: iid))
                } else {
                    self.emit(.connected(peerName: peerName))
                }
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
        // NOTE: this is deliberately NOT an identity gate. The presented cert is a per-session
        // self-signed peer cert UNBOUND to the installID, so gating here adds zero installID
        // assurance and cannot tell a trusted peer from a spoofer (RESEARCH Pitfall 5). The
        // real identity gate is the allowlist check at foundPeer / didReceiveInvitation.
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
        // `invitationHandler` is non-Sendable → box it across the hop. `context`/`peerID`
        // are Sendable-safe to read here; the trust decision happens on the MainActor hop.
        let box = UncheckedSendableBox(value: invitationHandler)
        let remoteName = peerID.displayName
        let context = context   // capture the Sendable Data? for the hop
        Task { @MainActor in
            // SYNC-06 accept-side gate (pre-session). Defensively decode the invite context —
            // it is UNTRUSTED LAN input (nil / non-UTF8 / oversized ⇒ untrusted, never crash).
            let peerIID = PeerAllowlistPolicy.decodeIID(context)
            if let peerIID { self.peerIIDByName[remoteName] = peerIID }
            let ok = PeerAllowlistPolicy.shouldConnect(
                peerIID: peerIID,
                allowlist: self.allowlist,
                pairingMode: self.isPairingMode
            )
            // Reject ⇒ (false, nil): no session forms with an un-allowlisted peer.
            box.value(ok, ok ? self.session : nil)
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
        // `info` is [String: String]? (Sendable) — safe to capture for the hop.
        let discoveredIID = info?["iid"]
        // Box the non-Sendable peerID + browser so the invite happens on the hop
        // where we can read `myDisplayName` and `session`.
        let peerBox = UncheckedSendableBox(value: peerID)
        let browserBox = UncheckedSendableBox(value: browser)
        Task { @MainActor in
            guard let session = self.session else { return }
            // SYNC-06 — record the peer's claimed iid (UNTRUSTED discoveryInfo) so `.connected`
            // can later distinguish a trusted peer from a pairing candidate.
            if let discoveredIID { self.peerIIDByName[remoteName] = discoveredIID }
            // SYNC-06 browse-side gate (pre-invite, pre-session). ADDITIVE to the existing
            // dual-connect tie-break — never a replacement (locked decision). Empty allowlist
            // in normal mode ⇒ deny ⇒ no invite ⇒ no session with an unpaired peer.
            guard PeerAllowlistPolicy.shouldConnect(
                peerIID: discoveredIID,
                allowlist: self.allowlist,
                pairingMode: self.isPairingMode
            ) else { return }
            // Deterministic tie-break: only the "lower" name invites. The other side
            // invites us — exactly one connection forms.
            if PeerInvitePolicy.shouldInvite(
                localDisplayName: self.myDisplayName,
                remoteDisplayName: remoteName
            ) {
                browserBox.value.invitePeer(
                    peerBox.value,
                    to: session,
                    // SYNC-06 — carry THIS device's iid so the advertiser can gate on accept.
                    withContext: Data(InstallIdentity.current().utf8),
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
