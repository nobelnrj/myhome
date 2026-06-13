import Testing
import SwiftData
import Foundation
@testable import MyHome

/// RoutineCalendarTests — calendar surfacing and dot-badge invariance for routine notes.
///
/// NOTE-01: Routine notes surface on every day in DayAgendaView via isDailyRoutine filter.
/// D-02:    CalendarAggregator.perDayCounts is NOT affected by routine notes without reminders.
/// D-06/D-08: Completion writes are idempotent per IST day (fetch-before-insert).
///
/// The routineNotes filter logic in DayAgendaView is:
///   notes.filter { note in
///     guard note.modelContext != nil else { return false }
///     return note.isDailyRoutine
///   }
/// These tests assert that exact predicate behaviour over a seeded in-memory container.
@MainActor
struct RoutineCalendarTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Note.self, NoteBlock.self, RoutineCompletion.self,
            configurations: config
        )
    }

    /// Returns the IST start-of-day for a given Date.
    private func istStartOfDay(_ date: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.startOfDay(for: date)
    }

    /// Returns an IST Calendar.
    private func istCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    // MARK: - NOTE-01: routineNotes filter inclusion / exclusion

    /// A note with isDailyRoutine == true must be included in the routineNotes filter.
    @Test("routineNoteIncludedInFilter: isDailyRoutine == true is included — NOTE-01")
    func routineNoteIncludedInFilter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let routine = Note(title: "Morning Routine")
        routine.isDailyRoutine = true
        ctx.insert(routine)
        try ctx.save()

        let allNotes = try ctx.fetch(FetchDescriptor<Note>())

        // Apply the same filter logic as DayAgendaView.routineNotes
        let routineNotes = allNotes.filter { note in
            guard note.modelContext != nil else { return false }
            return note.isDailyRoutine
        }

        #expect(routineNotes.count == 1,
                "A note with isDailyRoutine == true must appear in the routine filter")
        #expect(routineNotes.first?.title == "Morning Routine")
    }

    /// A note with isDailyRoutine == false must be excluded from the routineNotes filter.
    @Test("normalNoteExcludedFromFilter: isDailyRoutine == false is excluded — NOTE-01")
    func normalNoteExcludedFromFilter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let normal = Note(title: "Shopping List")
        normal.isDailyRoutine = false
        ctx.insert(normal)

        let routine = Note(title: "Exercise")
        routine.isDailyRoutine = true
        ctx.insert(routine)

        try ctx.save()

        let allNotes = try ctx.fetch(FetchDescriptor<Note>())

        // Apply the same filter logic as DayAgendaView.routineNotes
        let routineNotes = allNotes.filter { note in
            guard note.modelContext != nil else { return false }
            return note.isDailyRoutine
        }

        #expect(routineNotes.count == 1,
                "Only isDailyRoutine == true notes must appear in the routine filter")
        #expect(routineNotes.allSatisfy { $0.isDailyRoutine },
                "All filtered notes must have isDailyRoutine == true")
        let normalNotes = allNotes.filter { !$0.isDailyRoutine }
        #expect(normalNotes.allSatisfy { note in
            !routineNotes.contains { $0.id == note.id }
        }, "Non-routine notes must not appear in the routine filter")
    }

    // MARK: - D-02: Dot-badge invariance

    /// A routine note with no reminderEnabled reminder must NOT produce a dot badge.
    ///
    /// D-02: CalendarAggregator.perDayCounts must not be inflated by routine notes
    /// that have no enabled reminder. CalendarAggregator is left UNCHANGED — this test
    /// proves the invariant without any aggregator modification.
    @Test("routineWithoutReminderDoesNotProduceDotCount — D-02")
    func routineWithoutReminderDoesNotProduceDotCount() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // A routine note with isDailyRoutine == true but no reminder
        let routine = Note(title: "Daily Meditation")
        routine.isDailyRoutine = true
        routine.reminderEnabled = false
        ctx.insert(routine)
        try ctx.save()

        let allNotes = try ctx.fetch(FetchDescriptor<Note>())

        // CalendarAggregator.perDayCounts must return empty — no reminder means no dot
        let counts = CalendarAggregator.perDayCounts(for: allNotes)
        #expect(counts.isEmpty,
                "D-02: a routine note without a reminderEnabled reminder must not produce a dot badge")
    }

    /// A routine note that ALSO has a reminderEnabled reminder must still produce a dot badge.
    ///
    /// D-02: Existing dot-badge behaviour is preserved — routines with reminders count.
    @Test("routineWithReminderStillProducesDot — D-02 correct existing behaviour preserved")
    func routineWithReminderStillProducesDot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let nineAM = cal.date(byAdding: .hour, value: 9, to: today)!

        // A routine note WITH a reminder enabled on today
        let routine = Note(title: "Morning Standup")
        routine.isDailyRoutine = true
        routine.reminderEnabled = true
        routine.reminderDate = nineAM
        ctx.insert(routine)
        try ctx.save()

        let allNotes = try ctx.fetch(FetchDescriptor<Note>())

        let counts = CalendarAggregator.perDayCounts(for: allNotes)
        let todayKey = cal.startOfDay(for: today)

        #expect(counts[todayKey] == 1,
                "D-02: a routine note WITH a reminderEnabled reminder must still produce a dot badge")
    }

    // MARK: - D-06/D-08: Completion idempotency

    /// Two fetch-before-insert completion writes for the same (noteID, IST dayKey) must
    /// result in exactly one RoutineCompletion row — not two.
    @Test("completionIsIdempotentPerDay — D-06/D-08")
    func completionIsIdempotentPerDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let noteID = UUID()
        let dayKey = istStartOfDay()

        // First write — same fetch-before-insert logic as RoutineAgendaRow.recordCompletion()
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
        )
        if let existing = try ctx.fetch(descriptor).first {
            existing.completedAt = Date()
        } else {
            ctx.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
        }
        try ctx.save()

        // Second write for the same (noteID, dayKey) — must upsert, not insert
        if let existing = try ctx.fetch(descriptor).first {
            existing.completedAt = Date()
        } else {
            ctx.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
        }
        try ctx.save()

        let allCompletions = try ctx.fetch(FetchDescriptor<RoutineCompletion>())
        #expect(allCompletions.count == 1,
                "D-08: two completion writes for the same (noteID, dayKey) must upsert to exactly one record")
    }
}
