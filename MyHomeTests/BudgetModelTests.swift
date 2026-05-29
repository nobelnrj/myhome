import Testing
import SwiftData
import Foundation
@testable import MyHome

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// Category budget model tests — verifies EXP-07 monthlyBudget Decimal storage and round-trip.
///
/// Uses an in-memory ModelContainer per test (FND-06, Pitfall 16).
@MainActor
struct BudgetModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    @Test("Category monthlyBudget stores and round-trips as Decimal unchanged")
    func budgetStoreAndRetrieve() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Rent", symbolName: "house")
        cat.monthlyBudget = Decimal(15000)
        context.insert(cat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Cat>())
        let retrieved = fetched.first?.monthlyBudget
        #expect(retrieved == Decimal(15000),
                "monthlyBudget must round-trip exactly as Decimal(15000), got \(String(describing: retrieved))")
        if let budget = retrieved {
            #expect(type(of: budget) == Decimal.self, "monthlyBudget must be Decimal, never Double")
        }
    }

    @Test("nil monthlyBudget round-trips as nil")
    func nilBudgetRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Shopping", symbolName: "bag")
        // monthlyBudget defaults to nil — do not set it
        context.insert(cat)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Cat>())
        #expect(fetched.first?.monthlyBudget == nil,
                "Category without a budget must round-trip monthlyBudget as nil")
    }
}
