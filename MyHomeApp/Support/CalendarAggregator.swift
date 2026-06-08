import Foundation

// MARK: - DayProgress

/// Completion progress for a single calendar day's reminders.
///
/// Exposes the raw done/total counts so the UI can display "2 of 5" or a fraction.
struct DayProgress: Equatable {
    /// Number of reminders due on this day that are marked complete (`isChecked == true`
    /// on their owning NoteBlock, or all blocks checked for note-level reminders).
    let done: Int
    /// Total reminders due on this day (done + not-done).
    let total: Int

    /// Fraction of reminders complete (0.0–1.0). Returns 0.0 when total == 0 (T-guard).
    var fraction: Double {
        total > 0 ? Double(done) / Double(total) : 0.0
    }

    init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

// MARK: - CalendarAggregator

/// Pure static helper for calendar-view aggregation: per-day reminder counts and
/// per-day completion progress (SC-R4(a), SC-R4(b)).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI. Mirrors the BudgetCalculator discipline.
///
/// Calendar fire-date bucketing follows Pitfall 5: all Date values are UTC instants;
/// bucketing into a calendar day is done using `Calendar.current` with
/// `TimeZone.current` (device timezone) so the displayed day matches the user's clock.
///
/// Threat mitigations:
/// - T-03-09: No note/block content is logged inside this helper.
enum CalendarAggregator {

    // MARK: - Private helpers

    /// Returns the start-of-day `Date` for a given `Date` in the device timezone.
    private static func startOfDay(_ date: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal.startOfDay(for: date)
    }

    // MARK: - Reminder enumeration

    /// A lightweight representation of one reminder "event" on a particular day.
    private struct ReminderEvent {
        let dayKey: Date    // startOfDay in device timezone
        let isChecked: Bool // whether the row is checked
    }

    /// Enumerates all reminder events from the given notes.
    ///
    /// A reminder event exists for a note/block when `reminderEnabled == true`
    /// AND `reminderDate != nil`. Events are bucketed by device-timezone start-of-day.
    ///
    /// STAB-01: Both loops guard against tombstoned @Model objects using the established
    /// `modelContext != nil` idiom (mirrors EditNoteView.swift:332). Accessing any stored
    /// property on a tombstoned SwiftData object causes EXC_BAD_ACCESS; the guard skips
    /// these objects silently before any property access.
    private static func events(from notes: [Note]) -> [ReminderEvent] {
        var result: [ReminderEvent] = []

        for note in notes {
            guard note.modelContext != nil else { continue }  // STAB-01: skip tombstoned notes

            // Note-level reminder
            if note.reminderEnabled, let date = note.reminderDate {
                let dayKey = startOfDay(date)
                // For note-level reminders, "checked" = all blocks are checked.
                // If no blocks, treat as not checked (cannot determine).
                let checked = noteIsChecked(note)
                result.append(ReminderEvent(dayKey: dayKey, isChecked: checked))
            }

            // Block-level reminders
            for block in note.blocks ?? [] {
                guard block.modelContext != nil else { continue }  // STAB-01: skip tombstoned blocks
                if block.reminderEnabled, let date = block.reminderDate {
                    let dayKey = startOfDay(date)
                    result.append(ReminderEvent(dayKey: dayKey, isChecked: block.isChecked))
                }
            }
        }

        return result
    }

    /// A note's "checked" status for calendar purposes: true when the note has at least
    /// one block and ALL blocks are checked.
    private static func noteIsChecked(_ note: Note) -> Bool {
        let blocks = note.blocks ?? []
        guard !blocks.isEmpty else { return false }
        return blocks.allSatisfy { $0.modelContext != nil && $0.isChecked }
    }

    // MARK: - Public API

    /// Computes a per-day reminder count map for a set of notes.
    ///
    /// - Parameter notes: Already-fetched notes; may contain note-level and block-level reminders.
    /// - Returns: A dictionary keyed by start-of-day `Date` (device timezone) mapping to the
    ///   number of reminders due on that day. Days with zero reminders are absent from the map.
    static func perDayCounts(for notes: [Note]) -> [Date: Int] {
        let evts = events(from: notes)
        var counts: [Date: Int] = [:]
        for event in evts {
            counts[event.dayKey, default: 0] += 1
        }
        return counts
    }

    /// Computes the completion progress for a specific calendar day.
    ///
    /// - Parameters:
    ///   - day: Any `Date` within the target day (bucketed to start-of-day internally).
    ///   - notes: Already-fetched notes.
    /// - Returns: `DayProgress` with done/total counts.  Returns `DayProgress(done:0, total:0)`
    ///   when no reminders fall on `day`.
    static func progress(for day: Date, notes: [Note]) -> DayProgress {
        let dayKey = startOfDay(day)
        let dayEvents = events(from: notes).filter { $0.dayKey == dayKey }
        let done = dayEvents.filter { $0.isChecked }.count
        return DayProgress(done: done, total: dayEvents.count)
    }
}
