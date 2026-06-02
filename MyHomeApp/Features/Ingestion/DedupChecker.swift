import Foundation
import SwiftData

// MARK: - DedupChecker

/// Pure static helper that detects probable duplicate expenses (ING-14, D7-13).
///
/// **Dedup key:** `amount + merchant-substring + date ±1 day`.
/// Caller fetches the existing expenses from SwiftData and passes the array here —
/// DedupChecker does NOT perform any SwiftData queries internally
/// (mirrors `BudgetCalculator` caller-supplies-array pattern).
///
/// **Match rule (D7-13):**
///   1. `existing.amount == candidate.amount`
///   2. Case-insensitive merchant substring overlap:
///      `existing.note` contains `candidate.normalizedMerchant` OR vice-versa.
///      Guard: empty `candidate.normalizedMerchant` → never a substring match.
///   3. `|existing.date − candidate.date| ≤ 86400 s` (24 hours / 1 day).
///
/// A found duplicate always routes to the Review Inbox as "possibleDuplicate" —
/// never silently merged (ING-14 requirement).
struct DedupChecker {

    /// Returns an existing expense that is a probable duplicate of `candidate`, or nil.
    ///
    /// - Parameters:
    ///   - candidate: The newly parsed `ParsedExpense` to check for duplicates.
    ///   - existingExpenses: All expenses fetched from SwiftData by the caller.
    /// - Returns: The first matching `Expense`, or nil if no duplicate is found.
    static func findDuplicate(
        of candidate: ParsedExpense,
        in existingExpenses: [Expense]
    ) -> Expense? {
        let oneDaySeconds: TimeInterval = 86_400

        return existingExpenses.first { existing in
            // 1. Amount must match exactly (Decimal comparison — no precision loss).
            guard existing.amount == candidate.amount else { return false }

            // 2. Merchant substring overlap (case-insensitive).
            //    Uses existing.note as the human-readable merchant field on Expense.
            let existingMerchant = (existing.note ?? "").lowercased()
            let candidateMerchant = candidate.normalizedMerchant.lowercased()
            // Guard: empty candidate merchant is never a valid substring key.
            guard !candidateMerchant.isEmpty else { return false }
            guard existingMerchant.contains(candidateMerchant)
                    || candidateMerchant.contains(existingMerchant) else { return false }

            // 3. Date within ±1 day (86 400 s).
            let delta = abs(existing.date.timeIntervalSince(candidate.date))
            return delta <= oneDaySeconds
        }
    }
}
