import Foundation
import SwiftData

// MARK: - BudgetColor

/// Color threshold for budget progress visualization (D2-09, EXP-08).
/// Values are never the sole signal — always paired with ₹-remaining / % text.
enum BudgetColor: Equatable {
    case normal      // Color.accentColor — under 80%
    case warning     // Color(.systemOrange) — 80%–99%
    case overBudget  // Color(.systemRed) — ≥100%
}

// MARK: - BudgetProgressData

/// Pure value type for budget progress state.
///
/// All computed properties are derived from `spent`, `budget`, and thresholds.
/// No SwiftUI. No @Query. Consumed by BudgetProgressView.
///
/// Threat mitigations:
/// - T-02-05: `fractionUsed` guards `b > 0` — no divide-by-zero on zero/negative budget.
/// - T-02-04: `Double` used only for visual bar fraction; money math stays `Decimal`.
struct BudgetProgressData {
    let category: Category
    /// Sum of `expense.amount` for the viewed month (negative amounts = refunds, reduce spend).
    let spent: Decimal
    /// The recurring monthly limit for this category (nil = no budget set, D2-06).
    let budget: Decimal?

    /// How much budget remains: `budget - spent`. Negative when over budget.
    /// Returns nil when no budget is set.
    var remaining: Decimal? {
        guard let b = budget else { return nil }
        return b - spent
    }

    /// Fraction of budget consumed: `spent / budget` as a Double for progress bar rendering.
    /// Returns nil when budget is nil or `budget <= 0` (T-02-05 zero-guard).
    /// Uses NSDecimalNumber for Decimal→Double conversion (avoids imprecision).
    var fractionUsed: Double? {
        guard let b = budget, b > 0 else { return nil }
        return Double(truncating: (spent / b) as NSDecimalNumber)
    }

    /// Color threshold for the progress bar (D2-09, EXP-08):
    /// - nil fraction (no budget) → .normal
    /// - fraction ≥ 1.0 → .overBudget  (boundary inclusive at 1.0)
    /// - fraction ≥ 0.8 → .warning     (boundary inclusive at 0.8)
    /// - fraction < 0.8 → .normal
    var colorThreshold: BudgetColor {
        guard let f = fractionUsed else { return .normal }
        if f >= 1.0 { return .overBudget }
        if f >= 0.8 { return .warning }
        return .normal
    }
}

// MARK: - BudgetCalculator

/// Pure static aggregation helpers for budget math.
///
/// All methods operate on already-fetched expense arrays (in-memory reduce).
/// No direct SwiftData fetching — callers supply the arrays (decouples math from @Query).
/// Tested without a ModelContainer for `monthBoundaries`; with a ModelContainer for
/// `monthlySpend`/`uncategorizedSpend` (requires PersistentIdentifier).
struct BudgetCalculator {

    /// Returns total spend per category for the given expense list, keyed by
    /// `PersistentIdentifier` (EXP-09, D2-08).
    ///
    /// - Uses `expense.categories.first` (v1 UI is single-select; schema supports multiple).
    /// - Expenses with empty `categories` are excluded here; they flow to `uncategorizedSpend`.
    /// - Refunds (negative `amount`) reduce the category total.
    static func monthlySpend(
        for expenses: [Expense],
        categories: [Category]
    ) -> [PersistentIdentifier: Decimal] {
        let expenses = expenses.filter { !isTransferForCashFlow($0) } // exclude confirmed + pending transfers
        var totals: [PersistentIdentifier: Decimal] = [:]
        for expense in expenses {
            guard let category = expense.categories.first else { continue }
            let key = category.persistentModelID
            totals[key, default: .zero] += expense.amount
        }
        return totals
    }

    /// Returns the total spend for expenses that have no category (D2-08).
    /// These surface as the "Uncategorized" group in the Budgets tab and are
    /// excluded from per-category budget math.
    static func uncategorizedSpend(for expenses: [Expense]) -> Decimal {
        expenses
            .filter { $0.categories.isEmpty && !isTransferForCashFlow($0) } // exclude confirmed + pending transfers
            .reduce(.zero) { $0 + $1.amount }
    }

    // MARK: - Cash-flow (hero) aggregation

    /// True when an expense should be EXCLUDED from income/spend cash-flow totals because it is —
    /// or is probably — an internal transfer between the user's own accounts.
    ///
    /// Why "probably": the transfer scanner only sets `transferPairID` (a pending pair awaiting the
    /// user's confirm/reject in the inbox); it does NOT set `isTransfer = true`. The old filters
    /// keyed on `isTransfer != true`, so a detected-but-unconfirmed self-transfer still counted as
    /// income and spend — the main driver of the inflated ₹ income and the negative spend total
    /// that clamped the hero orb to 0%. We now exclude a leg as soon as it is paired:
    ///   - `isTransfer == true`  → confirmed transfer → exclude
    ///   - `isTransfer == false` → user rejected the pairing → INCLUDE (real income/spend)
    ///   - `isTransfer == nil`   → exclude iff it has a pending `transferPairID`
    static func isTransferForCashFlow(_ expense: Expense) -> Bool {
        if expense.isTransfer == true { return true }
        if expense.isTransfer == false { return false }
        return expense.transferPairID != nil
    }

    /// Gross spend for the hero cash-flow readout: the sum of positive (debit) amounts of
    /// non-transfer expenses. Unlike `monthlySpend`, this never nets in credits/refunds, so it can
    /// never go negative — the hero orb needs a non-negative spend to render a real percentage
    /// (a negative spend was being clamped to 0% by `max(spent, 0)`).
    static func grossSpend(for expenses: [Expense]) -> Decimal {
        expenses
            .filter { !isTransferForCashFlow($0) && $0.amount > 0 }
            .reduce(.zero) { $0 + $1.amount }
    }

    /// Gross income for the hero cash-flow readout: the sum of |negative| amounts (credits) of
    /// non-transfer expenses. Self-transfers received into an account are excluded once paired, so
    /// moving money between your own accounts no longer shows up as income.
    static func grossIncome(for expenses: [Expense]) -> Decimal {
        expenses
            .filter { !isTransferForCashFlow($0) && $0.amount < 0 }
            .reduce(.zero) { $0 + abs($1.amount) }
    }

    /// Computes inclusive [start, end] boundaries for a calendar month in the
    /// user's local timezone (P2-05, T-02-06).
    ///
    /// - `start`: first instant of the month (day 1, 00:00:00 local time).
    /// - `end`:   last second of the month (last day, 23:59:59 local time).
    ///
    /// Boundaries are returned as absolute `Date` values (UTC-absolute instants)
    /// and can be compared directly in a SwiftData `#Predicate`.
    static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)? {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current   // T-02-06: user's timezone for correct month edges
        guard let start = cal.date(from: month),
              let end = cal.date(
                byAdding: DateComponents(month: 1, second: -1),
                to: start
              )
        else { return nil }
        return (start, end)
    }
}
