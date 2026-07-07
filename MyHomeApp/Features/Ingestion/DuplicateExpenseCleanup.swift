import Foundation
import SwiftData

// MARK: - DuplicateExpenseCleanup

/// One-time maintenance pass that removes exact-duplicate ingested expenses.
///
/// **Why this exists:** before `GmailSyncController.sync()` had a re-entrancy guard, two
/// overlapping sync runs (background refresh + a manual "Sync now", or two taps) could each
/// snapshot the pre-loop existing-expenses set and both insert the same Gmail messages. This
/// produced byte-identical expenses — same `gmailMessageID`, `sourceAccount`, amount, and a
/// same-second `createdAt` — which doubled every total on the Overview (spend hero, donut,
/// budgets). This pass repairs stores that already accumulated such duplicates.
///
/// **Dedup key:** `(sourceAccount, gmailMessageID)` — the same idempotency key the sync loop
/// uses (D-MA-01/03). A Gmail message ID is unique within a mailbox, so grouping by account +
/// message ID never merges two genuinely different transactions.
///
/// **Safety rules:**
/// - Manual expenses (`gmailMessageID == nil`) are never touched — they can't be re-derived.
/// - Within a duplicate group, the **earliest** `createdAt` is kept (the original insert);
///   ties break on the stable `id` so the choice is deterministic. Any row the user has since
///   marked/paired is not special-cased — the "auto-delete, keep earliest" behaviour is
///   intentional and predictable (chosen 2026-07-07).
enum DuplicateExpenseCleanup {

    /// Pure function: given all expenses, returns the ones that should be deleted (every
    /// member of a `(sourceAccount, gmailMessageID)` group except the earliest-created).
    ///
    /// Deterministic and side-effect free so it can be unit-tested without SwiftData.
    static func duplicatesToDelete(in expenses: [Expense]) -> [Expense] {
        // Group only ingested expenses (non-nil messageID). Key on account + message ID.
        var groups: [String: [Expense]] = [:]
        for expense in expenses {
            guard let msgID = expense.gmailMessageID else { continue }
            let key = "\(expense.sourceAccount ?? "")\u{1F}\(msgID)"
            groups[key, default: []].append(expense)
        }

        var toDelete: [Expense] = []
        for (_, members) in groups where members.count > 1 {
            // Keep the earliest createdAt; tie-break on id for determinism.
            let sorted = members.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            toDelete.append(contentsOf: sorted.dropFirst())
        }
        return toDelete
    }

    /// Fetches all expenses, deletes the duplicates, and saves. Returns the number removed.
    /// No-op (returns 0) when the store is clean, so it is cheap to run on every launch.
    @discardableResult
    @MainActor
    static func run(in context: ModelContext) -> Int {
        guard let expenses = try? context.fetch(FetchDescriptor<Expense>()) else { return 0 }
        let victims = duplicatesToDelete(in: expenses)
        guard !victims.isEmpty else { return 0 }
        for expense in victims { context.delete(expense) }
        try? context.save()
        return victims.count
    }
}
