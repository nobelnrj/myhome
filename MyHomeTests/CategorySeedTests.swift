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

    @Test("14 predefined categories are seeded on empty store")
    func seedsOnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)
        let all = try context.fetch(FetchDescriptor<Cat>())
        #expect(all.count == 14, "Expected 14 predefined categories, got \(all.count)")
    }

    @Test("Seeding is idempotent — no duplicates on second run")
    func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)
        try seedCategoriesIfNeeded(context: context)   // second call must be a no-op
        let all = try context.fetch(FetchDescriptor<Cat>())
        #expect(all.count == 14, "Expected 14 categories after two seed calls, got \(all.count)")
    }
}
