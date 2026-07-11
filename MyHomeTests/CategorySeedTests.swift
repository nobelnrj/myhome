import Testing
import SwiftData
import Foundation
@testable import MyHome

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// Category seeding tests — verifies EXP-04 idempotent first-launch seeding.
///
/// Uses an in-memory ModelContainer per test (FND-06, Pitfall 16).
/// Calls `seedCategoriesIfNeeded(context:)` directly (internal visibility required).
@MainActor
struct CategorySeedTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    @Test("16 predefined categories are seeded on empty store")
    func seedsOnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)
        let all = try context.fetch(FetchDescriptor<Cat>())
        #expect(all.count == 16, "Expected 16 predefined categories, got \(all.count)")
        #expect(all.contains { $0.name == "Meat" }, "Expected the Meat category to be seeded (07-07)")
        #expect(all.contains { $0.name == "Investments" }, "Expected the Investments category to be seeded (07-07)")
    }

    @Test("Seeding is idempotent — no duplicates on second run")
    func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)
        try seedCategoriesIfNeeded(context: context)   // second call must be a no-op
        let all = try context.fetch(FetchDescriptor<Cat>())
        #expect(all.count == 16, "Expected 16 categories after two seed calls, got \(all.count)")
    }

    @Test("Top-up seeding adds only missing categories, preserves existing — 07-07")
    func topUpAddsOnlyMissing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        // Simulate an older install that was seeded before "Meat" existed: insert a couple of
        // predefined categories plus a user-created one.
        context.insert(Cat(name: "Groceries", symbolName: "cart", sortOrder: 0))
        context.insert(Cat(name: "Dining", symbolName: "fork.knife", sortOrder: 1))
        context.insert(Cat(name: "My Custom Category", symbolName: "star", sortOrder: 99))
        try context.save()

        try seedCategoriesIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<Cat>())
        // 15 predefined + 1 user category, with no duplicate Groceries/Dining.
        #expect(all.count == 17, "Expected 16 predefined + 1 custom = 17, got \(all.count)")
        #expect(all.filter { $0.name == "Groceries" }.count == 1, "Groceries must not be duplicated")
        #expect(all.contains { $0.name == "Meat" }, "Missing 'Meat' should be topped up")
        #expect(all.contains { $0.name == "My Custom Category" }, "User category must be preserved")
    }
}
