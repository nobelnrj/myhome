import Testing
import SwiftData
import Foundation
@testable import MyHome

/// `Category` is ambiguous with the Objective-C runtime typedef in test scope — disambiguate.
private typealias Cat = MyHome.Category

// MARK: - Shared fixtures (used by SnapshotRoundTripTests + SnapshotImporterTests)

/// Test support for the merge engine — fresh in-memory SchemaV10 containers and a full-store
/// seed touching every one of the 11 syncable entities + DeletionLog. The engine is proven
/// WITHOUT a device or the App-Group store.
@MainActor
enum SyncTestSupport {

    /// A fresh in-memory container registering the whole SchemaV10 model set.
    static func makeStore() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seed one of every syncable entity: 2 categories, 1 expense linked to both, 1 note + 2
    /// blocks (one carrying a reminderRecurrence blob), 1 account, 1 asset, 1 netWorthSnapshot,
    /// 1 SIP + 1 SIPAmountChange + 1 contribution, 1 routineCompletion, and 1 DeletionLog row.
    @discardableResult
    static func seedFullStore(_ ctx: ModelContext) throws -> UUID {
        let cat1 = Cat(name: "Food", symbolName: "fork.knife", sortOrder: 0)
        let cat2 = Cat(name: "Travel", symbolName: "car", sortOrder: 1)
        cat1.monthlyBudget = Decimal(string: "8000")
        ctx.insert(cat1)
        ctx.insert(cat2)

        let exp = Expense(amount: Decimal(string: "1234.56")!)
        exp.sourceAccount = "user@gmail.com"
        exp.gmailMessageID = "msg-1"
        exp.note = "Weekly groceries"
        exp.categories = [cat1, cat2]
        ctx.insert(exp)

        let note = Note(title: "Groceries")
        ctx.insert(note)
        let blob = try JSONEncoder().encode(["freq": "daily"])
        let b1 = NoteBlock(kindRaw: "checkbox", text: "Milk", order: 0)
        b1.reminderRecurrenceData = blob
        b1.note = note
        let b2 = NoteBlock(kindRaw: "text", text: "Remember eggs", order: 1)
        b2.note = note
        ctx.insert(b1)
        ctx.insert(b2)

        let acct = Account(name: "HDFC")
        acct.balanceBaseline = Decimal(string: "50000")
        ctx.insert(acct)

        let asset = Asset()
        asset.name = "Nifty Index"
        asset.units = Decimal(string: "10.5")
        asset.currentNAV = Decimal(string: "250.75")
        ctx.insert(asset)

        let nw = NetWorthSnapshot()
        nw.totalNetWorth = Decimal(string: "100000")!
        nw.mfValue = Decimal(string: "60000")!
        ctx.insert(nw)

        let sip = SIP(assetID: asset.id, amount: Decimal(string: "5000")!)
        ctx.insert(sip)
        let sac = SIPAmountChange(sipID: sip.id, amount: Decimal(string: "6000")!)
        ctx.insert(sac)
        let contrib = Contribution(
            assetID: asset.id, sipID: sip.id,
            amount: Decimal(string: "5000")!, navUsed: Decimal(string: "100")!,
            unitsAdded: Decimal(string: "50")!
        )
        ctx.insert(contrib)

        let rc = RoutineCompletion(noteID: note.id, dayKey: Date())
        ctx.insert(rc)

        let del = DeletionLog(
            entitySyncID: UUID(),
            entityKindRaw: SyncEntityKind.expense.rawValue,
            deletedAt: Date()
        )
        ctx.insert(del)

        try ctx.save()
        return exp.syncID
    }

    /// Compares every entity collection + deletions of two snapshots (exportedAt/deviceName
    /// deliberately excluded — they always differ). Returns true iff all 12 collections are equal.
    static func entitiesEqual(_ a: SyncSnapshot, _ b: SyncSnapshot) -> Bool {
        a.categories == b.categories
            && a.expenses == b.expenses
            && a.notes == b.notes
            && a.noteBlocks == b.noteBlocks
            && a.accounts == b.accounts
            && a.assets == b.assets
            && a.netWorthSnapshots == b.netWorthSnapshots
            && a.sips == b.sips
            && a.sipAmountChanges == b.sipAmountChanges
            && a.contributions == b.contributions
            && a.routineCompletions == b.routineCompletions
            && a.deletions == b.deletions
    }
}

/// Golden round-trip: the phase's required exit criterion (SYNC success criterion 4). Also pins
/// re-import idempotency (criterion 1) and Decimal integrity.
@MainActor
struct SnapshotRoundTripTests {

