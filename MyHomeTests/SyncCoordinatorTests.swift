import Testing
import SwiftData
import Foundation
@testable import MyHome

/// SYNC-04 — loopback proof of the auto-sync orchestrator WITHOUT two devices.
///
/// A `FakeSyncTransport` pair (linked so a send on one delivers `.received` to the other,
/// synchronously on the MainActor) lets us drive two `SyncCoordinator`s over in-memory
/// SchemaV10 containers and prove: change-on-A-appears-on-B, echo suppression (no runaway
/// ping-pong), snapshotRequest reply, manual syncNow, capped-backoff retry, foreground
/// lifecycle, merge-failure isolation, and newer-local-edit survival (LWW).
///
/// `@Suite(.serialized)` because every coordinator's `SyncStatusStore` reads/writes the shared
/// `UserDefaults` key `"sync.lastSyncedAt"` — the suite must not run in parallel (shared-state
/// race precedent in this repo). The key is cleaned before each test.

// MARK: - FakeSyncTransport

/// A pairable, in-process `SyncTransport` double. Lives in the TEST target only
/// (BiometricAuthPort precedent) — the 19-01 seam is sufficient, no production change.
@MainActor
final class FakeSyncTransport: SyncTransport {
    var onEvent: ((SyncTransportEvent) -> Void)?
    var isConnected = false
    var connectedPeerName: String?

    /// Every envelope handed to `send(_:)`, in order — the assertion surface for echo bounds.
    var sentEnvelopes: [SyncEnvelope] = []
    var startCount = 0
    var stopCount = 0

    /// The linked peer. A send is delivered to `peer.onEvent(.received(...))` when connected.
    weak var peer: FakeSyncTransport?

    func start() { startCount += 1 }

    func stop() {
        stopCount += 1
        isConnected = false
    }

    func send(_ envelope: SyncEnvelope) throws {
        sentEnvelopes.append(envelope)
        if let peer, isConnected {
            peer.onEvent?(.received(envelope))
        }
    }

    // MARK: Test drivers

    /// Two transports wired as each other's peer (not yet connected).
    static func linkedPair() -> (FakeSyncTransport, FakeSyncTransport) {
        let a = FakeSyncTransport()
        let b = FakeSyncTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func simulateConnected(peerName: String) {
        isConnected = true
        connectedPeerName = peerName
        onEvent?(.connected(peerName: peerName))
    }

    func simulateDisconnected() {
        isConnected = false
        connectedPeerName = nil
        onEvent?(.disconnected)
    }

    func simulateFailure(_ message: String) {
        onEvent?(.failed(message: message))
    }
}

// MARK: - Tests

@Suite(.serialized)
@MainActor
struct SyncCoordinatorTests {

    private static let lastSyncedKey = "sync.lastSyncedAt"

    init() {
        // Clean the shared persisted key so lastSyncedAt starts as "Never" every test.
        UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
    }

    // MARK: Fixtures

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try SyncTestSupport.makeStore()
        return (container, container.mainContext)
    }

    private func makeCoordinator(
        transport: any SyncTransport,
        context: ModelContext
    ) -> SyncCoordinator {
        let coord = SyncCoordinator(
            transport: transport,
            deviceName: "TestPhone",
            pushDebounce: 0,
            retryBaseDelay: 0.01
        )
        coord.setContext(context)
        return coord
    }

    /// Valid snapshot bytes produced by a freshly-seeded throwaway store.
    private func snapshotBytes(device: String = "Remote", seed: (ModelContext) throws -> Void) throws -> Data {
        let c = try SyncTestSupport.makeStore()
        try seed(c.mainContext)
        return try SnapshotExporter.exportData(context: c.mainContext, deviceName: device)
    }

    private func fetchExpense(_ ctx: ModelContext, syncID: UUID) throws -> Expense? {
        try ctx.fetch(FetchDescriptor<Expense>()).first { $0.syncID == syncID }
    }

