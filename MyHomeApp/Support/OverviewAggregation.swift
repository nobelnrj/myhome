import Foundation
import SwiftData

// MARK: - OverviewAggregation

/// Pure static helper for Overview screen aggregation (OVR-01, OVR-02, OVR-03).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData fetching,
/// no @Query, no SwiftUI, no Charts import. Mirrors the CalendarAggregator discipline.
///
/// Three responsibilities:
/// - OVR-01: Aggregate budget threshold (total spend / total budget) → color classification.
/// - OVR-02: Top-3 category ranking by spend (descending, alphabetical tie-break).
/// - OVR-03: Pinned-note resolution via NoteListOrganizer (not isPinned directly — Pitfall E).
enum OverviewAggregation {

    // MARK: - OVR-01: Aggregate threshold

    /// Computes the aggregate fraction-used and budget color for the Overview bar.
    ///
    /// Thresholds mirror `BudgetProgressData.colorThreshold` (D2-09, EXP-08):
    /// - `totalBudget == 0` → `fractionUsed: nil`, `.normal` (no divide-by-zero — T-02-05)
    /// - fraction ≥ 1.0    → `.overBudget`  (boundary inclusive)
    /// - fraction ≥ 0.8    → `.warning`     (boundary inclusive)
    /// - fraction < 0.8    → `.normal`
    ///
    /// `totalSpend` is caller-computed and MUST include uncategorized spend
    /// (Open Question #1 answer: `spendMap.values.reduce(.zero, +) + BudgetCalculator.uncategorizedSpend`).
    ///
    /// Decimal→Double conversion via `NSDecimalNumber(decimal:).doubleValue` (T-04-02 guard).
    static func aggregateThreshold(
        totalSpend: Decimal,
        totalBudget: Decimal
    ) -> (fractionUsed: Double?, color: BudgetColor) {
        guard totalBudget > 0 else {
            return (fractionUsed: nil, color: .normal)
        }
        let fractionUsed = Double(truncating: (totalSpend / totalBudget) as NSDecimalNumber)
        let color: BudgetColor
        if fractionUsed >= 1.0 {
            color = .overBudget
        } else if fractionUsed >= 0.8 {
            color = .warning
        } else {
            color = .normal
        }
        return (fractionUsed: fractionUsed, color: color)
    }

    // MARK: - OVR-02: Top-3 category ranking

    /// Returns up to 3 categories ranked by descending spend, alphabetical tie-break.
    ///
    /// - Parameters:
    ///   - spendByCategory: Per-category spend map keyed by `PersistentIdentifier`
    ///     (from `BudgetCalculator.monthlySpend`).
    ///   - categories: All categories for the current month's expense list.
    /// - Returns: Up to 3 `(category, spent)` pairs with spend > 0, sorted descending.
    ///   Fewer than 3 rows returned when fewer categories have spend (no placeholders).
    static func topCategories(
        spendByCategory: [PersistentIdentifier: Decimal],
        categories: [Category]
    ) -> [(category: Category, spent: Decimal)] {
        categories
            .compactMap { category -> (category: Category, spent: Decimal)? in
                let spent = spendByCategory[category.persistentModelID] ?? .zero
                guard spent > .zero else { return nil }
                return (category: category, spent: spent)
            }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent {
                    return lhs.spent > rhs.spent      // descending by spend
                }
                // Alphabetical tie-break on category name (nil name sorts last)
                let lName = lhs.category.name ?? ""
                let rName = rhs.category.name ?? ""
                return lName < rName
            }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - OVR-03: Pinned-note resolution

    /// Resolves the display note for the Overview pinned-note card.
    ///
    /// Priority (Pitfall E: MUST route through NoteListOrganizer, never isPinned directly):
    /// 1. First pinned note from `NoteListOrganizer.organize(notes).pinned` — daily-routine notes
    ///    are automatically excluded even if their `isPinned == true`.
    /// 2. First note (in input order) that contains a checkbox `NoteBlock` (kindRaw == "checkbox").
    /// 3. `nil` — empty state; Overview card shows a "no notes" prompt.
    ///
    /// Returns the resolved note alongside `isFallback` provenance: `true` when the note
    /// came from the checklist-fallback path (priority 2), `false` when it came from the
    /// pinned path (priority 1) or when there is no note. The caller uses `isFallback`
    /// directly instead of re-running `NoteListOrganizer.organize` to derive the flag —
    /// a single organize call, no divergence risk (WR-02).
    static func pinnedOrChecklistNote(from notes: [Note]) -> (note: Note?, isFallback: Bool) {
        // Priority 1: pinned via NoteListOrganizer (Pitfall E guard)
        let sections = NoteListOrganizer.organize(notes)
        if let pinned = sections.pinned.first {
            return (note: pinned, isFallback: false)
        }

        // Priority 2: fallback to first note with a checkbox block
        let checklist = notes.first { note in
            note.blocks?.contains { $0.kindRaw == "checkbox" } == true
        }
        return (note: checklist, isFallback: checklist != nil)
    }
}
