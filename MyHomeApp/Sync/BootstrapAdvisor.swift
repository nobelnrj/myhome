import Foundation
import SwiftData

/// SYNC-05 — the "should we offer to seed this phone from the other one?" advisor.
///
/// PURE decision logic. It NEVER syncs, merges, or exports — the `SyncCoordinator` owns the
/// snapshot exchange (bootstrap is a guided window onto that exchange, NOT a second sync path).
/// This type only answers the two questions the bootstrap UI needs:
///
///   1. Is this store effectively empty — a fresh install with NO user-entered data?
///      Both phones seed the same set of Categories at first launch, so Categories — and the
///      derived/seeded RoutineCompletion + DeletionLog tables — are deliberately IGNORED.
///   2. Should the first-run bootstrap sheet be offered? → empty store AND the one-shot
///      "resolved" flag is unset.
///
/// SwiftData + Foundation only. `@MainActor` because `ModelContext` is main-actor bound.
@MainActor
enum BootstrapAdvisor {

    /// UserDefaults key marking the first-run bootstrap prompt as answered (completed,
    /// "Set up later", or swipe-dismissed). Once set, the prompt never auto-appears again.
    static let resolvedFlagKey = "sync.bootstrapResolved"

    /// True when the store holds no user-entered data OF A SYNCABLE KIND. Uses `fetchCount`
    /// (cheap — no row materialization).
    ///
    /// Scoped to `SyncScope.synced` on purpose: bootstrap can only ever copy in-scope data, so
    /// it can only ever clobber in-scope data. Counting out-of-scope rows here would mean a
    /// fresh phone that has already auto-ingested a bank mail (an Expense — private, never
    /// synced) could never be offered the notes bootstrap it genuinely needs. `DeletionLog` is
    /// still excluded (derived, not user-entered).
    static func isStoreEffectivelyEmpty(context: ModelContext,
                                        scope: SyncScope = .production) -> Bool {
        var counts: [Int] = []
        if scope.isSynced(.note) {
            counts.append((try? context.fetchCount(FetchDescriptor<Note>())) ?? 0)
        }
        if scope.isSynced(.expense) {
            counts.append((try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0)
        }
        if scope.isSynced(.account) {
            counts.append((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0)
        }
        if scope.isSynced(.asset) {
            counts.append((try? context.fetchCount(FetchDescriptor<Asset>())) ?? 0)
        }
        if scope.isSynced(.sip) {
            counts.append((try? context.fetchCount(FetchDescriptor<SIP>())) ?? 0)
        }
        if scope.isSynced(.netWorthSnapshot) {
            counts.append((try? context.fetchCount(FetchDescriptor<NetWorthSnapshot>())) ?? 0)
        }
        // Phase 20: kitchen joined the sync scope (20-02 widened `SyncScope.production` to
        // notes + kitchen). Emptiness is SCOPE-relative, so kitchen rows MUST count now —
        // a phone whose only user data is a stocked pantry is not a fresh install and must
        // not be offered the first-run bootstrap sheet.
        if scope.isSynced(.pantryItem) {
            counts.append((try? context.fetchCount(FetchDescriptor<PantryItem>())) ?? 0)
        }
        if scope.isSynced(.shoppingListItem) {
            counts.append((try? context.fetchCount(FetchDescriptor<ShoppingListItem>())) ?? 0)
        }
        return counts.allSatisfy { $0 == 0 }
    }

    /// Should the first-run bootstrap sheet be offered? Only for a genuinely fresh install
    /// whose owner has not already answered the prompt.
    static func shouldOfferBootstrap(context: ModelContext,
                                     defaults: UserDefaults = .standard,
                                     scope: SyncScope = .production) -> Bool {
        !defaults.bool(forKey: resolvedFlagKey)
            && isStoreEffectivelyEmpty(context: context, scope: scope)
    }

    /// Persist that the prompt has been answered — it never auto-appears again.
    static func markResolved(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: resolvedFlagKey)
    }

    #if DEBUG
    /// DEBUG suppression: keeps the simulator screenshot loop and UI-verification launches
    /// (started with `-seedSampleData` or an explicit `-suppressBootstrapPrompt`) from being
    /// blocked by the first-run sheet. Always `false` in release builds.
    static var isSuppressedByLaunchArguments: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-seedSampleData") || args.contains("-suppressBootstrapPrompt")
    }
    #else
    static var isSuppressedByLaunchArguments: Bool { false }
    #endif
}
