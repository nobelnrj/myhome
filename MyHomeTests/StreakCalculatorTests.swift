import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Unit tests for StreakCalculator (NOTE-05, D-07, D-08, Phase 12).
///
/// All streak tests inject a fixed `today` Date and the IST calendar so results are
/// deterministic regardless of when the test runs.
@MainActor
struct StreakCalculatorTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, NoteBlock.self, RoutineCompletion.self, configurations: config)
    }

    private func istCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    /// Returns the IST start-of-day for a given day offset from a reference date.
    /// offset = 0 means the reference date itself; offset = -1 means yesterday, etc.
    private func istDay(offset: Int, from ref: Date, calendar: Calendar) -> Date {
        let todayKey = calendar.startOfDay(for: ref)
        return calendar.date(byAdding: .day, value: offset, to: todayKey)!
    }

    /// Seed a RoutineCompletion for the given noteID and dayKey into the context.
    private func seed(noteID: UUID, dayKey: Date, into context: ModelContext) {
        let c = RoutineCompletion(noteID: noteID, dayKey: dayKey)
        context.insert(c)
    }

    // MARK: - Open Question #1: UUID predicate form (MUST PASS — resolves OQ-1)

    @Test("OQ-1: fetch RoutineCompletion by noteID UUID predicate compiles and works")
    func uuidPredicateFetchCompiles() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let noteID = UUID()
        let cal = istCalendar()
        let dayKey = cal.startOfDay(for: Date())

        // Insert one completion for noteID and one for a different ID
        let c1 = RoutineCompletion(noteID: noteID, dayKey: dayKey)
        let c2 = RoutineCompletion(noteID: UUID(), dayKey: dayKey)
        context.insert(c1)
        context.insert(c2)
        try context.save()

        // Open Question #1: direct UUID comparison in #Predicate — confirmed working in 12-01.
        let capturedNoteID = noteID
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate<RoutineCompletion> { $0.noteID == capturedNoteID }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1, "Fetching by noteID UUID predicate must return exactly 1 matching completion")
        #expect(results.first?.noteID == noteID, "Returned completion must have the matching noteID")
    }

    // MARK: - Streak algorithm tests

    @Test("streak is 0 when no completions exist")
    func streakIsZeroWithNoCompletions() throws {
        let cal = istCalendar()
        let today = cal.startOfDay(for: Date())
        let noteID = UUID()

        let result = StreakCalculator.compute(
            for: noteID,
            completions: [],
            today: today,
            calendar: cal
        )

        #expect(result.currentStreak == 0, "Streak must be 0 when there are no completions")
        #expect(result.history.count == 30, "History must always contain exactly 30 entries")
        #expect(result.history.allSatisfy { !$0.isCompleted }, "All history entries must be not-completed when there are no completions")
    }

    @Test("D-07: incomplete today does NOT break streak — shows yesterday's run")
    func incompleteToday_doesNotBreakStreak() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cal = istCalendar()
        // Fixed reference "today" — not actually today, but deterministic
        let refToday = cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let noteID = UUID()

        // Complete yesterday and the day before, but NOT today
        seed(noteID: noteID, dayKey: istDay(offset: -1, from: refToday, calendar: cal), into: context)
        seed(noteID: noteID, dayKey: istDay(offset: -2, from: refToday, calendar: cal), into: context)
        try context.save()

        let completions = try context.fetch(FetchDescriptor<RoutineCompletion>())
        let result = StreakCalculator.compute(
            for: noteID,
            completions: completions,
            today: refToday,
            calendar: cal
        )

        // Today is not completed. Streak should reflect yesterday's run of 2 consecutive days.
        #expect(result.currentStreak == 2, "D-07: incomplete today must not break the streak; streak should be 2 (yesterday + day before)")
        #expect(result.history.count == 30, "History must always contain 30 entries")
        // today's entry (offset 0) should be not completed
        #expect(!result.history[0].isCompleted, "Today's history entry must be not-completed")
        // yesterday (offset 1) should be completed
        #expect(result.history[1].isCompleted, "Yesterday's history entry must be completed")
    }

    @Test("D-07: streak breaks on fully-missed past day")
    func streakBreaksOnMissedDay() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cal = istCalendar()
        let refToday = cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let noteID = UUID()

        // Complete yesterday and 3 days ago, but NOT 2 days ago (gap creates a break)
        seed(noteID: noteID, dayKey: istDay(offset: -1, from: refToday, calendar: cal), into: context)
        // skip -2 (the gap)
        seed(noteID: noteID, dayKey: istDay(offset: -3, from: refToday, calendar: cal), into: context)
        try context.save()

        let completions = try context.fetch(FetchDescriptor<RoutineCompletion>())
        let result = StreakCalculator.compute(
            for: noteID,
            completions: completions,
            today: refToday,
            calendar: cal
        )

        // Walk: today incomplete → start from yesterday (offset 1). Yesterday = complete → streak=1.
        // 2 days ago = missing → break. Streak = 1.
        #expect(result.currentStreak == 1, "Streak must break at the gap — only yesterday is in the current run")
    }

    @Test("D-07: completing today extends streak by 1")
    func completingTodayExtendsStreak() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cal = istCalendar()
        let refToday = cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let noteID = UUID()

        // Complete today AND yesterday AND day before
        seed(noteID: noteID, dayKey: istDay(offset:  0, from: refToday, calendar: cal), into: context)
        seed(noteID: noteID, dayKey: istDay(offset: -1, from: refToday, calendar: cal), into: context)
        seed(noteID: noteID, dayKey: istDay(offset: -2, from: refToday, calendar: cal), into: context)
        try context.save()

        let completions = try context.fetch(FetchDescriptor<RoutineCompletion>())
        let result = StreakCalculator.compute(
            for: noteID,
            completions: completions,
            today: refToday,
            calendar: cal
        )

        // Today IS completed → startOffset = 0 → streak counts today + yesterday + day before = 3
        #expect(result.currentStreak == 3, "D-07: completing today must extend the streak to include today")
        #expect(result.history[0].isCompleted, "Today's history entry must be completed")
    }

    @Test("D-08: idempotent — second tap on same day upserts, not inserts")
    func idempotentCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let noteID = UUID()
        let cal = istCalendar()
        let dayKey = cal.startOfDay(for: Date())

        // First completion
        let c1 = RoutineCompletion(noteID: noteID, dayKey: dayKey, completedAt: Date())
        context.insert(c1)
        try context.save()

        // Simulate fetch-before-insert idempotency (mirrors recordTodayCompletion pattern)
        let capturedNoteID = noteID
        let capturedDayKey = dayKey
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate<RoutineCompletion> { $0.noteID == capturedNoteID && $0.dayKey == capturedDayKey }
        )
        let existing = try context.fetch(descriptor)
        if let first = existing.first {
            first.completedAt = Date()  // upsert — update existing
        } else {
            context.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
        }
        try context.save()

        // Assert only 1 row exists (idempotent — no duplicate inserted)
        let all = try context.fetch(FetchDescriptor<RoutineCompletion>())
        #expect(all.count == 1, "Idempotent upsert must not insert a duplicate row on second tap")
    }

    // MARK: - Cross-note isolation

    @Test("completions for other noteIDs are ignored")
    func crossNoteCompletionsIgnored() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cal = istCalendar()
        let refToday = cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let noteID = UUID()
        let otherNoteID = UUID()

        // Seed completions for a DIFFERENT note only
        seed(noteID: otherNoteID, dayKey: istDay(offset: -1, from: refToday, calendar: cal), into: context)
        seed(noteID: otherNoteID, dayKey: istDay(offset: -2, from: refToday, calendar: cal), into: context)
        try context.save()

        let completions = try context.fetch(FetchDescriptor<RoutineCompletion>())
        let result = StreakCalculator.compute(
            for: noteID,        // query for noteID, not otherNoteID
            completions: completions,
            today: refToday,
            calendar: cal
        )

        #expect(result.currentStreak == 0, "Cross-note completions must not count toward this note's streak")
        #expect(result.history.count == 30, "History must still have 30 entries")
        #expect(result.history.allSatisfy { !$0.isCompleted }, "All history entries must be not-completed when only other notes have completions")
    }

    // MARK: - History window

    @Test("history array always has exactly 30 entries")
    func historyAlwaysHas30Entries() throws {
        let cal = istCalendar()
        let refToday = cal.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let noteID = UUID()

        let result = StreakCalculator.compute(
            for: noteID,
            completions: [],
            today: refToday,
            calendar: cal
        )

        #expect(result.history.count == 30, "History must contain exactly 30 DayStatus entries")
    }
}
