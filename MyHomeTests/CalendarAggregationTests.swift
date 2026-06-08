import Testing
import Foundation
import SwiftData
@testable import MyHome

// Requirements: SC-R4(a) (per-day reminder counts correct), SC-R4(b) (completion math correct)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/CalendarAggregationTests

/// CalendarAggregationTests — pure-logic tests for per-day reminder aggregation
/// and completion progress math in the Calendar view.
///
/// SC-R4(a): Per-day reminder counts are computed correctly from reminder records.
/// SC-R4(b): Tapped-day agenda completion progress (e.g. 2/5) is computed correctly.
///
/// Tests use an in-memory ModelContainer to construct Note/NoteBlock objects,
/// then call CalendarAggregator's pure functions directly (no @Query, no SwiftUI).
@MainActor
struct CalendarAggregationTests {

    // MARK: - SC-R4(a,b): Per-day counts and completion progress

    @Test("perDayCountsAndProgress: per-day counts and x/y completion math correct — SC-R4(a,b)")
    func perDayCountsAndProgress() throws {
        // Arrange: build an in-memory container and create notes with reminders.
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        // Use a fixed reference date in the device timezone to avoid Pitfall 5.
        // We construct dates at known UTC instants that map to specific local days.
        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        // Reference: today's start-of-day in device timezone.
        let today = cal.startOfDay(for: Date())
        // Tomorrow's start-of-day.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        // A time-of-day within today (e.g. 09:00 local).
        let nineAMToday = cal.date(byAdding: .hour, value: 9, to: today)!
        let tenAMToday  = cal.date(byAdding: .hour, value: 10, to: today)!
        let nineAMTomorrow = cal.date(byAdding: .hour, value: 9, to: tomorrow)!

        // Note A: note-level reminder, today at 9am; two checkbox blocks (one checked, one not)
        let noteA = Note(title: "Morning routine")
        noteA.reminderEnabled = true
        noteA.reminderDate = nineAMToday
        ctx.insert(noteA)

        let blockA1 = NoteBlock(kindRaw: "checkbox", text: "Brush teeth", order: 0)
        blockA1.isChecked = true
        blockA1.note = noteA
        ctx.insert(blockA1)

        let blockA2 = NoteBlock(kindRaw: "checkbox", text: "Make bed", order: 1)
        blockA2.isChecked = false
        blockA2.note = noteA
        ctx.insert(blockA2)

        noteA.blocks = [blockA1, blockA2]

        // Note B: two block-level reminders — one today (checked), one tomorrow (not checked)
        let noteB = Note(title: "Task list")
        ctx.insert(noteB)

        let blockB1 = NoteBlock(kindRaw: "checkbox", text: "Send report", order: 0)
        blockB1.reminderEnabled = true
        blockB1.reminderDate = tenAMToday
        blockB1.isChecked = true
        blockB1.note = noteB
        ctx.insert(blockB1)

        let blockB2 = NoteBlock(kindRaw: "checkbox", text: "Buy groceries", order: 1)
        blockB2.reminderEnabled = true
        blockB2.reminderDate = nineAMTomorrow
        blockB2.isChecked = false
        blockB2.note = noteB
        ctx.insert(blockB2)

        noteB.blocks = [blockB1, blockB2]

        try ctx.save()

        let allNotes = [noteA, noteB]

        // --- SC-R4(a): per-day counts ---
        let counts = CalendarAggregator.perDayCounts(for: allNotes)

        let todayKey = cal.startOfDay(for: today)
        let tomorrowKey = cal.startOfDay(for: tomorrow)

        // Today: 2 reminders (noteA's note-level reminder + blockB1's block-level reminder)
        #expect(counts[todayKey] == 2,
                "Today should have 2 reminders (1 note-level + 1 block-level)")

