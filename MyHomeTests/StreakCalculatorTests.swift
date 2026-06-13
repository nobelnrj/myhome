import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Unit tests for StreakCalculator (NOTE-05, D-07, D-08, Phase 12).
///
/// Wave 0 scaffolds — test bodies with `#expect(Bool(false), "pending 12-02")` compile now
/// and go green in plan 12-02 when StreakCalculator is implemented.
///
/// Also resolves Open Question #1: UUID predicate form for RoutineCompletion.
@MainActor
struct StreakCalculatorTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, NoteBlock.self, RoutineCompletion.self, configurations: config)
    }

    private func istStartOfToday() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.startOfDay(for: Date())
    }

    private var istCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    // MARK: - Open Question #1: UUID predicate form (MUST PASS — resolves OQ-1)

    @Test("OQ-1: fetch RoutineCompletion by noteID UUID predicate compiles and works")
    func uuidPredicateFetchCompiles() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let noteID = UUID()
        let dayKey = istStartOfToday()

        // Insert one completion for noteID and one for a different ID
        let c1 = RoutineCompletion(noteID: noteID, dayKey: dayKey)
        let c2 = RoutineCompletion(noteID: UUID(), dayKey: dayKey)
        context.insert(c1)
        context.insert(c2)
        try context.save()

        // Open Question #1: attempt direct UUID comparison first.
        // If #Predicate { $0.noteID == noteID } compiles (UUID is Equatable and supported
        // by SwiftData's predicate macro), this test passes cleanly.
        // If UUID direct comparison is rejected by the macro at runtime, the fallback
        // ($0.noteID.uuidString == noteID.uuidString) is used instead — recorded in SUMMARY.
        let capturedNoteID = noteID
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate<RoutineCompletion> { $0.noteID == capturedNoteID }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1, "Fetching by noteID UUID predicate must return exactly 1 matching completion")
        #expect(results.first?.noteID == noteID, "Returned completion must have the matching noteID")
    }

    // MARK: - Streak algorithm stubs (pending plan 12-02 StreakCalculator implementation)

    @Test("streak is 0 when no completions exist")
    func streakIsZeroWithNoCompletions() throws {
        // Pending 12-02: StreakCalculator does not exist yet.
        // This test will be wired to StreakCalculator.compute() in plan 12-02.
        Issue.record("pending 12-02: StreakCalculator not yet implemented")
    }

    @Test("D-07: incomplete today does NOT break streak — shows yesterday's run")
    func incompleteToday_doesNotBreakStreak() throws {
        // Pending 12-02: StreakCalculator does not exist yet.
        Issue.record("pending 12-02: StreakCalculator not yet implemented")
    }

    @Test("D-07: streak breaks on fully-missed past day")
    func streakBreaksOnMissedDay() throws {
        // Pending 12-02: StreakCalculator does not exist yet.
        Issue.record("pending 12-02: StreakCalculator not yet implemented")
    }

    @Test("D-07: completing today extends streak by 1")
    func completingTodayExtendsStreak() throws {
        // Pending 12-02: StreakCalculator does not exist yet.
        Issue.record("pending 12-02: StreakCalculator not yet implemented")
    }

    @Test("D-08: idempotent — second tap on same day upserts, not inserts")
    func idempotentCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let noteID = UUID()
        let dayKey = istStartOfToday()

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
}
