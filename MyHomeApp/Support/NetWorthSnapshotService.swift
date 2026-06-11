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
/// - `upsertIfNeeded()` is synchronous (IST gate) + wraps compute/persist in `Task {}`
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
    /// Fetches any existing snapshot for today, overwrites totals if found, inserts a new row if not.
    /// Second call on the same IST day is an idempotent overwrite — never produces duplicates.
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
            // Fetch-before-insert upsert (Pitfall 7: no @Attribute(.unique))
            let existing = try context.fetch(
                FetchDescriptor<NetWorthSnapshot>(
                    predicate: #Predicate { $0.date >= todayIST }
                )
            )
            let snapshot: NetWorthSnapshot
            if let first = existing.first {
                snapshot = first
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
