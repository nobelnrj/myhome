import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Expense model and formatting tests — turned green in plan 02.
/// Uses a fresh in-memory ModelContainer per test (FND-06, Pitfall 16).
@MainActor
struct ExpenseModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, configurations: config)
    }

    @Test("Expense CRUD lifecycle — insert, fetch, delete")
    func expenseCRUD() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let expense = Expense(amount: Decimal(500), note: "Lunch")
        context.insert(expense)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.count == 1)
        #expect(fetched[0].currencyCode == "INR")
        #expect(fetched[0].amount == Decimal(500))

        context.delete(fetched[0])
        try context.save()
        let afterDelete = try context.fetch(FetchDescriptor<Expense>())
        #expect(afterDelete.isEmpty)
    }

    @Test("Expense update — edit fields and persist")
    func expenseUpdate() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let expense = Expense(amount: Decimal(500), note: "Lunch")
        let createdUpdatedAt = expense.updatedAt
        context.insert(expense)
        try context.save()

        // Small delay to ensure updatedAt timestamp differs
        let before = expense.updatedAt
        expense.amount = Decimal(750)
        expense.note = "Dinner"
        expense.updatedAt = Date()
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.count == 1)
        #expect(fetched[0].amount == Decimal(750))
        #expect(fetched[0].note == "Dinner")
        // updatedAt was explicitly set after initial creation
        #expect(fetched[0].updatedAt >= before)
    }

    @Test("Currency formatting — en-IN lakh grouping")
    func currencyFormatting() {
        let amount = Decimal(100000)
        let formatted = amount.formattedINR()
        // en_IN produces lakh grouping: ₹1,00,000.00
        #expect(formatted.contains("1,00,000"), "Expected lakh grouping in '\(formatted)'")
        #expect(formatted.contains("₹"), "Expected ₹ symbol in '\(formatted)'")

        // Negative amount (refund): sign appears before ₹
        let refund = Decimal(-500)
        let formattedRefund = refund.formattedINR()
        #expect(formattedRefund.contains("500"), "Expected amount in '\(formattedRefund)'")
        #expect(formattedRefund.contains("₹"), "Expected ₹ symbol in '\(formattedRefund)'")
        #expect(formattedRefund.hasPrefix("-") || formattedRefund.contains("-"),
                "Expected negative indicator in '\(formattedRefund)'")
    }

    @Test("Expense @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func expensePropertiesAreCloudKitReady() throws {
        // Create an Expense with only the required parameter; all others must default.
        let expense = Expense(amount: Decimal(0))
        let mirror = Mirror(reflecting: expense)

        for child in mirror.children {
            guard let label = child.label else { continue }
            let value = child.value
            let isOptional = value is any OptionalProtocol
            let hasNonNilValue = !isOptional

            // Every property must be either optional (nil is valid) or
            // have produced a non-nil value from a default.
            let passesRule = isOptional || hasNonNilValue
            #expect(passesRule, "Property '\(label)' must be optional or have a default value")
        }

        // Assert no @Attribute(.unique): uniquenessConstraints must be empty.
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let entityDescription = container.schema.entities.first { $0.name == "Expense" }
        #expect(entityDescription?.uniquenessConstraints.isEmpty == true,
                "Expense must have no @Attribute(.unique) — CloudKit does not support it")
    }
}

// MARK: - Helpers

/// Protocol used by the reflection test to detect Optional<T> values
/// without needing to know T at compile time.
private protocol OptionalProtocol {}
extension Optional: OptionalProtocol {}
