import SwiftData
import Foundation

extension ModelContainer {
    /// Creates the app's production ModelContainer, wired to the App Group store URL.
    ///
    /// Store path: group.com.reojacob.myhome / MyHome.store
    /// CloudKit: .none for v1 (local-only); flip to
    ///   .private("iCloud.com.reojacob.myhome") post-paid-developer-upgrade.
    ///
    /// App Group fallback (RESEARCH Open Question 1, Pitfall 5):
    /// On a free Apple Developer account the App Group entitlement may not provision
    /// reliably. If containerURL returns nil, we fall back to .applicationSupportDirectory.
    /// The store file is at the same relative path in both cases so migration is a file copy.
    /// TODO: migrate to App Group URL when paid account active (group.com.reojacob.myhome).
    @MainActor
    static func appContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV4.self)

        // Resolve the App Group container URL; fall back to Application Support if unavailable.
        let storeURL: URL
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.reojacob.myhome") {
            storeURL = groupURL.appendingPathComponent("MyHome.store")
        } else {
            // TODO: migrate to App Group URL when paid account active
            guard let supportURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first else {
                throw CocoaError(.fileNoSuchFile)
            }
            storeURL = supportURL.appendingPathComponent("MyHome.store")
        }

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

/// Seeds the 14 predefined India-tuned categories on first launch (D2-03, EXP-04).
///
/// Idempotent: fetches with fetchLimit = 1 first; if any category exists, returns
/// immediately without inserting duplicates (Pitfall P2-03).
///
/// `internal` (not `private`) so it can be called directly from CategorySeedTests.
@MainActor
func seedCategoriesIfNeeded(context: ModelContext) throws {
    var descriptor = FetchDescriptor<Category>()
    descriptor.fetchLimit = 1
    let existing = try context.fetch(descriptor)
    guard existing.isEmpty else { return }  // already seeded — skip

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
    ]

    let categories = predefined.map {
        Category(name: $0.name, symbolName: $0.symbol, sortOrder: $0.order)
    }
    // Batch insert — avoids repeated single-append (30× perf difference per fatbobman).
    categories.forEach { context.insert($0) }
    // CR-01: persist explicitly — configuration write.
    try context.save()
}
