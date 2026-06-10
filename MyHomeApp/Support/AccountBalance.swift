import Foundation

/// Pure helper for the live account balance formula (ACCT-05, D-09, D-10).
///
/// Extracted from views so it can be unit-tested without SwiftUI dependencies.
/// Sign convention lives in the data (D-09): credit-card baseline is stored negative
/// (amount owed); savings/current baseline is positive. One formula serves all account types.
///
/// Expense amount convention (app-wide): a SPEND/outflow is stored POSITIVE (AddExpenseView
/// default; BudgetCalculator treats positive as spend, "negative amounts = refunds"); a
/// REFUND/inflow is stored negative. The live balance therefore SUBTRACTS the net of attributed
/// amounts: a spend reduces a savings balance and increases a credit-card amount-owed.
/// (Fixed in Phase 10 — RESEARCH-A3 / human-verify gate: the prior `baseline + net` inverted
/// the sign and was masked by Phase 9 tests that fed negative amounts for spends.)
enum AccountBalance {

    /// Compute the live balance for an account.
    ///
    /// - Parameters:
    ///   - baseline: The opening balance baseline stored on the account. Returns 0 if nil.
    ///   - asOf: The as-of date for the baseline anchor. Returns 0 if nil.
    ///   - expenses: All expenses to filter. Only those with accountID == accountID and
    ///               date >= asOf are included (D-10).
    ///   - accountID: The account's UUID used to filter attributed expenses.
    /// - Returns: baseline − sum(amounts of attributed expenses dated on/after asOf),
    ///            or 0 when baseline or asOf is nil (ACCT-05). Spends (positive amounts)
    ///            reduce a positive savings baseline; refunds (negative) raise it.
    static func compute(
        baseline: Decimal?,
        asOf: Date?,
        expenses: [Expense],
        accountID: UUID
    ) -> Decimal {
        guard let baseline = baseline, let asOf = asOf else { return Decimal(0) }

        // Filter: attributed to this account AND dated on/after the as-of date (D-10).
        let net = expenses
            .filter { $0.accountID == accountID && $0.date >= asOf }
            .reduce(Decimal(0)) { $0 + $1.amount }

        // Subtract: a spend (positive amount) lowers a savings balance; a refund (negative) raises it.
        return baseline - net
    }
}

/// D-03: Infer account type from a label string (case-insensitive keyword match).
///
/// Used by both `MigrationPlan.v5ToV6.didMigrate` (during backfill) and `EditAccountView`
/// (auto-type when the user types an account name). Exposed at module level so tests can
/// call it directly without SwiftUI.
///
/// - Returns: `"credit_card"` if label contains "cc", "credit", or "card" (case-insensitive);
///            `"savings"` otherwise.
func inferAccountType(from label: String) -> String {
    let lower = label.lowercased()
    // Match "cc" only as a standalone word — a plain `contains("cc")` also matches the
    // "cc" inside "a-cc-ount", mis-typing "ICICI Account" / "Savings Account" as
    // credit_card (CR-01). Tokenize on non-alphanumerics so "cc" is a whole-word match.
    let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    if tokens.contains("cc") || lower.contains("credit") || lower.contains("card") {
        return "credit_card"
    }
    return "savings"
}
