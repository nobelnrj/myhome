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

    /// True when ANY dimension of the filter is active — drives content suppression
    /// (Net Worth / Budgets / Over Time) in Plan 03.
    var isActive: Bool {
        accountFilterActive || dateRange != nil
    }

    /// Returns a copy with the ACCOUNT dimension cleared (keeps any custom date range).
    /// The header scope pill now owns the account dimension only; its one-tap clear resets
    /// accounts without discarding a date range the user set from the left eyebrow.
    func clearingAccounts() -> OverviewFilter {
        var copy = self
        copy.accountIDs = []
        copy.includeUnassigned = false
        return copy
    }

    /// Returns a copy with the custom DATE RANGE cleared (keeps any account subset).
    /// Backs the left eyebrow's tap-to-reset when a custom range is showing, so the two
    /// dimensions are independently resettable.
    func clearingDateRange() -> OverviewFilter {
        var copy = self
        copy.dateRange = nil
        return copy
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

    /// The canonical calendar for Overview financial day-edges (WR-04).
    ///
    /// Bank-mail expense timestamps are IST-anchored, so a custom range's `[start, end]`
    /// boundaries — and the label that discloses them — must be computed against IST day-edges
    /// regardless of the *device* timezone. Without this, a second household phone set to another
    /// region (this is a two-phone-sync app) would build the `@Query` window from its own UTC
    /// offset and include/drop a boundary day's expenses relative to what the label claims.
    ///
    /// Production call sites pass this explicitly instead of relying on ambient `Calendar.current`,
    /// so the UI exercises the same calendar the boundary tests pin. Falls back to `.current` only
    /// if the IST identifier is somehow unavailable.
    static let financialCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        if let ist = TimeZone(identifier: "Asia/Kolkata") {
            cal.timeZone = ist
        }
        return cal
    }()

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

    /// Compact "5 Jun – 12 Jul 2026" range label shared by the Overview header eyebrow and the
    /// scope pill (WR-01 / WR-02: defined once so the header and the pill can never disagree).
    ///
    /// The trailing (to-side) year is always shown. The leading (from-side) year is shown ONLY
    /// when the two endpoints fall in different calendar years, so a cross-year range is never
    /// ambiguous (e.g. "5 Dec 2025 – 12 Jan 2026" rather than the lossy "5 Dec – 12 Jan 2026").
    /// Same-year ranges omit the redundant from-side year to stay compact.
    ///
    /// `calendar` supplies both the year comparison and the formatter time zone, so the label
    /// matches the same day-edges `rangeBoundaries` uses instead of ambient device state (WR-04).
    static func rangeLabel(from: Date, to: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: from) == calendar.component(.year, from: to)

        let fromFmt = DateFormatter()
        fromFmt.locale = .current
        fromFmt.calendar = calendar
        fromFmt.timeZone = calendar.timeZone
        fromFmt.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")

        let toFmt = DateFormatter()
        toFmt.locale = .current
        toFmt.calendar = calendar
        toFmt.timeZone = calendar.timeZone
        toFmt.setLocalizedDateFormatFromTemplate("dMMMyyyy")

        return "\(fromFmt.string(from: from)) – \(toFmt.string(from: to))"
    }
}
