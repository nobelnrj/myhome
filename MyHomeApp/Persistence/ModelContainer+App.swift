import SwiftData
import Foundation

/// Raised when the app cannot resolve its single source-of-truth store location.
///
/// We deliberately do NOT fall back to a second store location. A silent fallback (the old
/// behaviour) split the database across the App Group store and Application Support whenever the
/// App Groups entitlement flipped between builds — old notes/routines "vanished" while the OS kept
/// firing their scheduled notifications. Failing loudly surfaces a provisioning problem instead of
/// corrupting the data model. (Decided 2026-07-07 — see [[account-balance-sign-convention]] session.)
enum AppContainerError: LocalizedError {
    case appGroupUnavailable(identifier: String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let id):
            return """
            App Group container "\(id)" could not be resolved. The app uses this as its single \
            source of truth for the SwiftData store. This almost always means the App Groups \
            entitlement is missing or not provisioned for the current signing team — check \
            Signing & Capabilities. Refusing to fall back to a second store location, which would \
            split the database.
            """
        }
    }
}

extension ModelContainer {
    /// Creates the app's production ModelContainer, wired to the App Group store URL.
    ///
    /// Store path: group.com.reojacob.myhome / MyHome.store
    /// CloudKit: .none for v1 (local-only); flip to
    ///   .private("iCloud.com.reojacob.myhome") post-paid-developer-upgrade.
    ///
    /// **Single source of truth (2026-07-07):** the App Group store is the ONLY store location.
    /// If the App Group container cannot be resolved we `throw` rather than silently fall back to
    /// Application Support — the previous fallback split the database when the App Groups
    /// entitlement was toggled between builds, making old data appear lost. See `AppContainerError`.
    static let appGroupIdentifier = "group.com.reojacob.myhome"

    @MainActor
    static func appContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV11.self)

        // Single source of truth: the App Group store. No fallback — fail loudly instead of
        // silently switching stores and splitting the database.
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw AppContainerError.appGroupUnavailable(identifier: appGroupIdentifier)
        }
        let storeURL = groupURL.appendingPathComponent("MyHome.store")

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none  // flip to .private("iCloud.com.reojacob.myhome") post-upgrade
        )

        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )

        // Idempotent seed — runs once on first launch, no-op thereafter (EXP-04, D2-03).
        // CR-01: called before returning to ensure categories are available on first render.
        try seedCategoriesIfNeeded(context: container.mainContext)

        return container
    }
}

// MARK: - Category seeding

/// Seeds the predefined India-tuned categories on first launch (D2-03, EXP-04).
///
/// Idempotent top-up (07-07): inserts only the predefined categories whose names are not
/// already present, so it is safe to run on every launch — fresh installs get the full set,
/// and existing installs pick up categories added in later releases (e.g. "Meat") without
/// duplicating or disturbing user-created categories.
///
/// `internal` (not `private`) so it can be called directly from CategorySeedTests.
@MainActor
func seedCategoriesIfNeeded(context: ModelContext) throws {
    // 07-07: fetch ALL existing categories (not fetchLimit = 1) so we can top-up only the
    // predefined names that are missing, rather than skipping entirely when any exist.
    let existing = try context.fetch(FetchDescriptor<Category>())

    // Source of truth: 02-UI-SPEC.md § "Category Taxonomy Reference"
    let predefined: [(name: String, symbol: String, order: Int)] = [
        ("Groceries",        "cart",                                0),
        ("Dining",           "fork.knife",                          1),
        ("Fuel",             "fuelpump",                            2),
        ("Utilities",        "bolt",                                3),
        ("Rent",             "house",                               4),
        ("Auto/Cab",         "car",                                 5),
        ("Shopping",         "bag",                                 6),
        ("Health/Pharmacy",  "cross.case",                          7),
        ("Entertainment",    "film",                                8),
        ("Recharge/DTH",     "antenna.radiowaves.left.and.right",   9),
        ("Maid/Help",        "person.2",                           10),
        ("UPI to Person",    "arrow.up.right",                     11),
        ("ATM",              "banknote",                           12),
        ("Misc",             "tray",                               13),
        ("Meat",             "flame",                              14),   // 07-07: Licious et al.
        ("Investments",      "chart.line.uptrend.xyaxis",          15),   // 07-07: Groww/BSE/NACH SIPs
    ]

    // 07-07: Top-up seeding. Previously all-or-nothing (skipped entirely if ANY category
    // existed), which meant categories added in a later release never reached users who had
    // already seeded. Now we insert only the predefined categories whose names are missing,
    // preserving user-created categories and any the user renamed.
    let existingNames = Set(existing.compactMap { $0.name })
    let missing = predefined.filter { !existingNames.contains($0.name) }
    guard !missing.isEmpty else { return }

    let categories = missing.map {
        Category(name: $0.name, symbolName: $0.symbol, sortOrder: $0.order)
    }
    // Batch insert — avoids repeated single-append (30× perf difference per fatbobman).
    categories.forEach { context.insert($0) }
    // CR-01: persist explicitly — configuration write.
    try context.save()
}