        // Tomorrow: 1 reminder (blockB2)
        #expect(counts[tomorrowKey] == 1,
                "Tomorrow should have 1 reminder (blockB2)")

        // No other days should appear
        #expect(counts.count == 2, "Only 2 days should have reminders")

        // --- SC-R4(b): completion progress ---

        // Today's progress: 2 total reminders.
        // - noteA note-level: isChecked from noteIsChecked(noteA)
        //   = allBlocks checked? blockA1=true, blockA2=false → NOT checked (false)
        // - blockB1: isChecked = true
        // → done = 1, total = 2
        let todayProgress = CalendarAggregator.progress(for: nineAMToday, notes: allNotes)
        #expect(todayProgress.total == 2,
                "Today's total should be 2")
        #expect(todayProgress.done == 1,
                "Today's done should be 1 (blockB1 is checked; noteA not all-blocks-checked)")
        #expect(todayProgress.fraction == 0.5,
                "Today's fraction should be 0.5 (1/2)")

        // Tomorrow's progress: 1 total, 0 done (blockB2 is not checked)
        let tomorrowProgress = CalendarAggregator.progress(for: nineAMTomorrow, notes: allNotes)
        #expect(tomorrowProgress.total == 1,
                "Tomorrow's total should be 1")
        #expect(tomorrowProgress.done == 0,
                "Tomorrow's done should be 0 (blockB2 is unchecked)")
        #expect(tomorrowProgress.fraction == 0.0,
                "Tomorrow's fraction should be 0.0")

        // Day with no reminders → DayProgress(done: 0, total: 0)
        let nextWeek = cal.date(byAdding: .day, value: 7, to: today)!
        let emptyProgress = CalendarAggregator.progress(for: nextWeek, notes: allNotes)
        #expect(emptyProgress.total == 0, "Day with no reminders should have total 0")
        #expect(emptyProgress.done == 0, "Day with no reminders should have done 0")
        #expect(emptyProgress.fraction == 0.0, "Day with no reminders should have fraction 0.0")
    }

    // MARK: - STAB-01: Tombstone-guard regression tests

    /// STAB-01 — Test A: a tombstoned Note must not appear in aggregation counts.
    ///
    /// Pre-fix: CalendarAggregator.events(from:) accesses note.reminderEnabled on a deleted
    /// Note, causing a SwiftData fault / EXC_BAD_ACCESS crash.
    /// Post-fix: the `modelContext != nil` guard skips tombstoned notes silently.
    @Test("tombstonedNoteIsFilteredFromAggregation — STAB-01")
    func tombstonedNoteIsFilteredFromAggregation() throws {
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let nineAM = cal.date(byAdding: .hour, value: 9, to: today)!

        // Insert a note with a reminder today, then delete it (tombstone it).
        let note = Note(title: "Tombstoned note")
        note.reminderEnabled = true
        note.reminderDate = nineAM
        ctx.insert(note)
        try ctx.save()

        ctx.delete(note)
        try ctx.save()

        // Fetch surviving notes — the deleted note should be absent from SwiftData results.
        let surviving = try ctx.fetch(FetchDescriptor<Note>())

        // Aggregator must return empty counts — tombstoned note absent.
        let counts = CalendarAggregator.perDayCounts(for: surviving)
        #expect(counts.isEmpty,
                "STAB-01: perDayCounts must return empty dict when the only note is tombstoned")
    }

    /// STAB-01 — Test B: a tombstoned NoteBlock must not appear in aggregation counts.
    ///
    /// Pre-fix: CalendarAggregator.events(from:) iterates note.blocks and accesses
    /// block.reminderEnabled on a deleted NoteBlock — fault / crash.
    /// Post-fix: the `modelContext != nil` guard on the block loop skips tombstoned blocks.
    @Test("tombstonedBlockIsFilteredFromAggregation — STAB-01")
    func tombstonedBlockIsFilteredFromAggregation() throws {
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let nineAM = cal.date(byAdding: .hour, value: 9, to: today)!

        // Insert a note with a block-level reminder, then delete the block only (keep parent).
        let note = Note(title: "Parent note")
        ctx.insert(note)

        let block = NoteBlock(kindRaw: "checkbox", text: "Deleted task", order: 0)
        block.reminderEnabled = true
        block.reminderDate = nineAM
        block.note = note
        ctx.insert(block)
        note.blocks = [block]
        try ctx.save()

        ctx.delete(block)
        try ctx.save()

        // Fetch surviving notes (parent note survives; its block was deleted).
        let surviving = try ctx.fetch(FetchDescriptor<Note>())

        // Aggregator must return empty counts — tombstoned block absent.
        let counts = CalendarAggregator.perDayCounts(for: surviving)
        #expect(counts.isEmpty,
                "STAB-01: perDayCounts must return empty dict when the only block is tombstoned")
    }
}
