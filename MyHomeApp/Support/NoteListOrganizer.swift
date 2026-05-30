import Foundation

// MARK: - NoteListSection

/// The three sections of the Notes list (D3-08, NOT-03, SC-R5).
///
/// Display order: Daily Routine → Pinned → Other.
struct NoteListSections {
    /// Notes with a note-level daily-recurring reminder (SC-R5).
    /// Ordered: preserves the input order (callers pass most-recent-first from @Query).
    let dailyRoutine: [Note]
    /// Notes where `isPinned == true` and not in `dailyRoutine`.
    /// Ordered: preserves input order.
    let pinned: [Note]
    /// All remaining notes (not pinned, not daily-recurring).
    /// Ordered: preserves input order (callers pass most-recent-first → already correct for Other).
    let other: [Note]
}

// MARK: - NoteListOrganizer

/// Pure static helper that partitions a `[Note]` array into the three
/// Notes-list sections: Daily Routine → Pinned → Other.
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI. Mirrors the BudgetCalculator discipline.
///
/// Threat mitigations:
/// - T-03-09: No note title/block text is logged inside this helper.
enum NoteListOrganizer {

    // MARK: - Helpers

    /// Decodes the note-level `reminderRecurrenceData` JSON blob into a
    /// `ReminderRecurrence` value.  Returns `nil` on any decoding failure
    /// (nil data, malformed JSON, etc.) — treated as "no recurrence".
    private static func recurrence(for note: Note) -> ReminderRecurrence? {
        guard let data = note.reminderRecurrenceData else { return nil }
        return try? JSONDecoder().decode(ReminderRecurrence.self, from: data)
    }

    /// Returns `true` when the note's note-level reminder recurrence type is `.daily`.
    private static func isDailyRecurring(_ note: Note) -> Bool {
        recurrence(for: note)?.type == .daily
    }

    // MARK: - Public API

    /// Partitions `notes` into the three display sections.
    ///
    /// - Parameter notes: Already-fetched array, expected to be in modifiedAt-descending order
    ///   from the caller's @Query (so Other preserves that order automatically).
    /// - Returns: `NoteListSections` with dailyRoutine, pinned, other arrays.
    ///
    /// Partition rules:
    /// 1. Daily Routine — note-level recurrence `.daily`, regardless of `isPinned`.
    /// 2. Pinned — `isPinned == true` AND not already in Daily Routine.
    /// 3. Other — everything else, preserving input order (= most-recent-first from @Query).
    static func organize(_ notes: [Note]) -> NoteListSections {
        var dailyRoutine: [Note] = []
        var pinned: [Note] = []
        var other: [Note] = []

        for note in notes {
            if isDailyRecurring(note) {
                dailyRoutine.append(note)
            } else if note.isPinned {
                pinned.append(note)
            } else {
                other.append(note)
            }
        }

        return NoteListSections(dailyRoutine: dailyRoutine, pinned: pinned, other: other)
    }
}
