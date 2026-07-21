import Testing
import SwiftData
import Foundation
@testable import MyHome

/// `Category` is ambiguous with the Objective-C runtime typedef in test scope — disambiguate.
private typealias Cat = MyHome.Category

/// Behaviour tests for `SnapshotImporter`: tombstones (no-resurrection + propagation), field-level
/// LWW, deterministic identity adoption, relationship wiring, version refusal, and orphan-block
/// skipping — all on in-memory SchemaV10 containers (no device, no App-Group store).
@MainActor
struct SnapshotImporterTests {

    // MARK: - Tombstones

    @Test("No resurrection: an older remote snapshot cannot revive a tombstoned local row")
    func tombstoneBlocksResurrection() throws {
        // A seeds + exports (this snapshot is the OLDER one).
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let snapA = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        // B imports A, then deletes the expense with a tombstone dated AFTER the expense's edit.
        let b = try SyncTestSupport.makeStore()
        _ = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        let expense = try #require(try b.mainContext.fetch(FetchDescriptor<Expense>()).first)
        let expenseSync = expense.syncID
        let tombstoneDate = expense.updatedAt.addingTimeInterval(60)
        b.mainContext.insert(DeletionLog(
            entitySyncID: expenseSync,
            entityKindRaw: SyncEntityKind.expense.rawValue,
            deletedAt: tombstoneDate
        ))
        b.mainContext.delete(expense)
        try b.mainContext.save()

        // Re-merge A's OLDER snapshot: the expense must stay gone and be counted as skipped.
        let stats = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        #expect(try b.mainContext.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(stats.skipped >= 1)

        // Tombstone propagates: B's export now carries the expense's DeletionDTO.
        let snapB = try SnapshotExporter.makeSnapshot(context: b.mainContext, deviceName: "B", scope: .all)
        #expect(snapB.deletions.contains { $0.entitySyncID == expenseSync })
    }

    // MARK: - Field-level LWW

    @Test("LWW: newer remote overwrites local text in place; older remote is ignored")
    func lastWriterWins() throws {
        let b = try SyncTestSupport.makeStore()
        let note = Note(title: "Local title")
        b.mainContext.insert(note)
        try b.mainContext.save()

        let base = SnapshotExporter.dto(note)

        // Newer remote wins.
        var newer = base
        newer.updatedAt = note.updatedAt.addingTimeInterval(100)
        newer.title = "Remote wins"
        let newerSnap = SyncSnapshot(exportedAt: Date(), deviceName: "R", notes: [newer])
        _ = try SnapshotImporter.merge(newerSnap, into: b.mainContext, scope: .all)

        var notes = try b.mainContext.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Remote wins")

        // Older remote loses.
        var older = base
        older.updatedAt = note.updatedAt.addingTimeInterval(-100)
        older.title = "Should be ignored"
        let olderSnap = SyncSnapshot(exportedAt: Date(), deviceName: "R", notes: [older])
        _ = try SnapshotImporter.merge(olderSnap, into: b.mainContext, scope: .all)

        notes = try b.mainContext.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Remote wins")
    }

    // MARK: - Identity adoption

    @Test("Adoption: same-name categories converge to one row with the min syncID")
    func categoryAdoption() throws {
        let b = try SyncTestSupport.makeStore()
        let local = Cat(name: "Food", symbolName: "fork.knife", sortOrder: 0)
        b.mainContext.insert(local)
        try b.mainContext.save()
        let localSync = local.syncID

        let remoteSync = UUID()
        let expectedWinner = localSync.uuidString <= remoteSync.uuidString ? localSync : remoteSync

        let dto = CategoryDTO(
            id: UUID(), syncID: remoteSync, updatedAt: local.updatedAt.addingTimeInterval(10),
            name: " food ", symbolName: "fork.knife", sortOrder: 0,
            monthlyBudget: nil, currencyCode: "INR", createdAt: Date()
        )
        let snap = SyncSnapshot(exportedAt: Date(), deviceName: "R", categories: [dto])
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext, scope: .all)

