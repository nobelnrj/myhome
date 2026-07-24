import CryptoKit
import Foundation

/// SYNC-04 — the transport seam for peer-to-peer sync.
///
/// This file is a PURE value + protocol layer: Foundation only, zero
/// MultipeerConnectivity / UIKit imports. Everything above the transport
/// (SyncCoordinator, UI, bootstrap) talks ONLY to `SyncTransport` — the
/// production `MultipeerSyncTransport` conformer contains all of MC's flakiness
/// in one file, and unit tests drive a fake conformer without two devices.
///
/// Mirrors the `BiometricAuthPort` pattern: protocol + production conformer here,
/// test double lives in MyHomeTests.

// MARK: - SyncEnvelope

/// The wire frame carried by any `SyncTransport`. A tiny handshake vocabulary on
/// top of the Phase-18 snapshot bytes:
///   - `.snapshotRequest` — "send me your current snapshot"
///   - `.snapshot(Data)`  — the exact bytes from `SnapshotExporter.exportData`.
///
/// This layer NEVER inspects the payload `Data`; it is opaque snapshot bytes that
/// the receiver hands to `SnapshotImporter.mergeData`. Encoded via JSON (the
/// `Data` case crosses as base64 automatically — fine at this app's payload sizes).
public enum SyncEnvelope: Codable, Equatable, Sendable {
    /// A request for the peer to reply with its current snapshot.
    case snapshotRequest
    /// A snapshot payload — the raw bytes produced by `SnapshotExporter.exportData`.
    case snapshot(Data)

    // Explicit Codable so the wire shape is stable and legible:
    //   {"kind":"request"} / {"kind":"snapshot","payload":"<base64>"}
    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case request, snapshot }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .request:
            self = .snapshotRequest
        case .snapshot:
            let data = try container.decode(Data.self, forKey: .payload)
            self = .snapshot(data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshotRequest:
            try container.encode(Kind.request, forKey: .kind)
        case .snapshot(let data):
            try container.encode(Kind.snapshot, forKey: .kind)
            try container.encode(data, forKey: .payload)
        }
    }

    /// Encode an envelope to bytes for transmission.
    public static func encode(_ envelope: SyncEnvelope) throws -> Data {
        try JSONEncoder().encode(envelope)
    }

    /// Decode untrusted bytes into an envelope. Throws on garbage/corrupt input —
    /// NEVER crashes and NEVER returns a default. The transport drops frames that
    /// fail this decode.
    public static func decode(_ data: Data) throws -> SyncEnvelope {
        try JSONDecoder().decode(SyncEnvelope.self, from: data)
    }
}

// MARK: - SyncTransportEvent

/// Everything a `SyncTransport` reports back to its owner. Always delivered on the
/// MainActor via `onEvent`. Not Codable — this is a local callback vocabulary, not
/// a wire type.
public enum SyncTransportEvent {
    /// A peer was found and an invite/connection is in progress.
    case connecting(peerName: String)
    /// A peer connection is established (encrypted link is live).
    case connected(peerName: String)
    /// The peer disconnected (or the session was torn down).
    case disconnected
    /// A well-formed envelope arrived from the peer.
    case received(SyncEnvelope)
    /// A transport-level failure worth surfacing (discovery error, permission
    /// denial hint, dropped malformed frame).
    case failed(message: String)
    /// SYNC-06 — an un-allowlisted peer formed a session *in pairing mode*. This is a
    /// trust CANDIDATE, not a trusted peer: it is emitted INSTEAD of `.connected` so the
    /// owner (SyncCoordinator) pushes NO snapshot to it (the pairing-window auto-push hole,
    /// RESEARCH Pitfall 1 / T-25-03). The pairing UI derives the confirmation code from
    /// `peerIID` and only after mutual "Codes match" is the device added to the allowlist;
    /// the next genuine reconnect then surfaces as a trusted `.connected`.
    case pairingCandidate(peerName: String, peerIID: String)
}

// MARK: - SyncTransport

