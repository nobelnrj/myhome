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

    /// True when the store holds NO user-entered data. Uses `fetchCount` (cheap — no row
    /// materialization) across the six entities that represent user data. Categories, routine
    /// templates, and `DeletionLog` are EXCLUDED (seeded/derived, not user-entered).
    static func isStoreEffectivelyEmpty(context: ModelContext) -> Bool {
        let counts = [
            (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Note>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<Asset>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<SIP>())) ?? 0,
            (try? context.fetchCount(FetchDescriptor<NetWorthSnapshot>())) ?? 0,
        ]
        return counts.allSatisfy { $0 == 0 }
    }

    /// Should the first-run bootstrap sheet be offered? Only for a genuinely fresh install
    /// whose owner has not already answered the prompt.
    static func shouldOfferBootstrap(context: ModelContext,
                                     defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: resolvedFlagKey) && isStoreEffectivelyEmpty(context: context)
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
