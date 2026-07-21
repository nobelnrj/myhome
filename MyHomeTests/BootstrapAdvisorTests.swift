import Testing
import SwiftData
import Foundation
@testable import MyHome

/// SYNC-05 — BootstrapAdvisor: fresh-install detection, one-shot offer gating, and the
/// never-clobber guarantee that a bootstrap MERGES (never wipes) a non-empty store.
///
/// `@Suite(.serialized)` + a dedicated `UserDefaults(suiteName:)` — the advisor's gate reads a
/// shared UserDefaults flag; the suite must not race other suites, and the injected suite is
/// wiped per test so each case starts from a known state. The never-clobber test reuses the
/// `FakeSyncTransport` pair + `SyncTestSupport` in-memory SchemaV10 containers (SyncCoordinatorTests
/// / SnapshotRoundTripTests fixtures) — the bootstrap path IS the coordinator's snapshot exchange.

/// One user-data entity kind. Emptiness is SCOPE-relative: only kinds bootstrap can actually
/// copy count, because only those can be clobbered. `syncable` drives "makes the store
/// non-empty"; `outOfScope` drives the inverse assertion.
enum BootstrapUserEntity: CaseIterable {
    case expense, note, account, asset, sip, netWorth, pantryItem, shoppingListItem

    @MainActor
    func insert(into ctx: ModelContext) {
        switch self {
        case .pantryItem:
            ctx.insert(PantryItem(name: "Milk", quantity: 1.0, unit: "L", lowStockThreshold: 1.0))
        case .shoppingListItem:
            ctx.insert(ShoppingListItem(name: "Sponges"))
        case .expense:  ctx.insert(Expense(amount: Decimal(string: "100")!))
        case .note:     ctx.insert(Note(title: "n"))
        case .account:  ctx.insert(Account(name: "a"))
        case .asset:    ctx.insert(Asset())
        case .sip:      ctx.insert(SIP(assetID: UUID(), amount: Decimal(string: "500")!))
        case .netWorth: ctx.insert(NetWorthSnapshot())
        }
    }

    var kind: SyncEntityKind {
        switch self {
        case .expense:  return .expense
        case .note:     return .note
        case .account:  return .account
        case .asset:    return .asset
        case .sip:      return .sip
        case .netWorth: return .netWorthSnapshot
        case .pantryItem: return .pantryItem
        case .shoppingListItem: return .shoppingListItem
        }
    }

    static var syncable: [BootstrapUserEntity] {
        allCases.filter { SyncScope.production.isSynced($0.kind) }
    }

    static var outOfScope: [BootstrapUserEntity] {
        allCases.filter { !SyncScope.production.isSynced($0.kind) }
    }
}

@Suite(.serialized)
@MainActor
struct BootstrapAdvisorTests {

    private static let suiteName = "bootstrap-tests"

