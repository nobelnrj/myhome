import Foundation
import SwiftData

/// @MainActor scan lifecycle coordinator that writes pending transfer pairs (XFER-01).
///
/// Design mirrors `RoutineResetService` (the established @MainActor @Observable service pattern):
/// - Injected `modelContext` set by RootView (same pattern as `routineResetService.modelContext`).
/// - Synchronous `scan()` — no `async`/no `await` (Pitfall 5: STAB-02 risk is eliminated because
///   there is no await boundary between fetch and mutation).
/// - STAB-08-safe fetch: fetches ALL expenses with a plain `FetchDescriptor<Expense>()` then
///   applies `.filter { $0.isTransfer == nil }` in Swift (never `#Predicate` on `Bool?`).
/// - CR-01: single `try context.save()` AFTER the pairing loop (both legs mutated before save,
///   so both commit or both roll back on a throw — atomic per SwiftData save call).
/// - D-09 first-run gate: `UserDefaults` key `"transferScanFirstRunDone"` set after the first
///   successful scan. The `isTransfer == nil` filter already handles incrementality — confirmed
///   and rejected legs are non-nil and naturally skipped on subsequent runs (D-10).
///
/// Pending-pair encoding (D-07, no new schema field):
/// After scoring, `TransferScanService` writes `transferPairID` cross-set on both legs while
/// `isTransfer` stays `nil`. This signals "pending, awaiting user confirm/reject in inbox."
/// State table:
///   - `isTransfer == nil && transferPairID == nil`: unevaluated (never seen by scorer)
///   - `isTransfer == nil && transferPairID != nil`: scorer paired (pending user decision)
///   - `isTransfer == true  && transferPairID != nil`: confirmed transfer pair
///   - `isTransfer == true  && transferPairID == nil`: confirmed solo transfer (manual mark)
///   - `isTransfer == false && transferPairID == nil`: rejected / not a transfer
@MainActor
@Observable
final class TransferScanService {

    /// Injected by RootView.onAppear (same pattern as `gmailSyncController.setContext`).
    var modelContext: ModelContext?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Scans for candidate transfer pairs and writes pending-pair state.
    ///
    /// First run (all expenses have `isTransfer == nil`): evaluates the full historical corpus.
    /// Subsequent runs: the `.filter { $0.isTransfer == nil }` skip rule means confirmed
    /// (`true`) and rejected (`false`) legs are never re-evaluated — incrementality is implicit
    /// (D-09/D-10). No separate "evaluated pairs ledger" is needed.
    ///
    /// This method is synchronous (no `async`/`await`) — safe to call from any `@MainActor`
    /// context (e.g., at the end of `GmailSyncController.syncAccount`, or from a "Scan" button).
    func scan() {
        guard let context = modelContext else { return }

        // IST gregorian calendar — same convention as RoutineResetService (D-05, D-09)
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        do {
            // STAB-08: fetch ALL expenses, then filter in Swift — do NOT use #Predicate on Bool?
            let all = try context.fetch(FetchDescriptor<Expense>())

            // D-09/D-10 skip rule: only isTransfer == nil expenses are candidates
            let candidates = all.filter { $0.isTransfer == nil }

            // WR-01: clear any prior pending-pair links on candidates before re-pairing.
            // Pending legs are re-scored every run; if the optimal pairing changes, a stale
            // back-pointer would otherwise dangle (old partner left pointing at a debit that
            // no longer points back). Confirmed (true) / rejected (false) legs are excluded
            // from `candidates`, so their links are never disturbed.
            for candidate in candidates {
                candidate.transferPairID = nil
            }

            // Pure scoring — returns UUID pairs only (STAB-02 value-type safety)
            let pairs = TransferDetectionScorer.findCandidatePairs(
                from: candidates,
                calendar: istCal
            )

            // Resolve UUIDs back to @Model objects for mutation.
            // Safe: no await boundary between fetch and mutation (Pitfall 5 / STAB-02).
            let expenseByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

            for pair in pairs {
                guard let debit  = expenseByID[pair.debitID],
                      let credit = expenseByID[pair.creditID] else { continue }

                // D-07 pending-pair encoding: write transferPairID cross-set; isTransfer stays nil.
                // A non-nil transferPairID with nil isTransfer == "pending pair, awaiting user decision."
                debit.transferPairID  = credit.id
                credit.transferPairID = debit.id
            }

            // CR-01: single batched save after ALL mutations — atomic commit or rollback
            try context.save()

            // D-09 first-run gate: mark that a full sweep has been completed
            defaults.set(true, forKey: "transferScanFirstRunDone")

        } catch {
            // Non-fatal: log and return — never crash the app on a scan failure
            print("[TransferScanService] scan failed: \(error)")
        }
    }
}
