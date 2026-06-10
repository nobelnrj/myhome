import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Unit tests for RoutineResetService (STAB-04, NOTE-02, D-11, D-12).
///
/// Verifies the per-IST-day reset contract:
///   - Routine notes (isDailyRoutine == true) have their checkbox blocks unchecked once per day.
///   - Non-routine notes are never auto-reset (D-11).
///   - Same-day reactivation is idempotent (D-12).
///   - Only kindRaw == "checkbox" blocks are affected; text blocks are untouched.
@MainActor
struct RoutineResetServiceTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, NoteBlock.self, configurations: config)
    }

    /// Returns the IST start-of-today, computed exactly as RoutineResetService does.
    private func istStartOfToday() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.startOfDay(for: Date())
    }

    /// Returns the IST start-of-yesterday.
    private func istStartOfYesterday() -> Date {
        let today = istStartOfToday()
        return today.addingTimeInterval(-86400)
    }

    // MARK: - Tests

    /// STAB-04 / D-12: A routine note whose routineLastResetDate is yesterday (IST) must have
    /// all its checked checkbox blocks unchecked and its routineLastResetDate stamped to today.
    @Test("resetsRoutineNoteCrossingMidnight: checked blocks cleared and date stamped")
    func resetsRoutineNoteCrossingMidnight() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed a routine note with two checked checkbox blocks
        let note = Note(title: "Morning Routine")
        note.isDailyRoutine = true
        note.routineLastResetDate = istStartOfYesterday()
        context.insert(note)

        let block1 = NoteBlock(kindRaw: "checkbox", text: "Brush teeth", order: 0)
        block1.isChecked = true
        block1.note = note
        context.insert(block1)

        let block2 = NoteBlock(kindRaw: "checkbox", text: "Exercise", order: 1)
        block2.isChecked = true
        block2.note = note
        context.insert(block2)

        try context.save()

        // Run the service
        let service = RoutineResetService()
        service.modelContext = context
        service.resetIfNeeded()

        // Fetch fresh copies and assert
        let notes = try context.fetch(FetchDescriptor<Note>())
        let blocks = try context.fetch(FetchDescriptor<NoteBlock>())

        let fetched = try #require(notes.first)
        #expect(fetched.routineLastResetDate == istStartOfToday(),
                "routineLastResetDate must be stamped to IST start-of-today")
        #expect(blocks.allSatisfy { !$0.isChecked },
                "All checkbox blocks must be unchecked after a cross-midnight reset")
    }

    /// D-11: A note with isDailyRoutine == false must never be auto-reset.
    /// Checked blocks and routineLastResetDate (nil) must remain unchanged.
    @Test("nonRoutineNoteUntouched: checked items and nil date preserved")
    func nonRoutineNoteUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed a non-routine note with a checked checkbox block
        let note = Note(title: "Shopping List")
        note.isDailyRoutine = false
        note.routineLastResetDate = nil
        context.insert(note)

        let block = NoteBlock(kindRaw: "checkbox", text: "Buy milk", order: 0)
        block.isChecked = true
        block.note = note
        context.insert(block)

        try context.save()

        let service = RoutineResetService()
        service.modelContext = context
        service.resetIfNeeded()

        let notes = try context.fetch(FetchDescriptor<Note>())
        let blocks = try context.fetch(FetchDescriptor<NoteBlock>())

        let fetched = try #require(notes.first)
        #expect(fetched.routineLastResetDate == nil,
                "D-11: non-routine note routineLastResetDate must remain nil")
        #expect(blocks.first?.isChecked == true,
                "D-11: non-routine note's checked block must remain checked")
    }

    /// D-12: A routine note already reset today (routineLastResetDate == IST start-of-today)
    /// must not have its blocks touched — intra-day user re-checks are preserved.
    @Test("idempotentSameDay: intra-day re-checks preserved on repeated activation")
    func idempotentSameDay() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed a routine note already reset today, with a block the user re-checked
        let note = Note(title: "Morning Routine")
        note.isDailyRoutine = true
        note.routineLastResetDate = istStartOfToday()   // already reset today
        context.insert(note)

        let block = NoteBlock(kindRaw: "checkbox", text: "Exercise", order: 0)
        block.isChecked = true   // user re-checked it after the morning reset
        block.note = note
        context.insert(block)

        try context.save()

        let service = RoutineResetService()
        service.modelContext = context
        service.resetIfNeeded()

        let blocks = try context.fetch(FetchDescriptor<NoteBlock>())
        #expect(blocks.first?.isChecked == true,
                "D-12: same-day re-check must be preserved — resetIfNeeded must be idempotent")
    }

    /// Only kindRaw == "checkbox" blocks are affected; text blocks on routine notes are untouched.
    @Test("onlyChecklistBlocksAffected: text blocks on routine note remain unchanged")
    func onlyChecklistBlocksAffected() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Seed a routine note with a text block and a checked checkbox block
        let note = Note(title: "Daily Log")
        note.isDailyRoutine = true
        note.routineLastResetDate = istStartOfYesterday()
        context.insert(note)

        let textBlock = NoteBlock(kindRaw: "text", text: "Today I will...", order: 0)
        textBlock.isChecked = false   // text blocks don't use isChecked, but ensure it stays false
        textBlock.note = note
        context.insert(textBlock)

        let checkBlock = NoteBlock(kindRaw: "checkbox", text: "Review notes", order: 1)
        checkBlock.isChecked = true
        checkBlock.note = note
        context.insert(checkBlock)

        try context.save()

        let service = RoutineResetService()
        service.modelContext = context
        service.resetIfNeeded()

        let blocks = try context.fetch(
            FetchDescriptor<NoteBlock>(sortBy: [SortDescriptor(\.order, order: .forward)])
        )
        #expect(blocks.count == 2)
        // Text block: isChecked stays false (untouched)
        let text = try #require(blocks.first(where: { $0.kindRaw == "text" }))
        #expect(!text.isChecked, "Text block must never be touched by reset")
        // Checkbox block: isChecked reset to false
        let checkbox = try #require(blocks.first(where: { $0.kindRaw == "checkbox" }))
        #expect(!checkbox.isChecked, "Checkbox block must be unchecked by reset")
    }
}
