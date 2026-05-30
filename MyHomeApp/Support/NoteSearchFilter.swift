import Foundation

// MARK: - NoteSearchFilter

/// Pure static helper for searching Notes by title and block text (NOT-06, D3-18).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI. Mirrors the BudgetCalculator discipline.
///
/// Threat mitigations:
/// - T-03-08: Uses Swift `localizedCaseInsensitiveContains` — type-safe, no query-string injection.
/// - T-03-09: No note content is logged inside this helper.
enum NoteSearchFilter {

    // MARK: - Public API

    /// Returns `true` when `query` appears in `note.title` OR in any block's `text`.
    ///
    /// Matching is case-insensitive and locale-aware (via `localizedCaseInsensitiveContains`).
    /// An empty `query` matches every note (no-filter state).
    ///
    /// - Parameters:
    ///   - note: The note to test.
    ///   - query: The free-form search string entered by the user.
    static func matches(_ note: Note, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        // Title match
        if note.title.localizedCaseInsensitiveContains(query) {
            return true
        }

        // Block text match — check every block's text field
        let blocks = note.blocks ?? []
        for block in blocks {
            if block.text.localizedCaseInsensitiveContains(query) {
                return true
            }
        }

        return false
    }

    /// Filters an array of notes, keeping only those that match `query`.
    ///
    /// Returns the full array unchanged when `query` is empty (no-filter state).
    ///
    /// - Parameters:
    ///   - notes: Already-fetched array of notes.
    ///   - query: The free-form search string entered by the user.
    static func filter(_ notes: [Note], query: String) -> [Note] {
        guard !query.isEmpty else { return notes }
        return notes.filter { matches($0, query: query) }
    }
}
