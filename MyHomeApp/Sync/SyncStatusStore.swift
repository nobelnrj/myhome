import Foundation

/// SYNC-04 — observable sync state surfaced to the Plan-03 UI and Plan-04 bootstrap.
///
/// Pure Foundation: no SwiftData, no MultipeerConnectivity, no UIKit. The coordinator
/// mutates this store as the exchange progresses; views read it via the coordinator.
///
/// `lastSyncedAt` is the ONLY persisted field — a plain `UserDefaults.standard`
/// timestamp (not sensitive) so the UI can show "Last synced …" across app relaunches.

// MARK: - PeerSyncStatus

/// Coarse peer-sync lifecycle state for the UI. `.error` carries a human-readable message.
///
/// Named `PeerSyncStatus` (not `SyncStatus`) to avoid colliding with the pre-existing
/// `SyncStatus` for the Gmail ingestion pipeline (GmailSyncController) — both live in the
/// same `MyHome` module, so the P2P status needs a distinct type name.
enum PeerSyncStatus: Equatable {
    case idle
    case connecting
    case syncing
    case error(message: String)
}

// MARK: - SyncStatusStore

@MainActor
@Observable
final class SyncStatusStore {

    /// UserDefaults key for the persisted last-synced timestamp.
    private static let lastSyncedKey = "sync.lastSyncedAt"

    /// Current coarse status driving the UI.
    var status: PeerSyncStatus = .idle

    /// The connected peer's display name, or nil when not connected (in-memory only).
    var connectedPeerName: String?

    /// Stats from the most recent successful merge (in-memory only — for the UI to show
    /// "N inserted / M updated" after a sync).
    var lastMergeStats: MergeStats?

    /// When this phone last completed a successful send or merge. Persisted so the UI's
    /// "Last synced" survives relaunch; nil means "Never".
    var lastSyncedAt: Date? {
        didSet {
            if let date = lastSyncedAt {
                UserDefaults.standard.set(date, forKey: Self.lastSyncedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
            }
        }
    }

    init() {
        // Read the persisted timestamp on init (assign to backing storage without
        // re-triggering the didSet write — value is already what's on disk).
        self.lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// Record a successful sync: stamp lastSyncedAt, store stats if present, and reset
    /// status to `.idle`. Called after any successful send or merge.
    func markSynced(at date: Date = Date(), stats: MergeStats? = nil) {
        lastSyncedAt = date
        if let stats { lastMergeStats = stats }
        status = .idle
    }
}
