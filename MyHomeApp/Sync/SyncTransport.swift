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
    /// Begin advertising + browsing for peers.
    func start()
    /// Disconnect and stop discovery. Idempotent — safe to call when never started.
    func stop()
    /// Send an envelope to the connected peer. Throws if no peer is connected.
    func send(_ envelope: SyncEnvelope) throws
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