        let cats = try b.mainContext.fetch(FetchDescriptor<Cat>())
        #expect(cats.count == 1)
        #expect(cats.first?.syncID == expectedWinner)
        #expect(stats.adopted == 1)
    }

    @Test("Adoption: same (sourceAccount, gmailMessageID) expenses converge to one row, min syncID")
    func expenseAdoption() throws {
        let b = try SyncTestSupport.makeStore()
        let local = Expense(amount: Decimal(string: "500")!)
        local.sourceAccount = "user@gmail.com"
        local.gmailMessageID = "bank-msg-42"
        b.mainContext.insert(local)
        try b.mainContext.save()
        let localSync = local.syncID

        let remoteSync = UUID()
        let expectedWinner = localSync.uuidString <= remoteSync.uuidString ? localSync : remoteSync

        let dto = ExpenseDTO(
            id: UUID(), syncID: remoteSync, updatedAt: local.updatedAt.addingTimeInterval(10),
            amount: "500", currencyCode: "INR", date: Date(), note: nil, createdAt: Date(),
            categorySyncIDs: [], rawEmailBody: nil, parserID: nil, parserVersion: nil,
            sourceLabel: nil, gmailMessageID: "bank-msg-42", ingestionStateRaw: nil,
            parseConfidence: nil, sourceAccount: "user@gmail.com", accountID: nil,
            isTransfer: nil, transferPairID: nil
        )
        let snap = SyncSnapshot(exportedAt: Date(), deviceName: "R", expenses: [dto])
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext, scope: .all)

        let expenses = try b.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.syncID == expectedWinner)
        #expect(stats.adopted == 1)
    }

    // MARK: - Relationship wiring

    @Test("Wiring: imported expense links both categories; imported block points at its note")
    func relationshipWiring() throws {
        let a = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(a.mainContext)
        let snapA = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A", scope: .all)

        let b = try SyncTestSupport.makeStore()
        _ = try SnapshotImporter.merge(snapA, into: b.mainContext, scope: .all)

        let expense = try #require(try b.mainContext.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.categories.count == 2)

        let note = try #require(try b.mainContext.fetch(FetchDescriptor<Note>()).first)
        let blocks = try b.mainContext.fetch(FetchDescriptor<NoteBlock>())
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { $0.note?.syncID == note.syncID })
    }

    // MARK: - Version refusal (T-18-06)

    @Test("Version refusal: a schema-9 payload throws and leaves local counts untouched")
    func versionRefusal() throws {
        let b = try SyncTestSupport.makeStore()
        try SyncTestSupport.seedFullStore(b.mainContext)
        let expensesBefore = try b.mainContext.fetch(FetchDescriptor<Expense>()).count
        let catsBefore = try b.mainContext.fetch(FetchDescriptor<Cat>()).count

        let stale = SyncSnapshot(schemaVersion: 9, exportedAt: Date(), deviceName: "Old")
        let data = try SnapshotCodec.encode(stale)

        #expect(throws: SyncError.schemaVersionMismatch(found: 9, expected: 10)) {
            _ = try SnapshotImporter.mergeData(data, into: b.mainContext, scope: .all)
        }

        #expect(try b.mainContext.fetch(FetchDescriptor<Expense>()).count == expensesBefore)
        #expect(try b.mainContext.fetch(FetchDescriptor<Cat>()).count == catsBefore)
    }

    // MARK: - Orphan-block skip

    @Test("Orphan blocks (nil / unresolvable noteSyncID) are never inserted")
    func orphanBlockSkip() throws {
        let b = try SyncTestSupport.makeStore()

        let nilBlock = NoteBlockDTO(
            id: UUID(), syncID: UUID(), updatedAt: Date(), kindRaw: "text", text: "orphan",
            isChecked: false, order: 0, noteSyncID: nil, reminderEnabled: false,
            reminderDate: nil, reminderIsAllDay: false, reminderRecurrenceData: nil,
            reminderEndRuleData: nil, reminderLeadMinutes: 0
        )
        let danglingBlock = NoteBlockDTO(
            id: UUID(), syncID: UUID(), updatedAt: Date(), kindRaw: "text", text: "dangling",
            isChecked: false, order: 1, noteSyncID: UUID(), reminderEnabled: false,
            reminderDate: nil, reminderIsAllDay: false, reminderRecurrenceData: nil,
            reminderEndRuleData: nil, reminderLeadMinutes: 0
        )
        let snap = SyncSnapshot(exportedAt: Date(), deviceName: "R", noteBlocks: [nilBlock, danglingBlock])
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext, scope: .all)

        #expect(try b.mainContext.fetch(FetchDescriptor<NoteBlock>()).isEmpty)
        #expect(stats.skipped >= 2)
    }
}
