import Foundation

// MARK: - StreakCalculator types

/// Represents a single day's completion status in the 30-day history window.
struct DayStatus {
    /// IST start-of-day stored as UTC (same convention as RoutineCompletion.dayKey).
    let dayKey: Date
    let isCompleted: Bool
}

/// Result of a streak computation for a single routine note.
struct StreakResult {
    /// D-07: consecutive completed days; an incomplete TODAY does NOT break the streak.
    /// The count reflects the run of completed days ending at yesterday's run (or extended
    /// by today if today is already complete).
    let currentStreak: Int
    /// Last 30 days, newest first. Each entry keyed to IST start-of-day (UTC).
    let history: [DayStatus]
}

// MARK: - StreakCalculator

/// Pure, injectable-calendar streak algorithm over an array of `RoutineCompletion` records.
///
/// Design requirements:
/// - Does NOT call `Date()` internally — `today` and `calendar` are injected for testability.
/// - Filters completions to the given `noteID` so cross-note records are ignored.
/// - Implements D-07 forgiving streak: incomplete TODAY does not break the streak.
/// - History window is exactly 30 entries, newest first.
/// - Streak count is capped at the 30-day window.
///
/// IST calendar discipline: caller must pass `Calendar(identifier: .gregorian)` with
/// `timeZone = TimeZone(identifier: "Asia/Kolkata")!` — mirrors RoutineResetService.swift lines 26-29.
enum StreakCalculator {

    /// Compute the current streak and 30-day history for a single routine note.
    ///
    /// - Parameters:
    ///   - noteID: The routine note's UUID (filters completions to this note only).
    ///   - completions: All `RoutineCompletion` records (unfiltered; cross-note records are ignored).
    ///   - today: The reference "today" date — inject for deterministic tests (do NOT call `Date()` here).
    ///   - calendar: IST Gregorian calendar injected by caller for day-boundary math.
    /// - Returns: `StreakResult` with `currentStreak` and `history` (30 entries, newest first).
    static func compute(
        for noteID: UUID,
        completions: [RoutineCompletion],
        today: Date,
        calendar: Calendar
    ) -> StreakResult {
        // 1. Build the set of completed dayKeys for this note only.
        //    Map each completion's dayKey to calendar.startOfDay so all keys are normalised
        //    to IST midnight (UTC), making Set membership checks reliable.
        let completedDays = Set(
            completions
                .filter { $0.noteID == noteID }
                .map { calendar.startOfDay(for: $0.dayKey) }
        )

        // 2. Build the 30-day history window ending at today (inclusive), newest first.
        //    offset 0 = today, offset 1 = yesterday, …, offset 29 = 29 days ago.
        let todayKey = calendar.startOfDay(for: today)
        var history: [DayStatus] = []
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayKey) else { continue }
            history.append(DayStatus(dayKey: day, isCompleted: completedDays.contains(day)))
        }

        // 3. Compute streak — D-07 forgiving rule:
        //    - If today is already completed: start the walk at offset 0 (today counts).
        //    - If today is NOT yet completed: start at offset 1 (yesterday) — incomplete
        //      today does NOT break the streak.
        //    Walk backward day by day; the first miss (not in completedDays) stops the count.
        //    Cap at 30 to match the history window.
        let todayCompleted = completedDays.contains(todayKey)
        let startOffset: Int = todayCompleted ? 0 : 1
        var streak = 0
        for offset in startOffset... {
            guard offset < 30 else { break }
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayKey) else { break }
            if completedDays.contains(day) {
                streak += 1
            } else {
                break   // first miss ends the streak
            }
        }

        return StreakResult(currentStreak: streak, history: history)
    }
}