    /// Poll a condition on the MainActor without a fixed long sleep.
    private func waitUntil(_ timeoutTicks: Int = 100, _ condition: () -> Bool) async {
        for _ in 0..<timeoutTicks {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: change-on-A-appears-on-B

    @Test("Connect exchange: an expense in A appears in B, and B's record appears in A — no tap")
    func connectExchangePropagatesBothWays() throws {
        let (ca, actx) = try makeStore()
        let (cb, bctx) = try makeStore()
        _ = ca; _ = cb  // retain containers

        let ea = Expense(amount: Decimal(string: "100")!)
        ea.note = "from-A"
        actx.insert(ea)
        try actx.save()
        let eaSync = ea.syncID

        let eb = Expense(amount: Decimal(string: "200")!)
        eb.note = "from-B"
        bctx.insert(eb)
        try bctx.save()
        let ebSync = eb.syncID

        let (ta, tb) = FakeSyncTransport.linkedPair()
        let coordA = makeCoordinator(transport: ta, context: actx)
        let coordB = makeCoordinator(transport: tb, context: bctx)
        coordA.start()
        coordB.start()

        // Symmetric connect — both push; merge is idempotent + LWW, converges in one round.
        ta.simulateConnected(peerName: "PhoneB")
        tb.simulateConnected(peerName: "PhoneA")

        #expect(try fetchExpense(bctx, syncID: eaSync)?.note == "from-A")
        #expect(try fetchExpense(actx, syncID: ebSync)?.note == "from-B")
    }

    // MARK: echo suppression

    @Test("A merge that saves does NOT enqueue a push (isMerging guard) — pendingPushTask stays nil")
    func mergeDoesNotEnqueuePush() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()  // isActive = true, so ONLY the isMerging guard can prevent scheduling

        // Snapshot that DOES change B (a brand-new expense) → merge saves → didSave fires.
        let data = try snapshotBytes { ctx in
            let e = Expense(amount: Decimal(string: "42")!)
            e.note = "remote"
            ctx.insert(e)
            try ctx.save()
        }
        coord.handle(.received(.snapshot(data)))

        #expect(coord.pendingPushTask == nil)
        #expect(try bctx.fetch(FetchDescriptor<Expense>()).count == 1)
    }

    @Test("Converged pair re-exchanging stays bounded — no infinite ping-pong")
    func echoExchangeIsBounded() async throws {
        let (ca, actx) = try makeStore()
        let (cb, bctx) = try makeStore()
        _ = ca; _ = cb

        let ea = Expense(amount: Decimal(string: "100")!)
        actx.insert(ea); try actx.save()
        let eb = Expense(amount: Decimal(string: "200")!)
        bctx.insert(eb); try bctx.save()

        let (ta, tb) = FakeSyncTransport.linkedPair()
        let coordA = makeCoordinator(transport: ta, context: actx)
        let coordB = makeCoordinator(transport: tb, context: bctx)
        coordA.start(); coordB.start()
        ta.simulateConnected(peerName: "B")
        tb.simulateConnected(peerName: "A")

        // Now converged. Drive another full exchange via syncNow and assert the envelope
        // counts grow by a small bounded amount and then STABILIZE (termination proof).
        let beforeA = ta.sentEnvelopes.count
        let beforeB = tb.sentEnvelopes.count
        coordA.syncNow()

        await waitUntil { false }  // drain any scheduled async tasks (short bounded wait)
        let afterA = ta.sentEnvelopes.count
        let afterB = tb.sentEnvelopes.count

        #expect(afterA - beforeA <= 3)
        #expect(afterB - beforeB <= 3)

        // Stability: no further growth after the exchange settles.
        await waitUntil { false }
        #expect(ta.sentEnvelopes.count == afterA)
        #expect(tb.sentEnvelopes.count == afterB)
    }

    // MARK: snapshotRequest reply

    @Test("snapshotRequest → exactly one snapshot envelope is sent in reply")
    func snapshotRequestReplies() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()   // peer nil → send records but does not recurse
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)

        coord.handle(.received(.snapshotRequest))