/// The seam every layer above the transport injects. The production conformer is
/// `MultipeerSyncTransport`; tests inject a fake.
///
/// Lifecycle contract:
///   - `start()` begins advertising AND browsing for peers.
///   - `stop()` disconnects the session and stops discovery.
///   - Callers own the foreground-only policy (start on foreground, stop on
///     background) — the transport itself is policy-free.
///   - `onEvent` is ALWAYS invoked on the MainActor.
@MainActor
public protocol SyncTransport: AnyObject {
    /// Event sink — always invoked on the MainActor. Set by the owner before `start()`.
    var onEvent: ((SyncTransportEvent) -> Void)? { get set }
    /// Whether a peer is currently connected.
    var isConnected: Bool { get }
    /// The connected peer's display name, or nil when not connected.
    var connectedPeerName: String? { get }
    /// SYNC-06 — the set of trusted paired install IDs the two MC gate callbacks consult
    /// (via `PeerAllowlistPolicy`) before any session forms. Set from `PairedDevicesStore`.
    /// An empty allowlist in normal mode blocks every peer (default-deny).
    var allowlist: Set<String> { get set }
    /// SYNC-06 — while true, the gate is relaxed so the pairing handshake can proceed with
    /// an as-yet-untrusted peer. Trust is persisted SEPARATELY, only after mutual code
    /// confirmation. Driven by `beginPairing()`/`endPairing()`.
    var isPairingMode: Bool { get set }
    /// Begin advertising + browsing for peers.
    func start()
    /// Disconnect and stop discovery. Idempotent — safe to call when never started.
    func stop()
    /// Send an envelope to the connected peer. Throws if no peer is connected.
    func send(_ envelope: SyncEnvelope) throws
    /// SYNC-06 — enter the time-boxed pairing window (relaxes the allowlist gate). Auto-cancels.
    func beginPairing()
    /// SYNC-06 — leave the pairing window immediately (restores default-deny).
    func endPairing()
}

// MARK: - PeerInvitePolicy

/// Deterministic peer-identity + invite tie-break policy. Pure value logic (no MC
/// import) so it is fully unit-testable.
///
/// The tie-break kills MultipeerConnectivity's notorious dual-connect race: both
/// phones advertise AND browse, so without a rule each would invite the other and
/// two half-open sessions collide. Because each display name carries a unique
/// install suffix, `shouldInvite` is a strict comparison — exactly one side
/// invites.
public enum PeerInvitePolicy {

    /// MC service type: ≤15 chars, lowercase / digits / hyphen only.
    public static let serviceType = "myhome-sync"

    /// Build a stable, human-legible MCPeerID display name from the device name and
    /// a persistent install ID.
    ///
    /// - Sanitizes the device name to alphanumerics + spaces (drops emoji / punctuation),
    ///   trims, and takes a 20-char prefix.
    /// - Appends `"#" + installID.prefix(6)` so two phones with the same device name
    ///   still get distinct, tie-breakable names.
    /// - Falls back to `"MyHome"` if sanitation empties the name.
    /// - Enforces the MCPeerID hard limit of ≤63 UTF-8 bytes.
    public static func displayName(deviceName: String, installID: String) -> String {
        // 1. Sanitize: keep alphanumerics + spaces only.
        let sanitized = deviceName.unicodeScalars
            .map { scalar -> Character in
                if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                    return Character(scalar)
                }
                return " "
            }
        var base = String(sanitized)
            .trimmingCharacters(in: .whitespaces)
        // Collapse runs of whitespace introduced by sanitation.
        base = base.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        if base.isEmpty { base = "MyHome" }
        base = String(base.prefix(20))

        let suffix = String(installID.prefix(6))
        var name = "\(base)#\(suffix)"

        // 2. Enforce ≤63 UTF-8 bytes (MCPeerID hard limit). Trim the base, never the
        //    suffix, so uniqueness survives.
        if name.utf8.count > 63 {
            let suffixCost = "#\(suffix)".utf8.count
            var trimmedBase = base
            while trimmedBase.utf8.count + suffixCost > 63 && !trimmedBase.isEmpty {
                trimmedBase.removeLast()
            }
            if trimmedBase.isEmpty { trimmedBase = "MyHome" }
            name = "\(trimmedBase)#\(suffix)"
            // Final hard clamp in the pathological case (huge multi-byte suffix).
            while name.utf8.count > 63 && !name.isEmpty {
                name.removeLast()
            }
        }
        return name
    }

    /// Antisymmetric invite decision. Returns `localDisplayName < remoteDisplayName`
    /// (strict). With unique install suffixes exactly one side of any pair invites;
    /// equal names → false both ways (no self-invite / no dual-connect).
    public static func shouldInvite(localDisplayName: String, remoteDisplayName: String) -> Bool {
        localDisplayName < remoteDisplayName
    }
}

// MARK: - InstallIdentity

/// SYNC-06 — the single source of truth for THIS device's persistent install ID.
///
/// The install ID is the peer identity the paired-devices allowlist keys on (NOT the
/// MCPeerID display name, which derives from the user-changeable device name). It is a
/// non-secret random UUID that is broadcast on the LAN by design.
///
/// The UserDefaults key MUST stay `"sync.installID"` verbatim — the transport minted
/// this value on first launch and the two already-in-practice-paired phones depend on
/// it surviving the upgrade. Rotating the key would orphan them and break every future
/// pairing (see RESEARCH Pitfall 4).
public enum InstallIdentity {

