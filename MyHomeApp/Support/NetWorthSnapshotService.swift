import Foundation
import SwiftData

// MARK: - NetWorthSnapshotService

/// Daily upsert service for `NetWorthSnapshot` rows (ASSET-08, D-08, D-09).
///
/// Fires on `scenePhase .active` (via RootView.onChange) — exactly one snapshot per IST day.
/// Uses fetch-before-insert upsert (no `@Attribute(.unique)` — CloudKit rule, Pitfall 7).
///
/// Design mirrors `RoutineResetService`:
/// - `@MainActor @Observable final class`, injected `modelContext: ModelContext?`
/// - `upsertIfNeeded()` wraps compute/persist in `Task {}`; the upsert is an idempotent
///   in-place overwrite of today's row, so it runs unconditionally per foreground (WR-04)
/// - Non-fatal catch (print only — mirrors D-07 silent-failure pattern)
///
/// Reuses `NetWorthCalculator.breakdown()` which in turn reuses `AccountBalance.compute()`
/// (T-11-07: sign convention is correct — never re-implements the balance formula).
@MainActor
@Observable
final class NetWorthSnapshotService {

    // MARK: - Public state

    /// Injected by RootView.onAppear.
    var modelContext: ModelContext?

    // MARK: - Entry point

    /// Upsert today's IST net-worth snapshot (D-08).
    ///
    /// WR-04: intentionally UNCONDITIONAL — runs on every `.active` scene phase rather than
    /// gating to once per IST day. The bounded, idempotent upsert in `performUpsert` (CR-01)
    /// overwrites *today's* row in place and never creates a duplicate, so re-running keeps
    /// today's trend point current with the latest holdings/balances (e.g. after the user adds
    /// a holding later the same day). The aggregate is small (household scale), so the redundant
    /// compute per foreground is acceptable for v1; a daily gate is deliberately NOT used.
    func upsertIfNeeded() {
        guard let context = modelContext else { return }
        Task { await performUpsert(context: context) }
    }

    // MARK: - Private upsert

    private func performUpsert(context: ModelContext) async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = cal.startOfDay(for: Date())

        do {
            // Fetch-before-insert upsert (Pitfall 7: no @Attribute(.unique)).
            // CR-01: bound the predicate to the [todayIST, tomorrowIST) half-open range so a
            // future-dated row (clock skew / CloudKit cross-device) is never picked and clobbered.
            let tomorrowIST = cal.date(byAdding: .day, value: 1, to: todayIST)!
            let existing = try context.fetch(
                FetchDescriptor<NetWorthSnapshot>(
                    predicate: #Predicate { $0.date >= todayIST && $0.date < tomorrowIST }
                )
            )
            let snapshot: NetWorthSnapshot
            if let first = existing.first {
                snapshot = first
                // Defensive: if duplicate today-rows somehow exist, keep one and delete the rest.
                for dup in existing.dropFirst() { context.deleteSynced(dup, kind: .netWorthSnapshot) }
            } else {
                let s = NetWorthSnapshot()
                context.insert(s)
                snapshot = s
            }

            // Aggregate current state using NetWorthCalculator (reuses AccountBalance.compute)
            let assets = try context.fetch(FetchDescriptor<Asset>())
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let expenses = try context.fetch(FetchDescriptor<Expense>())

            let bd = NetWorthCalculator.breakdown(assets: assets, accounts: accounts, expenses: expenses)

            snapshot.date = todayIST
            snapshot.totalNetWorth = bd.totalNetWorth
            snapshot.mfValue = bd.mfValue
            snapshot.stockValue = bd.stockValue
            snapshot.npsValue = bd.npsValue
            snapshot.cashValue = bd.cashValue

            try context.save()

        } catch {
            // Non-fatal: log and return (mirrors RoutineResetService / D-07)
            print("[NetWorthSnapshotService] upsert failed: \(error)")
        }
    }
}
