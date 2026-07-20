import Foundation
import SwiftData

/// SYNC-04 — the orchestration half of auto-sync.
///
/// Drives the snapshot exchange over the injected `SyncTransport` seam (19-01):
///   - On connect, BOTH sides push `SnapshotExporter.exportData` (merge is idempotent +
///     LWW, so a symmetric double-exchange converges in one round — this is also what
///     makes Plan-04 bootstrap "just work").
///   - On a received snapshot, merge via `SnapshotImporter.mergeData` (Phase-18 engine,
///     REUSED — this file contains ZERO merge/DTO logic).
///   - On a local ModelContext save, debounce then push (so a peer sees the change with
///     no tap). The `isMerging` guard breaks the merge→save→push→merge echo loop.
///   - On `.disconnected` / `.failed`, auto-retry with capped exponential backoff to
///     contain MultipeerConnectivity flakiness.
///   - `syncNow()` is the manual fallback; the foreground-only lifecycle lives in
///     MyHomeApp's scenePhase wiring (start on foreground, stop on background).
///
/// SwiftData + Foundation only — no MultipeerConnectivity, no UIKit. `deviceName` is
/// injected so this class never touches UIKit (`UIDevice`).
@MainActor
@Observable
final class SyncCoordinator {

    /// Public status store — Plans 03/04 read sync state via the coordinator.
    let statusStore: SyncStatusStore

    // MARK: - Injected dependencies

    private let transport: any SyncTransport
    private let deviceName: String
    private let pushDebounce: TimeInterval
    private let retryBaseDelay: TimeInterval

    // MARK: - Private state

    private var context: ModelContext?
    private var didSaveObserver: NSObjectProtocol?

    /// True between start() and stop().
    private var isActive = false
    /// True while a received snapshot is being merged — suppresses the merge-triggered
    /// didSave from scheduling a push (the echo-loop guard, T-19-05).
    private var isMerging = false
    /// Whether we've already pushed on the current connection (avoids a redundant
    /// second push when we received before our connect-push fired).
    private var didSendThisConnection = false

    /// Pending debounced local-change push — exposed internally so tests can assert it
    /// stays nil after a merge (echo suppression).
    private(set) var pendingPushTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Current backoff delay (starts at retryBaseDelay, doubles to a 30s cap).
    private var retryDelay: TimeInterval

    // MARK: - Init

    init(
        transport: any SyncTransport,
        statusStore: SyncStatusStore = SyncStatusStore(),
        deviceName: String,
        pushDebounce: TimeInterval = 3.0,
        retryBaseDelay: TimeInterval = 2.0
    ) {
        self.transport = transport
        self.statusStore = statusStore
        self.deviceName = deviceName
        self.pushDebounce = pushDebounce
        self.retryBaseDelay = retryBaseDelay
        self.retryDelay = retryBaseDelay
    }

    // MARK: - Context wiring

    /// Wire the coordinator to our production ModelContext (GmailSyncController idiom).
    /// Registers a `ModelContext.didSave` observer scoped to THIS context only, so
    /// in-memory test containers and future contexts never trip a push. Idempotent.
    func setContext(_ context: ModelContext) {
        if let existing = didSaveObserver {
            NotificationCenter.default.removeObserver(existing)
            didSaveObserver = nil
        }
        self.context = context
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: .main
        ) { [weak self] _ in
            // `.main` queue delivery is on the MainActor; hop explicitly for Swift 6.
            Task { @MainActor in self?.localStoreDidChange() }
        }
    }

    // MARK: - Lifecycle

    /// Begin auto-sync: wire the transport event sink and start discovery. Idempotent.
    func start() {
        guard !isActive else { return }
        isActive = true
        transport.onEvent = { [weak self] event in
            // The transport contract guarantees onEvent is invoked on the MainActor.
            MainActor.assumeIsolated { self?.handle(event) }
        }
        statusStore.status = .connecting
        transport.start()
    }

    /// Tear everything down: cancel pending work, stop discovery, reset status.
    /// Idempotent — foreground-only policy calls this on backgrounding.
    func stop() {
        isActive = false
        retryTask?.cancel(); retryTask = nil
        pendingPushTask?.cancel(); pendingPushTask = nil
        transport.stop()
        statusStore.status = .idle
        statusStore.connectedPeerName = nil
        didSendThisConnection = false
    }

    // MARK: - Transport events (internal so tests can drive directly)

    func handle(_ event: SyncTransportEvent) {
        switch event {
        case .connecting:
            statusStore.status = .connecting

        case .connected(let peerName):
            statusStore.connectedPeerName = peerName
            retryDelay = retryBaseDelay          // healthy link — reset backoff
            didSendThisConnection = false
            pushLocalSnapshot()                  // both sides push; merge is idempotent + LWW

        case .received(.snapshotRequest):
            pushLocalSnapshot()                  // unconditional reply — "Sync now" always works

        case .received(.snapshot(let data)):
            guard let context else { return }
            statusStore.status = .syncing
            isMerging = true
            defer { isMerging = false }
            do {
                let stats = try SnapshotImporter.mergeData(data, into: context)
                statusStore.markSynced(stats: stats)
                if !didSendThisConnection {
                    // We received before our connect-push fired — reciprocate now.
                    pushLocalSnapshot()
                }
            } catch {
                // Engine guarantees an atomic merge: on throw the store is untouched.
                statusStore.status = .error(message: error.localizedDescription)
            }

        case .disconnected:
            statusStore.connectedPeerName = nil
            if isActive {
                statusStore.status = .connecting
                scheduleRetry()
            }

        case .failed(let message):
            statusStore.status = .error(message: message)
            if isActive { scheduleRetry() }
        }
    }

    // MARK: - Sending

    /// Export the full local snapshot and send it. Guards on a connected transport;
    /// a completed outbound send IS a sync from this phone's perspective.
    func pushLocalSnapshot() {
        guard let context, transport.isConnected else { return }
        statusStore.status = .syncing
        do {
            let data = try SnapshotExporter.exportData(context: context, deviceName: deviceName)
            try transport.send(.snapshot(data))
            didSendThisConnection = true
            statusStore.markSynced()
        } catch {
            statusStore.status = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Local change → debounced push

    func localStoreDidChange() {
        // CRITICAL echo-loop guard: mergeData ends in context.save(), which fires
        // didSave. Without this, two connected phones ping-pong snapshots forever.
        guard !isMerging else { return }
        guard isActive, transport.isConnected else { return }
        pendingPushTask?.cancel()
        pendingPushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.pushDebounce))
            guard !Task.isCancelled else { return }
            self.pushLocalSnapshot()
        }
    }

    // MARK: - Retry with capped backoff

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.retryDelay))
            guard !Task.isCancelled, self.isActive else { return }
            self.retryDelay = min(self.retryDelay * 2, 30)  // 2s→4s→…→30s cap
            // Fresh MC objects per the 19-01 transport contract.
            self.transport.stop()
            self.transport.start()
        }
    }

    // MARK: - Manual fallback (SYNC-04)

    /// "Sync now": if connected, push ours AND request theirs (bidirectional). If not
    /// connected, force fresh discovery instead of silently doing nothing.
    func syncNow() {
        if transport.isConnected {
            pushLocalSnapshot()
            try? transport.send(.snapshotRequest)
        } else {
            retryDelay = retryBaseDelay
            transport.stop()
            transport.start()
            statusStore.status = .connecting
        }
    }
}