    /// UserDefaults key — UNCHANGED from `MultipeerSyncTransport`; never rotate on upgrade.
    static let key = "sync.installID"

    /// Returns the stored install ID, minting and persisting a fresh `UUID().uuidString`
    /// only when none exists yet. `defaults` is injectable for tests.
    public static func current(_ defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }
}

// MARK: - PairingCode

/// SYNC-06 — deterministic, order-independent 6-digit confirmation code from two
/// installIDs. Both phones compute the identical value with NO extra exchange (each
/// side already knows both IDs: one from `discoveryInfo`, one local). Pure + testable.
///
/// The code's security value is *mutual confirmation of intent*, not secrecy — both IDs
/// are broadcast on the LAN. It defeats the accidental rogue (a seeded sim / other
/// install shows a mismatched code), which is exactly this phase's threat model.
public enum PairingCode {

    /// Six decimal digits (zero-padded) derived from `SHA256(min|max)` of the two IDs.
    ///
    /// - Order-independent: `min`/`max` on the two ID strings ⇒ `sixDigit(a,b) == sixDigit(b,a)`.
    /// - Cross-device / cross-launch stable: SHA-256 is deterministic. NEVER use the
    ///   Swift standard-library string hasher — it is per-process randomly seeded and
    ///   would show a different code on each phone and each relaunch (RESEARCH Pitfall 3).
    public static func sixDigit(_ idA: String, _ idB: String) -> String {
        let lo = min(idA, idB)                       // order-independence
        let hi = max(idA, idB)
        let input = Data("\(lo)|\(hi)".utf8)
        let digest = SHA256.hash(data: input)        // stable across devices/relaunch
        let b = Array(digest)                        // 32 bytes
        let n = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16)
              | (UInt32(b[2]) << 8)  |  UInt32(b[3])
        return String(format: "%06u", n % 1_000_000) // always 6 digits, zero-padded
    }
}

// MARK: - PeerAllowlistPolicy

/// SYNC-06 — the pure allowlist gate. Antisymmetric sibling of `PeerInvitePolicy`:
/// decides whether to form/accept a session with a peer of a given install ID.
///
/// This gate is ADDITIVE to `PeerInvitePolicy.shouldInvite` (the dual-connect
/// tie-break), never a replacement (locked decision). It runs at both MC trust gates
/// (browse-side `foundPeer` and accept-side `didReceiveInvitationFromPeer`), before any
/// session forms.
public enum PeerAllowlistPolicy {

    /// - Parameters:
    ///   - peerIID: the peer's claimed install ID (from `discoveryInfo`/invite `context`);
    ///     untrusted LAN input, so `nil`/empty ⇒ deny (a peer that advertises no ID is
    ///     treated as untrusted).
    ///   - allowlist: the local set of paired install IDs. Empty ⇒ default-deny (this is
    ///     what makes "no paired device ⇒ nothing connects" fall out for free).
    ///   - pairingMode: when true, relaxes the gate so the pairing handshake can proceed
    ///     with an as-yet-untrusted peer. Trust is persisted SEPARATELY, only after
    ///     mutual code confirmation.
    /// - Returns: whether a session may form/accept with this peer.
    public static func shouldConnect(peerIID: String?,
                                     allowlist: Set<String>,
                                     pairingMode: Bool) -> Bool {
        guard let peerIID, !peerIID.isEmpty else { return false } // missing iid = untrusted
        return pairingMode || allowlist.contains(peerIID)
    }

    /// Defensively decode a peer's claimed install ID from untrusted, unauthenticated,
    /// pre-session LAN input — the invite `context` bytes (mirrors what the browser reads
    /// from `discoveryInfo["iid"]`). Returns `nil` for anything that is not a plausible
    /// install ID so the caller treats it as untrusted and forms no session:
    ///   - `nil` data (an old build sent no context)
    ///   - non-UTF8 bytes (garbage / hostile)
    ///   - empty / whitespace-only after trimming
    ///   - oversized (> 64 bytes — a UUID string is 36; anything larger is not one of ours,
    ///     and keeping this tight also mirrors the tiny-`discoveryInfo` discipline, Pitfall 2)
    ///
    /// NEVER force-unwraps and NEVER crashes on hostile bytes (V5 input validation). Pure so
    /// it is unit-tested directly with nil/garbage/oversized input.
    public static func decodeIID(_ data: Data?) -> String? {
        guard let data, data.count <= 64 else { return nil }        // nil / oversized ⇒ untrusted
        guard let raw = String(data: data, encoding: .utf8) else { return nil } // non-UTF8 ⇒ untrusted
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