    /// A wiped, dedicated defaults suite — never touches `UserDefaults.standard`.
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: Self.suiteName)!
        d.removePersistentDomain(forName: Self.suiteName)
        return d
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let c = try SyncTestSupport.makeStore()
        return (c, c.mainContext)
    }

    // MARK: - Emptiness detection

    @Test("A brand-new store is effectively empty")
    func brandNewStoreIsEmpty() throws {
        let (c, ctx) = try makeContext(); _ = c
        #expect(BootstrapAdvisor.isStoreEffectivelyEmpty(context: ctx))
    }

    @Test("A store holding only seeded Categories is still effectively empty")
    func seededCategoriesStillEmpty() throws {
        let (c, ctx) = try makeContext(); _ = c
        for i in 0..<14 {
            ctx.insert(MyHome.Category(name: "Cat\(i)", symbolName: "cart", sortOrder: i))
        }
        try ctx.save()
        #expect(BootstrapAdvisor.isStoreEffectivelyEmpty(context: ctx))
    }

    @Test("ANY single IN-SCOPE user entity makes the store non-empty",
          arguments: BootstrapUserEntity.syncable)
    func userEntityMakesNonEmpty(_ entity: BootstrapUserEntity) throws {
        let (c, ctx) = try makeContext(); _ = c
        entity.insert(into: ctx)
        try ctx.save()
        #expect(BootstrapAdvisor.isStoreEffectivelyEmpty(context: ctx) == false)
    }

    /// The regression this guards: a fresh phone that has already auto-ingested a bank mail
    /// holds an Expense — private, never synced, never clobberable — and must STILL be offered
    /// the notes bootstrap it genuinely needs.
    @Test("An OUT-OF-SCOPE entity leaves the store effectively empty (bootstrap stays available)",
          arguments: BootstrapUserEntity.outOfScope)
    func outOfScopeEntityKeepsStoreEmpty(_ entity: BootstrapUserEntity) throws {
        let (c, ctx) = try makeContext(); _ = c
        entity.insert(into: ctx)
        try ctx.save()
        #expect(BootstrapAdvisor.isStoreEffectivelyEmpty(context: ctx))
    }

    @Test("Under a widened scope, an expense DOES make the store non-empty")
    func emptinessFollowsTheScope() throws {
        let (c, ctx) = try makeContext(); _ = c
        ctx.insert(Expense(amount: Decimal(string: "100")!))
        try ctx.save()
        #expect(BootstrapAdvisor.isStoreEffectivelyEmpty(context: ctx, scope: .all) == false)
    }

    // MARK: - Offer gate

    @Test("shouldOfferBootstrap == true only for an empty store with the flag unset")
    func offerGateEmptyUnset() throws {
        let (c, ctx) = try makeContext(); _ = c
        let d = freshDefaults()
        #expect(BootstrapAdvisor.shouldOfferBootstrap(context: ctx, defaults: d))
    }

    @Test("shouldOfferBootstrap == false once the resolved flag is set (regardless of emptiness)")
    func offerGateResolvedFlag() throws {
        let (c, ctx) = try makeContext(); _ = c
        let d = freshDefaults()
        BootstrapAdvisor.markResolved(defaults: d)
        #expect(BootstrapAdvisor.shouldOfferBootstrap(context: ctx, defaults: d) == false)
    }

    @Test("shouldOfferBootstrap == false for a non-empty store even with the flag unset")
    func offerGateNonEmpty() throws {
        let (c, ctx) = try makeContext(); _ = c
        ctx.insert(Note(title: "already here"))
        try ctx.save()
        let d = freshDefaults()
        #expect(BootstrapAdvisor.shouldOfferBootstrap(context: ctx, defaults: d) == false)
    }

    // MARK: - Never-clobber (SYNC-05 core)

    @Test("Bootstrap MERGES a non-empty store: B keeps its newer edit, gains A's records, loses nothing")
    func bootstrapMergesNeverClobbers() throws {
        let ca = try SyncTestSupport.makeStore()
        let cb = try SyncTestSupport.makeStore()
        let actx = ca.mainContext
        let bctx = cb.mainContext

        let sharedSyncID = UUID()
        let now = Date()

        // A: an OLDER copy of the shared note + a note that exists ONLY on A (proves seeding),
        // plus an expense that must NOT be seeded (out of scope).
        let noteA = Note(title: "A-older")
        noteA.syncID = sharedSyncID
        noteA.updatedAt = now.addingTimeInterval(-100)   // strictly older → must lose
        actx.insert(noteA)
        let onlyOnA = Note(title: "seeded-from-A")
        actx.insert(onlyOnA)
        let moneyOnA = Expense(amount: Decimal(string: "777")!)
        actx.insert(moneyOnA)
        try actx.save()
        let onlyOnASyncID = onlyOnA.syncID

        // B: a NEWER copy of the shared note — its edit MUST survive the exchange.
        let noteB = Note(title: "B-newer")
        noteB.syncID = sharedSyncID
        noteB.updatedAt = now                            // newer → must win (LWW)
        bctx.insert(noteB)
        try bctx.save()

        let notesBefore = try bctx.fetchCount(FetchDescriptor<Note>())

        // The bootstrap path IS the coordinator's connect-time snapshot exchange.
        let (ta, tb) = FakeSyncTransport.linkedPair()
        let coordA = SyncCoordinator(transport: ta, deviceName: "A", pushDebounce: 0, retryBaseDelay: 0.01)
        coordA.setContext(actx)
        let coordB = SyncCoordinator(transport: tb, deviceName: "B", pushDebounce: 0, retryBaseDelay: 0.01)
        coordB.setContext(bctx)
        coordA.start(); coordB.start()

        ta.simulateConnected(peerName: "PhoneB")
        tb.simulateConnected(peerName: "PhoneA")

        // B gained A's record it lacked (SEED) …
        let seeded = try bctx.fetch(FetchDescriptor<Note>()).first { $0.syncID == onlyOnASyncID }
        #expect(seeded?.title == "seeded-from-A")
        // … B's newer edit SURVIVED (never clobbered by A's older copy) …
        let mergedNote = try bctx.fetch(FetchDescriptor<Note>()).first { $0.syncID == sharedSyncID }
        #expect(mergedNote?.title == "B-newer")
        // … and B lost NOTHING: the shared note stayed a single row and gained exactly the one
        // note it lacked (no dup, no delete) …
        #expect(try bctx.fetchCount(FetchDescriptor<Note>()) == notesBefore + 1)
        // … while A's money stayed on A.
        #expect(try bctx.fetch(FetchDescriptor<Expense>()).isEmpty)
    }
}