    @Test("Golden: export A → import into empty B → export B yields an equal snapshot")
    func goldenRoundTrip() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)

        let snapA = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        let b = try SyncTestSupport.makeStore()
        let stats = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        let snapB = try SnapshotExporter.makeSnapshot(context: b.mainContext, deviceName: "B", scope: .all)

        #expect(SyncTestSupport.entitiesEqual(snapA, snapB))
        // Empty B → everything inserted, nothing deleted/adopted.
        #expect(stats.inserted > 0)
        #expect(stats.deleted == 0)
        #expect(stats.adopted == 0)
    }

    @Test("Golden seed touches all 11 entity types + DeletionLog")
    func goldenSeedIsComplete() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        #expect(snap.categories.count == 2)
        #expect(snap.expenses.count == 1)
        #expect(snap.notes.count == 1)
        #expect(snap.noteBlocks.count == 2)
        #expect(snap.accounts.count == 1)
        #expect(snap.assets.count == 1)
        #expect(snap.netWorthSnapshots.count == 1)
        #expect(snap.sips.count == 1)
        #expect(snap.sipAmountChanges.count == 1)
        #expect(snap.contributions.count == 1)
        #expect(snap.routineCompletions.count == 1)
        #expect(snap.deletions.count == 1)
    }

    @Test("Re-import: merging the same snapshot twice inserts zero and changes no row counts")
    func reImportIsIdempotent() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let snapA = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        let b = try SyncTestSupport.makeStore()
        _ = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        let expensesBefore = try b.mainContext.fetch(FetchDescriptor<Expense>()).count
        let catsBefore = try b.mainContext.fetch(FetchDescriptor<Cat>()).count
        let blocksBefore = try b.mainContext.fetch(FetchDescriptor<NoteBlock>()).count

        let stats2 = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        #expect(stats2.inserted == 0)
        #expect(stats2.deleted == 0)
        #expect(stats2.adopted == 0)
        #expect(try b.mainContext.fetch(FetchDescriptor<Expense>()).count == expensesBefore)
        #expect(try b.mainContext.fetch(FetchDescriptor<Cat>()).count == catsBefore)
        #expect(try b.mainContext.fetch(FetchDescriptor<NoteBlock>()).count == blocksBefore)
    }

    @Test("Decimal integrity: imported expense amount equals Decimal(string:) exactly")
    func decimalIntegrity() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let snapA = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        let b = try SyncTestSupport.makeStore()
        _ = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        let expenses = try b.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.amount == Decimal(string: "1234.56"))
    }

    // MARK: - SyncScope (v1.3: notes only — money never leaves the device)

    @Test("Production export carries notes/blocks/routines and NOTHING else")
    func productionExportIsNotesOnly() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)

        // Default scope == production. The fully-seeded store has one of every entity, so any
        // leak shows up as a non-empty array here.
        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")

        #expect(snap.notes.count == 1)
        #expect(snap.noteBlocks.count == 2)
        #expect(snap.routineCompletions.count == 1)

        #expect(snap.expenses.isEmpty)
        #expect(snap.categories.isEmpty)
        #expect(snap.accounts.isEmpty)
        #expect(snap.assets.isEmpty)
        #expect(snap.netWorthSnapshots.isEmpty)
        #expect(snap.sips.isEmpty)
        #expect(snap.sipAmountChanges.isEmpty)
        #expect(snap.contributions.isEmpty)
    }

    @Test("Money never appears in the exported BYTES, not merely in the decoded arrays")
    func exportedBytesContainNoMoney() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)

        let data = try SnapshotExporter.exportData(context: a.mainContext, deviceName: "A")
        let json = String(decoding: data, as: UTF8.self)

        // Seeded money values and their identifying strings, verbatim from seedFullStore.
        for needle in ["1234.56", "Weekly groceries", "msg-1", "HDFC", "50000",
                       "Nifty Index", "250.75"] {
            #expect(!json.contains(needle), "exported snapshot leaked \(needle)")
        }
    }

    @Test("Import REJECTS out-of-scope rows even when a peer sends them")
    func importRefusesOutOfScopeRows() throws {
        // A hostile/stale peer exports EVERYTHING (scope: .all) …
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let fullSnap = try SnapshotExporter.makeSnapshot(
            context: a.mainContext, deviceName: "A", scope: .all
        )
        #expect(!fullSnap.expenses.isEmpty)   // the payload really does contain money

        // … and B, running the production scope, still takes only the notes.
        let b = try SyncTestSupport.makeStore()
        _ = try SnapshotImporter.merge(fullSnap, into: b.mainContext)

        #expect(try b.mainContext.fetch(FetchDescriptor<Note>()).count == 1)
        #expect(try b.mainContext.fetch(FetchDescriptor<NoteBlock>()).count == 2)
        #expect(try b.mainContext.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(try b.mainContext.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try b.mainContext.fetch(FetchDescriptor<Asset>()).isEmpty)
    }

    @Test("An out-of-scope TOMBSTONE cannot delete local rows")
    func importRefusesOutOfScopeTombstones() throws {
        // B has a local expense the peer must not be able to reach.
        let b = try SyncTestSupport.makeStore()
        let local = Expense(amount: Decimal(string: "999")!)
        b.mainContext.insert(local)
        try b.mainContext.save()

        // A sends a tombstone naming that exact expense.
        let snap = SyncSnapshot(
            exportedAt: Date(),
            deviceName: "A",
            deletions: [DeletionDTO(
                entitySyncID: local.syncID,
                entityKindRaw: SyncEntityKind.expense.rawValue,
                deletedAt: Date().addingTimeInterval(60)   // newer than the local row
            )]
        )
        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        #expect(try b.mainContext.fetch(FetchDescriptor<Expense>()).count == 1)
    }
}