        let snapshots = t.sentEnvelopes.filter { if case .snapshot = $0 { return true } else { return false } }
        #expect(snapshots.count == 1)
    }

    // MARK: syncNow

    @Test("syncNow while connected sends both a snapshot AND a snapshotRequest")
    func syncNowConnectedSendsBoth() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)

        coord.syncNow()

        let snapshots = t.sentEnvelopes.filter { if case .snapshot = $0 { return true } else { return false } }
        let requests = t.sentEnvelopes.filter { $0 == .snapshotRequest }
        #expect(snapshots.count == 1)
        #expect(requests.count == 1)
    }

    @Test("syncNow while disconnected restarts discovery instead of failing silently")
    func syncNowDisconnectedRestarts() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        t.isConnected = false
        let coord = makeCoordinator(transport: t, context: bctx)

        coord.syncNow()

        #expect(t.stopCount >= 1)
        #expect(t.startCount >= 1)
        #expect(coord.statusStore.status == .connecting)
    }

    // MARK: retry

    @Test("Disconnected while active auto-retries; after stop() a disconnect does NOT restart")
    func retryOnlyWhileActive() async throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()                       // t.startCount == 1
        let baseline = t.startCount

        coord.handle(.disconnected)         // active → scheduleRetry (base 0.01s)
        await waitUntil { t.startCount > baseline }
        #expect(t.startCount > baseline)    // retry fired transport.stop()+start()

        coord.stop()                        // isActive = false
        let afterStop = t.startCount
        coord.handle(.disconnected)         // inactive → no retry
        await waitUntil(20) { false }       // brief wait; should NOT restart
        #expect(t.startCount == afterStop)
    }

    // MARK: foreground lifecycle

    @Test("stop() sets status idle, clears peer name, and tears the transport down")
    func stopTearsDown() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()
        coord.handle(.connected(peerName: "Peer"))
        #expect(coord.statusStore.connectedPeerName == "Peer")

        coord.stop()

        #expect(coord.statusStore.status == .idle)
        #expect(coord.statusStore.connectedPeerName == nil)
        #expect(t.stopCount >= 1)
    }

    // MARK: lastSyncedAt persistence

    @Test("lastSyncedAt is nil before any sync and set after a successful merge (UserDefaults-written)")
    func lastSyncedPersists() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        let coord = makeCoordinator(transport: t, context: bctx)

        #expect(coord.statusStore.lastSyncedAt == nil)   // "Never" state for the UI

        let data = try snapshotBytes { ctx in
            let e = Expense(amount: Decimal(string: "7")!)
            ctx.insert(e)
            try ctx.save()
        }
        coord.handle(.received(.snapshot(data)))

        #expect(coord.statusStore.lastSyncedAt != nil)
        #expect(UserDefaults.standard.object(forKey: Self.lastSyncedKey) != nil)
    }

    // MARK: merge failure isolation

    @Test("Garbage snapshot → status .error, store unchanged, lastSyncedAt NOT updated")
    func mergeFailureIsIsolated() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let existing = Expense(amount: Decimal(string: "500")!)
        bctx.insert(existing)
        try bctx.save()
        let countBefore = try bctx.fetch(FetchDescriptor<Expense>()).count

        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        coord.handle(.received(.snapshot(Data([0x01, 0x02, 0x03, 0x04]))))

        if case .error = coord.statusStore.status {} else {
            Issue.record("Expected .error status after garbage merge, got \(coord.statusStore.status)")
        }
        #expect(try bctx.fetch(FetchDescriptor<Expense>()).count == countBefore)
        #expect(coord.statusStore.lastSyncedAt == nil)
    }

    // MARK: no-data-loss (LWW, SYNC-05 proven early)

    @Test("Newer local edit survives an older remote snapshot for the same record (LWW)")
    func newerLocalEditSurvives() throws {
        // B holds the record with a NEWER edit; A sends the same syncID with an OLDER updatedAt.
        let (cb, bctx) = try makeStore()
        _ = cb
        let eb = Expense(amount: Decimal(string: "300")!)
        eb.note = "B-newer"
        bctx.insert(eb)
        try bctx.save()
        let sharedSync = eb.syncID
        let bTime = eb.updatedAt

        let olderRemote = try snapshotBytes(device: "A") { ctx in
            let ea = Expense(amount: Decimal(string: "300")!)
            ea.syncID = sharedSync
            ea.note = "A-older"
            ea.updatedAt = bTime.addingTimeInterval(-100)   // strictly older → must lose
            ctx.insert(ea)
            try ctx.save()
        }

        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        coord.handle(.received(.snapshot(olderRemote)))

        #expect(try fetchExpense(bctx, syncID: sharedSync)?.note == "B-newer")
    }
}
