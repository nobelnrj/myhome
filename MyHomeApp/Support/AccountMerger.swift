import Foundation

/// Pure logic for merging two accounts that are really one real-world balance (D-MERGE-01).
///
/// Motivating cases:
/// - A **savings account and its debit card** arrive as two ingestion identities but debit the
///   same balance (a debit card is a spending instrument on the savings account, not a separate
///   balance — unlike a credit card).
/// - The **same account masked differently** across emails (`••843` vs `••6843`). The suffix
///   matcher in `AccountAttributionHelper` prevents *new* such splits, but merge cleans up pairs
///   that already exist.
///
/// Merge re-points every expense from the absorbed account onto the survivor and folds the
/// absorbed account's ingestion identities into the survivor's `sourceLabel` alias set, so future
/// emails from either identity attribute to the one surviving account. The caller deletes the
/// absorbed account afterwards (a SwiftData context op kept out of this pure helper).
///
/// Design: operates on `@Model` instances (mutated in place) but performs no persistence,
/// fetching, or SwiftUI work, so it is unit-testable against an in-memory container.
enum AccountMerger {

    /// The outcome of a merge, returned so the caller can persist/delete and report to the user.
    struct MergeResult: Equatable {
        /// The survivor account's id (unchanged).
        let survivorID: UUID
        /// The absorbed account's id — the caller must `ctx.delete` this account.
        let absorbedID: UUID
        /// ids of the expenses whose `accountID` was re-pointed onto the survivor.
        let repointedExpenseIDs: [UUID]
        /// The survivor's `sourceLabel` after folding in the absorbed aliases.
        let mergedSourceLabel: String?
    }

    /// Merges `absorbed` into `survivor`, mutating both models and the affected expenses in place.
    ///
    /// - Re-points every expense in `allExpenses` whose `accountID == absorbed.id` to `survivor.id`.
    /// - Folds the absorbed account's `sourceLabel` aliases into the survivor's (de-duplicated,
    ///   survivor-first order), so `AccountAttributionHelper` routes both identities to the survivor.
    /// - Adopts the absorbed account's `last4` only when the survivor has none (survivor wins).
    /// - Leaves the survivor's `balanceBaseline` / `balanceAsOfDate` untouched — the survivor is the
    ///   account whose baseline the user chose to keep.
    ///
    /// The caller is responsible for `ctx.delete(absorbed)` and `ctx.save()` after this returns.
    ///
    /// - Returns: a `MergeResult` describing what changed. If `absorbed.id == survivor.id` the merge
    ///   is a no-op and returns an empty re-point list.
    @discardableResult
    static func merge(absorbed: Account, into survivor: Account, allExpenses: [Expense]) -> MergeResult {
        guard absorbed.id != survivor.id else {
            return MergeResult(
                survivorID: survivor.id,
                absorbedID: survivor.id,
                repointedExpenseIDs: [],
                mergedSourceLabel: survivor.sourceLabel
            )
        }

        // 1. Re-point the absorbed account's expenses onto the survivor.
        var repointed: [UUID] = []
        for expense in allExpenses where expense.accountID == absorbed.id {
            expense.accountID = survivor.id
            repointed.append(expense.id)
        }

        // 2. Fold ingestion identities: survivor aliases first, then absorbed's (deduped).
        let merged = AccountAttributionHelper.aliases(of: survivor)
            + AccountAttributionHelper.aliases(of: absorbed)
        survivor.sourceLabel = AccountAttributionHelper.sourceLabel(fromAliases: merged)

        // 3. Adopt last4 only if the survivor lacks one (survivor's identity wins).
        if (survivor.last4?.isEmpty ?? true), let absorbedLast4 = absorbed.last4, !absorbedLast4.isEmpty {
            survivor.last4 = absorbedLast4
        }

        return MergeResult(
            survivorID: survivor.id,
            absorbedID: absorbed.id,
            repointedExpenseIDs: repointed,
            mergedSourceLabel: survivor.sourceLabel
        )
    }
}
