import Testing
import SwiftData
import Foundation
@testable import MyHome

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// Expense ↔ Category relationship tests — verifies EXP-06 assign and clear category.
///
/// Uses an in-memory ModelContainer per test (FND-06, Pitfall 16).
@MainActor
struct ExpenseCategoryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    @Test("Expense can have a category assigned and persisted")
    func assignCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Groceries", symbolName: "cart")
        context.insert(cat)
        let catID = cat.id

        let expense = Expense(amount: Decimal(500))
        expense.categories = [cat]
        context.insert(expense)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.first?.categories.isEmpty == false,
                "Expense should have a category after assignment")
        #expect(fetched.first?.categories.first?.id == catID,
                "Fetched expense's category ID should match the assigned category")
    }

    @Test("Expense category can be cleared and persists as empty")
    func clearCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Dining", symbolName: "fork.knife")
        context.insert(cat)

        let expense = Expense(amount: Decimal(200))
        expense.categories = [cat]
        context.insert(expense)
        try context.save()

        // Clear the category
        expense.categories = []
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.first?.categories.isEmpty == true,
                "Expense should have no categories after clearing")
    }
}
