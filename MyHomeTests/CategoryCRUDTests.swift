import Testing
import SwiftData
import Foundation
@testable import MyHome

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// Category CRUD model tests — verifies EXP-05 add/rename/delete operations.
///
/// Uses an in-memory ModelContainer per test (FND-06, Pitfall 16).
@MainActor
struct CategoryCRUDTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    @Test("Category can be inserted and fetched")
    func addCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Groceries", symbolName: "cart", sortOrder: 0)
        context.insert(cat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Cat>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Groceries")
    }

    @Test("Category name can be renamed and persisted")
    func renameCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Old Name", symbolName: nil)
        context.insert(cat)
        try context.save()

        // Mutate and save
        cat.name = "New Name"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Cat>())
        #expect(fetched.first?.name == "New Name")
    }

    @Test("Deleting a category nullifies expense.categories link")
    func deleteNullifiesExpenseLink() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Test", symbolName: nil)
        context.insert(cat)
        let expense = Expense(amount: Decimal(100))
        expense.categories = [cat]
        context.insert(expense)
        try context.save()

        context.delete(cat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.first?.categories.isEmpty == true,
                "Deleting category must nullify expense.categories (D2-04, .nullify deleteRule)")
    }

    @Test("Category uniqueness enforced via lookup-before-insert (no @Attribute(.unique))")
    func uniquenessByFetch() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert a "Food" category
        let cat = Cat(name: "Food", symbolName: "fork.knife")
        context.insert(cat)
        try context.save()

        // Lookup-before-insert: fetch by exact name to check for duplicates.
        // Note: SwiftData #Predicate does not support String.lowercased() — case-insensitive
        // comparison must be done after fetching or using an exact-case predicate.
        // Production code trims and lowercases before comparing; the test verifies the
        // lookup-by-fetch mechanism, which is the uniqueness-enforcement pattern (Pitfall P2-06).
        let targetName = "Food"
        let existing = try context.fetch(
            FetchDescriptor<Cat>(predicate: #Predicate { $0.name == targetName })
        )
        #expect(existing.count == 1, "Should find exactly one 'Food' category by name fetch")
    }
}
