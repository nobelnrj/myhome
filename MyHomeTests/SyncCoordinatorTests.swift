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

    /// SYNC-06 — the allowlist/pairing surface the coordinator forwards onto (Plan 02).
    var allowlist: Set<String> = []
    var isPairingMode = false

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

    func beginPairing() { isPairingMode = true }
    func endPairing() { isPairingMode = false }

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

    /// SYNC-06 — drive the coordinator's `.pairingCandidate` arm (un-allowlisted peer that
    /// formed a session in pairing mode). Deliberately does NOT set `isConnected`: a candidate
    /// is not a trusted connection.
    func simulatePairingCandidate(peerName: String, peerIID: String) {
        onEvent?(.pairingCandidate(peerName: peerName, peerIID: peerIID))
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

    private func fetchNote(_ ctx: ModelContext, syncID: UUID) throws -> Note? {
        try ctx.fetch(FetchDescriptor<Note>()).first { $0.syncID == syncID }
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

    @Test("Connect exchange: a note in A appears in B, and B's note appears in A — no tap")
    func connectExchangePropagatesBothWays() throws {
        let (ca, actx) = try makeStore()
        let (cb, bctx) = try makeStore()
        _ = ca; _ = cb  // retain containers

        // Notes, not expenses: `SyncScope.production` carries notes only, so a note IS the
        // production payload. Expense propagation is proven NOT to happen — see
        // `expensesNeverCrossTheWire` below.
        let na = Note(title: "from-A")
        actx.insert(na)
        try actx.save()
        let eaSync = na.syncID

        let nb = Note(title: "from-B")
        bctx.insert(nb)
        try bctx.save()
        let ebSync = nb.syncID

        let (ta, tb) = FakeSyncTransport.linkedPair()
        let coordA = makeCoordinator(transport: ta, context: actx)
        let coordB = makeCoordinator(transport: tb, context: bctx)
        coordA.start()
        coordB.start()

        // Symmetric connect — both push; merge is idempotent + LWW, converges in one round.
        ta.simulateConnected(peerName: "PhoneB")
        tb.simulateConnected(peerName: "PhoneA")

        #expect(try fetchNote(bctx, syncID: eaSync)?.title == "from-A")
        #expect(try fetchNote(actx, syncID: ebSync)?.title == "from-B")
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

        // Snapshot that DOES change B (a brand-new note) → merge saves → didSave fires.
        let data = try snapshotBytes { ctx in
            let n = Note(title: "remote")
            ctx.insert(n)
            try ctx.save()
        }
        coord.handle(.received(.snapshot(data)))

        #expect(coord.pendingPushTask == nil)
        #expect(try bctx.fetch(FetchDescriptor<Note>()).count == 1)
    }

    @Test("Converged pair re-exchanging stays bounded — no infinite ping-pong")
    func echoExchangeIsBounded() async throws {
        let (ca, actx) = try makeStore()
        let (cb, bctx) = try makeStore()
        _ = ca; _ = cb

        let ea = Note(title: "A")
        actx.insert(ea); try actx.save()
        let eb = Note(title: "B")
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
            ctx.insert(Note(title: "seven"))
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
        let existing = Note(title: "local")
        bctx.insert(existing)
        try bctx.save()
        let countBefore = try bctx.fetch(FetchDescriptor<Note>()).count

        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        coord.handle(.received(.snapshot(Data([0x01, 0x02, 0x03, 0x04]))))

        if case .error = coord.statusStore.status {} else {
            Issue.record("Expected .error status after garbage merge, got \(coord.statusStore.status)")
        }
        #expect(try bctx.fetch(FetchDescriptor<Note>()).count == countBefore)
        #expect(coord.statusStore.lastSyncedAt == nil)
    }

    // MARK: no-data-loss (LWW, SYNC-05 proven early)

    @Test("Newer local edit survives an older remote snapshot for the same record (LWW)")
    func newerLocalEditSurvives() throws {
        // B holds the record with a NEWER edit; A sends the same syncID with an OLDER updatedAt.
        let (cb, bctx) = try makeStore()
        _ = cb
        let eb = Note(title: "B-newer")
        bctx.insert(eb)
        try bctx.save()
        let sharedSync = eb.syncID
        let bTime = eb.updatedAt

        let olderRemote = try snapshotBytes(device: "A") { ctx in
            let ea = Note(title: "A-older")
            ea.syncID = sharedSync
            ea.updatedAt = bTime.addingTimeInterval(-100)   // strictly older → must lose
            ctx.insert(ea)
            try ctx.save()
        }

        let t = FakeSyncTransport()
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        coord.handle(.received(.snapshot(olderRemote)))

        #expect(try fetchNote(bctx, syncID: sharedSync)?.title == "B-newer")
    }

    // MARK: scope — money never leaves the phone

    @Test("An expense on A never reaches B, even over a fully connected auto-sync link")
    func expensesNeverCrossTheWire() throws {
        let (ca, actx) = try makeStore()
        let (cb, bctx) = try makeStore()
        _ = ca; _ = cb

        // A holds BOTH an expense and a note. Only the note may travel.
        let secret = Expense(amount: Decimal(string: "1234.56")!)
        secret.note = "private-spend"
        actx.insert(secret)
        let shared = Note(title: "shared-note")
        actx.insert(shared)
        try actx.save()
        let noteSync = shared.syncID

        let (ta, tb) = FakeSyncTransport.linkedPair()
        let coordA = makeCoordinator(transport: ta, context: actx)
        let coordB = makeCoordinator(transport: tb, context: bctx)
        coordA.start()
        coordB.start()
        ta.simulateConnected(peerName: "PhoneB")
        tb.simulateConnected(peerName: "PhoneA")

        // The note crossed…
        #expect(try fetchNote(bctx, syncID: noteSync)?.title == "shared-note")
        // …and the expense did not, by any path.
        #expect(try bctx.fetch(FetchDescriptor<Expense>()).isEmpty)

        // Stronger: it is not even present in the bytes A put on the wire.
        for envelope in ta.sentEnvelopes {
            guard case .snapshot(let data) = envelope else { continue }
            #expect(!String(decoding: data, as: UTF8.self).contains("private-spend"))
            #expect(try SnapshotCodec.decode(data).expenses.isEmpty)
        }
    }

    // MARK: SYNC-06 — pairing-window auto-push hole (T-25-03)

    @Test("A pairing candidate in pairing mode pushes NO snapshot and is NOT marked syncing")
    func pairingCandidateNeverPushesSnapshot() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()
        // Even if a session physically exists, an un-allowlisted candidate must never be pushed to.
        t.isConnected = true
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        var captured: (name: String, iid: String)?
        coord.onPairingCandidate = { name, iid in captured = (name, iid) }

        t.simulatePairingCandidate(peerName: "Candidate", peerIID: "rogue-iid-not-in-allowlist")

        // No snapshot envelope was sent to the candidate (the hole is closed)…
        let snapshots = t.sentEnvelopes.filter { if case .snapshot = $0 { return true } else { return false } }
        #expect(snapshots.isEmpty)
        // …status was never driven to .syncing…
        #expect(coord.statusStore.status != .syncing)
        // …and the candidate was forwarded to the pairing UI hook for the code ceremony.
        #expect(captured?.name == "Candidate")
        #expect(captured?.iid == "rogue-iid-not-in-allowlist")
    }

    @Test("A trusted .connected still pushes exactly as before (SC-3 no regression)")
    func trustedConnectedStillPushes() throws {
        let (cb, bctx) = try makeStore()
        _ = cb
        let t = FakeSyncTransport()   // peer nil → send records but does not recurse
        let coord = makeCoordinator(transport: t, context: bctx)
        coord.start()

        t.simulateConnected(peerName: "TrustedPhone")   // sets isConnected = true, emits .connected

        let snapshots = t.sentEnvelopes.filter { if case .snapshot = $0 { return true } else { return false } }
        #expect(snapshots.count == 1)   // the connect-push fired for a trusted peer
    }

    // MARK: SYNC-06 — allowlist never crosses the wire (SC-5 / T-25-04)

    @Test("A snapshot built while paired devices are persisted contains none of their installID/friendlyName bytes")
    func allowlistNeverAppearsInSnapshot() throws {
        // Persist a couple of paired devices in an isolated UserDefaults suite.
        let suiteName = "test.pairedDevices.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PairedDevicesStore(defaults: defaults)
        let iidA = "AAAAAAAA-1111-2222-3333-444444444444"
        let iidB = "BBBBBBBB-5555-6666-7777-888888888888"
        store.add(PairedDevice(installID: iidA, friendlyName: "Reo-iPhone-Secret", pairedAt: .now))
        store.add(PairedDevice(installID: iidB, friendlyName: "Spouse-iPhone-Secret", pairedAt: .now))
        #expect(store.allowlist == [iidA, iidB])

        // Export a snapshot from a POPULATED context (notes + an expense present).
        let data = try snapshotBytes { ctx in
            ctx.insert(Note(title: "shared-note"))
            ctx.insert(Expense(amount: Decimal(string: "42")!))
            try ctx.save()
        }

        // The allowlist is structurally not a SyncSnapshot field, so its bytes never appear.
        let wire = String(decoding: data, as: UTF8.self)
        #expect(!wire.contains(iidA))
        #expect(!wire.contains(iidB))
        #expect(!wire.contains("Reo-iPhone-Secret"))
        #expect(!wire.contains("Spouse-iPhone-Secret"))

        // And the decoded snapshot exposes no field bearing them (belt-and-suspenders).
        let decoded = try SnapshotCodec.decode(data)
        for child in Mirror(reflecting: decoded).children {
            let dump = String(describing: child.value)
            #expect(!dump.contains(iidA))
            #expect(!dump.contains(iidB))
            #expect(!dump.contains("Reo-iPhone-Secret"))
            #expect(!dump.contains("Spouse-iPhone-Secret"))
        }
    }
}
