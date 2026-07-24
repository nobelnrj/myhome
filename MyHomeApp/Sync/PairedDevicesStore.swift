import Foundation

/// SYNC-06 — the local-only paired-devices allowlist.
///
/// This is the trust root for auto-sync: only peers whose `installID` is in this store
/// may form/accept a MultipeerConnectivity session (via `PeerAllowlistPolicy`). It is a
/// per-device setting persisted as JSON under ONE `UserDefaults.standard` key, mirroring
/// `SyncStatusStore`'s `lastSyncedAt`.
///
/// IMPORTANT — this type is intentionally NOT a SwiftData `@Model` and is NEVER a field of
/// `SyncSnapshot`. That structural exclusion is what keeps the allowlist off the wire: the
/// snapshot codec only encodes `@Model` DTOs, so a `PairedDevice` cannot be serialized into
/// any exported/synced snapshot (proved by a bytes-don't-contain test in Plan 02).
///
/// Decode-failure / empty ⇒ empty devices ⇒ empty `allowlist` ⇒ default-deny (safe): a
/// corrupted or absent store blocks every peer rather than trusting any.

// MARK: - PairedDevice

/// One trusted, paired household device. `installID` is the allowlist key; `friendlyName`
/// is a human label for the paired-devices list; `pairedAt` records when trust was granted.
public struct PairedDevice: Codable, Equatable, Sendable {
    public var installID: String
    public var friendlyName: String
    public var pairedAt: Date

    public init(installID: String, friendlyName: String, pairedAt: Date) {
        self.installID = installID
        self.friendlyName = friendlyName
        self.pairedAt = pairedAt
    }
}

// MARK: - PairedDevicesStore

@MainActor
@Observable
final class PairedDevicesStore {

    /// UserDefaults key for the JSON-encoded `[PairedDevice]`. Local-only, never synced.
    private static let key = "sync.pairedDevices"

    /// The backing store — injectable so tests isolate state from `.standard`.
    @ObservationIgnored private let defaults: UserDefaults

    /// The currently paired devices, decoded on init. Mutated only via `add`/`remove`.
    private(set) var devices: [PairedDevice] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Decode defensively: any failure (absent / corrupt) ⇒ empty ⇒ default-deny.
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            self.devices = decoded
        } else {
            self.devices = []
        }
    }

    /// Whether the given install ID is currently trusted.
    func isPaired(_ iid: String) -> Bool {
        devices.contains { $0.installID == iid }
    }

    /// Upsert a device by `installID` (adding the same ID twice yields one row, updated),
    /// then persist.
    func add(_ device: PairedDevice) {
        if let idx = devices.firstIndex(where: { $0.installID == device.installID }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }
        persist()
    }

    /// Drop the device with the given `installID` (stops all future connections to it),
    /// then persist.
    func remove(installID: String) {
        devices.removeAll { $0.installID == installID }
        persist()
    }

    /// The plain `Set` the transport gate + `PeerAllowlistPolicy` consume.
    var allowlist: Set<String> {
        Set(devices.map(\.installID))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
