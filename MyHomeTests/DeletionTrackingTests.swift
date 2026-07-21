import Testing
import SwiftData
import Foundation
@testable import MyHome

/// `Category` is ambiguous with the Objective-C runtime typedef in test scope — disambiguate.
private typealias Cat = MyHome.Category

/// SYNC-01 live write-path proof: `ModelContext.deleteSynced` writes a `DeletionLog` tombstone in
/// the same context as the delete, Note deletes cascade-tombstone their blocks, repeated tombstoning
/// is crash-safe, and a real tombstone flows through the Plan-03 engine to delete a record on a peer
/// that still holds it (no resurrection).
@MainActor
struct DeletionTrackingTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SyncTestSupport.makeStore())
    }

    // MARK: - tombstone-on-delete

    @Test("deleteSynced writes a matching tombstone and removes the record")
    func tombstoneOnDelete() throws {
        let ctx = try makeContext()
        let exp = Expense(amount: Decimal(9500))
        ctx.insert(exp)
        try ctx.save()
        let expectedSyncID = exp.syncID
        let before = Date().addingTimeInterval(-1)

        ctx.deleteSynced(exp, kind: .expense)
        try ctx.save()

        // Record is gone.
        #expect(try ctx.fetch(FetchDescriptor<Expense>()).isEmpty)

        // Exactly one tombstone, keyed to the deleted record's syncID/kind, stamped ~now.
        let tombstones = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(tombstones.count == 1)
        let t = try #require(tombstones.first)
        #expect(t.entitySyncID == expectedSyncID)
        #expect(t.entityKindRaw == SyncEntityKind.expense.rawValue)
        #expect(t.deletedAt >= before)
    }

    // MARK: - note-cascade-tombstones

    @Test("deleteSynced on a Note tombstones the note AND every block (cascade)")
    func noteCascadeTombstones() throws {
        let ctx = try makeContext()
        let note = Note(title: "Groceries")
        ctx.insert(note)
        let b1 = NoteBlock(kindRaw: "checkbox", text: "Milk", order: 0)
        b1.note = note
        let b2 = NoteBlock(kindRaw: "text", text: "Eggs", order: 1)
        b2.note = note
        ctx.insert(b1)
        ctx.insert(b2)
        try ctx.save()
        let noteSyncID = note.syncID
        let blockSyncIDs = Set([b1.syncID, b2.syncID])

        ctx.deleteSynced(note, kind: .note)
        try ctx.save()

        // Note + both blocks gone (cascade).
        #expect(try ctx.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<NoteBlock>()).isEmpty)

        // 3 tombstones: 1 note + 2 noteBlock.
        let tombstones = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(tombstones.count == 3)

        let noteTombstones = tombstones.filter { $0.entityKindRaw == SyncEntityKind.note.rawValue }
        #expect(noteTombstones.count == 1)
        #expect(noteTombstones.first?.entitySyncID == noteSyncID)

        let blockTombstones = tombstones.filter { $0.entityKindRaw == SyncEntityKind.noteBlock.rawValue }
        #expect(blockTombstones.count == 2)
        #expect(Set(blockTombstones.map(\.entitySyncID)) == blockSyncIDs)
    }

    // MARK: - idempotent-safe

    @Test("tombstoning the same record twice does not crash (importer dedupes downstream)")
    func repeatedTombstoneIsCrashSafe() throws {
        let ctx = try makeContext()
        let cat = Cat(name: "Food", symbolName: "fork.knife", sortOrder: 0)
        ctx.insert(cat)
        try ctx.save()
        let syncID = cat.syncID

        ctx.deleteSynced(cat, kind: .category)
        try ctx.save()
        // A second tombstone for the same syncID (e.g. a re-run of a cleanup) must not crash;
        // duplicate rows are tolerated (importer keys on entitySyncID / max deletedAt).
        ctx.insert(DeletionLog(entitySyncID: syncID, entityKindRaw: SyncEntityKind.category.rawValue))
        try ctx.save()

        let tombstones = try ctx.fetch(FetchDescriptor<DeletionLog>())
            .filter { $0.entitySyncID == syncID }
        #expect(tombstones.count == 2)
    }

    // MARK: - end-to-end through the Plan-03 engine

    @Test("a deleteSynced tombstone flows through export→merge and removes the record on a peer")
    func tombstonePropagatesThroughEngine() throws {
        // Store B still holds the record (with an older clock).
        let ctxB = try makeContext()
        let sharedSyncID = UUID()
        let expB = Expense(amount: Decimal(9500))
        expB.syncID = sharedSyncID
        expB.updatedAt = Date(timeIntervalSince1970: 1_000)   // old — tombstone must win LWW
        ctxB.insert(expB)
        try ctxB.save()

        // Store A deletes the same record through the live write path, then exports.
        let ctxA = try makeContext()
        let expA = Expense(amount: Decimal(9500))
        expA.syncID = sharedSyncID
        ctxA.insert(expA)
        try ctxA.save()
        ctxA.deleteSynced(expA, kind: .expense)
        try ctxA.save()

        let snapshotData = try SnapshotExporter.exportData(context: ctxA, deviceName: "PhoneA", scope: .all)

        // Merge A's snapshot into B — the record must be removed (no resurrection).
        let stats = try SnapshotImporter.mergeData(snapshotData, into: ctxB, scope: .all)
        #expect(stats.deleted >= 1)
        #expect(try ctxB.fetch(FetchDescriptor<Expense>()).isEmpty)
    }
}
