import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-03 (section ordering), NOT-04 (pin moves to Pinned section), SC-R5 (Daily Routine)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteListOrderingTests

/// NoteListOrderingTests — section ordering and pin logic for the Notes list.
///
/// NOT-03: List ordering = Daily Routine → Pinned → Other (most-recent-first).
/// NOT-04: Toggling isPinned moves a note into/out of the Pinned section.
/// SC-R5:  Daily-recurring notes appear in the Daily Routine section (D3-08).
///
/// These tests are PURE — they use in-memory Note/NoteBlock values constructed directly
/// (no ModelContainer, no @Query) to keep them fast and deterministic.
@MainActor
struct NoteListOrderingTests {

    // MARK: - Helpers

    /// Encodes a ReminderRecurrence to Data (mirrors NoteListOrganizer's decoder path).
    private func recurrenceData(_ type: RecurrenceType, weekdays: [Int]? = nil) -> Data {
        let recurrence = ReminderRecurrence(type: type, weekdays: weekdays)
        return (try? JSONEncoder().encode(recurrence)) ?? Data()
    }

    // MARK: - NOT-03: Section ordering

    @Test("sectionOrdering: Daily Routine → Pinned → Other ordering correct — NOT-03")
    func sectionOrdering() throws {
        // Arrange: one pinned note, one unpinned note, one daily-recurring note.
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        let dailyNote = Note(title: "Daily standup")
        dailyNote.reminderRecurrenceData = recurrenceData(.daily)
        ctx.insert(dailyNote)

        let pinnedNote = Note(title: "Pinned grocery list")
        pinnedNote.isPinned = true
        ctx.insert(pinnedNote)

        let otherNote = Note(title: "Random thought")
        ctx.insert(otherNote)

        try ctx.save()

        let allNotes = [dailyNote, pinnedNote, otherNote]

        // Act
        let sections = NoteListOrganizer.organize(allNotes)

        // Assert
        #expect(sections.dailyRoutine.contains(where: { $0.id == dailyNote.id }),
                "Daily-recurring note must be in Daily Routine section")
        #expect(sections.pinned.contains(where: { $0.id == pinnedNote.id }),
                "Pinned note must be in Pinned section")
        #expect(sections.other.contains(where: { $0.id == otherNote.id }),
                "Unpinned, non-daily note must be in Other section")

        // No cross-contamination
        #expect(!sections.dailyRoutine.contains(where: { $0.id == pinnedNote.id }))
        #expect(!sections.dailyRoutine.contains(where: { $0.id == otherNote.id }))
        #expect(!sections.pinned.contains(where: { $0.id == dailyNote.id }))
        #expect(!sections.pinned.contains(where: { $0.id == otherNote.id }))
        #expect(!sections.other.contains(where: { $0.id == dailyNote.id }))
        #expect(!sections.other.contains(where: { $0.id == pinnedNote.id }))
    }

    // MARK: - NOT-04: Pin moves to Pinned section

    @Test("pinMovesToPinnedSection: toggling isPinned moves note into Pinned section — NOT-04")
    func pinMovesToPinnedSection() throws {
        // Arrange: start with an unpinned note (should be in Other).
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        let note = Note(title: "Important task")
        note.isPinned = false
        ctx.insert(note)
        try ctx.save()

        let beforeSections = NoteListOrganizer.organize([note])
        #expect(beforeSections.other.contains(where: { $0.id == note.id }),
                "Unpinned note starts in Other")
        #expect(beforeSections.pinned.isEmpty, "Pinned section is empty before pin toggle")

        // Act: toggle isPinned → true
        note.isPinned = true
        try ctx.save()

        // Assert: now the note must be in Pinned, not Other
        let afterSections = NoteListOrganizer.organize([note])
        #expect(afterSections.pinned.contains(where: { $0.id == note.id }),
                "After toggling isPinned=true, note must be in Pinned section")
        #expect(afterSections.other.isEmpty,
                "Other section must be empty after note is pinned")
    }

    // MARK: - SC-R5: Daily Routine auto-section

    @Test("dailyRoutineFilter: daily-recurring notes appear in Daily Routine section — SC-R5")
    func dailyRoutineFilter() throws {
        // Arrange: one daily note, one weekly note, one monthly note, one yearly note.
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        let dailyNote = Note(title: "Daily workout")
        dailyNote.reminderRecurrenceData = recurrenceData(.daily)
        ctx.insert(dailyNote)

        let weeklyNote = Note(title: "Weekly review")
        weeklyNote.reminderRecurrenceData = recurrenceData(.weekly, weekdays: [2])
        ctx.insert(weeklyNote)

        let monthlyNote = Note(title: "Monthly bills")
        monthlyNote.reminderRecurrenceData = recurrenceData(.monthly)
        ctx.insert(monthlyNote)

        let yearlyNote = Note(title: "Annual checkup")
        yearlyNote.reminderRecurrenceData = recurrenceData(.yearly)
        ctx.insert(yearlyNote)

        try ctx.save()

        let allNotes = [dailyNote, weeklyNote, monthlyNote, yearlyNote]

        // Act
        let sections = NoteListOrganizer.organize(allNotes)

        // Assert: only daily ends up in Daily Routine
        #expect(sections.dailyRoutine.count == 1,
                "Exactly one note should be in Daily Routine")
        #expect(sections.dailyRoutine.first?.id == dailyNote.id,
                "Only the daily-recurring note belongs in Daily Routine")

        // Weekly, monthly, yearly must NOT be in Daily Routine
        #expect(!sections.dailyRoutine.contains(where: { $0.id == weeklyNote.id }),
                "Weekly note must NOT be in Daily Routine")
        #expect(!sections.dailyRoutine.contains(where: { $0.id == monthlyNote.id }),
                "Monthly note must NOT be in Daily Routine")
        #expect(!sections.dailyRoutine.contains(where: { $0.id == yearlyNote.id }),
                "Yearly note must NOT be in Daily Routine")
    }
}
