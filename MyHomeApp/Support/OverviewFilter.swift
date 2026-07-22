import Foundation
import SwiftData

// MARK: - OverviewFilter

/// Value type describing the user's current Overview scope (OVF-01, OVF-02).
///
/// **Pure state, no behavior.** OverviewView holds this in `@State`; the actual
/// filtering math lives in `OverviewFilterEngine`. No SwiftUI, no @Query, no fetching.
///
/// Defaults (`OverviewFilter()`) describe the *all-accounts, current-month* scope:
/// - `accountIDs` empty → every account passes (OVF-01 default).
/// - `dateRange` nil → the view's existing current-month @Query window applies (OVF-02).
///
/// Because the default `init()` produces the neutral scope, `filter = OverviewFilter()`
/// IS the one-tap clear used by the OVF-03 header pill.
struct OverviewFilter: Equatable {
    /// Selected `Account.id` values. EMPTY = all accounts (the OVF-01 default).
    var accountIDs: Set<UUID> = []

    /// When an account subset is selected, also pass expenses whose `accountID == nil`
    /// (the "Unassigned" picker row). Filtered money can never silently vanish.
    /// Irrelevant while `accountIDs` is empty — the all-accounts branch already passes
    /// unassigned rows.
    var includeUnassigned: Bool = false

    /// User-picked, day-granular custom date range; nil = default current-month scope (OVF-02).
    /// Date scoping is applied in the view's @Query predicate via
    /// `OverviewFilterEngine.rangeBoundaries`, not by `apply(_:to:)`.
    var dateRange: ClosedRange<Date>?

    /// True when the account dimension of the filter is narrowing results:
    /// a subset is selected OR "Unassigned" was explicitly toggled.
    var accountFilterActive: Bool {
        !accountIDs.isEmpty || includeUnassigned
    }

    /// True when ANY dimension of the filter is active — drives the OVF-03 header pill
    /// (accent dot + summary label + one-tap clear) in Plan 03.
    var isActive: Bool {
        accountFilterActive || dateRange != nil
    }
}

// MARK: - OverviewFilterEngine

/// Pure static helpers that apply an `OverviewFilter` to already-fetched expenses.
///
/// **Pure contract:** operates on in-memory arrays; no SwiftData fetching, no @Query,
/// no SwiftUI. Mirrors the `OverviewAggregation` / `BudgetCalculator` discipline.
///
/// **Division of labour:**
/// - `apply(_:to:)` handles the ACCOUNT dimension only (membership filtering).
/// - Date scoping stays in the view's @Query predicate, fed by `rangeBoundaries`.
///
/// **Transfer exclusion is NOT this engine's job.** Callers compose `apply(_:to:)` with
/// `BudgetCalculator.grossSpend` / `grossIncome` / `monthlySpend`, which already route
/// through `BudgetCalculator.isTransferForCashFlow` (excludes confirmed AND pending
/// self-transfer pairs). Never re-implement `isTransfer` / `transferPairID` logic here —
/// doing so would let filtered totals diverge from the hero cash-flow readout (T-21-02).
enum OverviewFilterEngine {

    /// True when a single expense passes the filter's ACCOUNT dimension.
    ///
    /// - When the account filter is inactive (`!filter.accountFilterActive`), every
    ///   expense passes — including `accountID == nil` rows (all-accounts default, OVF-01).
    /// - Otherwise the expense passes iff its `accountID` is in `filter.accountIDs`, or
    ///   it is unassigned (`accountID == nil`) and `filter.includeUnassigned` is true.
    static func matchesAccount(_ expense: Expense, filter: OverviewFilter) -> Bool {
        guard filter.accountFilterActive else { return true }
        if let accountID = expense.accountID {
            return filter.accountIDs.contains(accountID)
        }
        return filter.includeUnassigned
    }

    /// Filters `expenses` down to those passing the filter's ACCOUNT dimension.
    ///
    /// Account-membership only — date scoping stays in the view's @Query predicate
    /// (see `rangeBoundaries`). Compose the result with `BudgetCalculator.grossSpend` /
    /// `grossIncome` so the self-transfer exclusion survives filtering (T-21-02).
    static func apply(_ filter: OverviewFilter, to expenses: [Expense]) -> [Expense] {
        expenses.filter { matchesAccount($0, filter: filter) }
    }

    /// Inclusive, day-granular [start, end] boundaries for a custom date range (OVF-02, T-21-01).
    ///
    /// Mirrors the inclusive `[start, end]` convention of `BudgetCalculator.monthBoundaries`
    /// so the existing `date >= lo && date <= hi` @Query predicate keeps working verbatim:
    /// - `start`: `calendar.startOfDay(for: from)` — 00:00:00 on the `from` day.
    /// - `end`:   last second of the `to` day — `startOfDay(to) + 1 day − 1 second` (23:59:59).
    ///
    /// If `from > to` the two are swapped (defensive clamp — T-21-01; never crashes/empties).
    /// `calendar` is injectable so tests can force Asia/Kolkata (IST) day edges instead of
    /// depending on the simulator timezone — same pattern as `AnalyticsAggregator`. Boundaries
    /// are derived entirely via `Calendar` (no manual epoch math).
    static func rangeBoundaries(
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let (lo, hi) = from <= to ? (from, to) : (to, from)
        let start = calendar.startOfDay(for: lo)
        let endDayStart = calendar.startOfDay(for: hi)
        // 23:59:59 on the hi day: next day's 00:00:00 minus one second.
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDayStart)
            ?? hi
        return (start: start, end: end)
    }
}
