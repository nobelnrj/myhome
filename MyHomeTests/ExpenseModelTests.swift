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
        // CR-02 / FND-03 / Pitfall 1: this test must actually be able to FAIL if a
        // future developer adds a non-optional, default-less stored property, drops a
        // CloudKit-incompatible @Attribute(.unique), or changes the money type.
        //
        // The previous version computed `isOptional || !isOptional` (always true) via
        // runtime reflection — which cannot in principle distinguish "non-optional with
        // default" from "non-optional without default" once an instance exists. We
        // replace it with checks against the SwiftData Schema metadata, which records
        // optionality, default-value presence, and uniqueness independently of any
        // instance.

        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let entity = try #require(
            container.schema.entities.first { $0.name == "Expense" },
            "Expense entity must be present in the schema"
        )

        // 1. Every stored attribute must be optional OR carry a default value, so
        //    CloudKit mirroring (which makes all attributes optional) can never see a
        //    required-but-empty column. `defaultValue` is non-nil only when the
        //    property declares a default.
        #expect(!entity.attributes.isEmpty, "Expense must declare stored attributes")
        for attribute in entity.attributes {
            let isOptional = attribute.isOptional
            let hasDefault = attribute.defaultValue != nil
            #expect(
                isOptional || hasDefault,
                "Attribute '\(attribute.name)' must be optional or have a default value for CloudKit mirroring"
            )
        }

        // 2. No @Attribute(.unique): CloudKit does not support unique constraints.
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "Expense must have no @Attribute(.unique) — CloudKit does not support it"
        )

        // 3. Money must be Decimal (never Double — Pitfall 17). A default-initialized
        //    instance must succeed using only the one required parameter, and its
        //    defaults must be intact.
        let expense = Expense(amount: Decimal(0))
        #expect(type(of: expense.amount) == Decimal.self, "amount must be a Decimal, never Double")
        #expect(expense.amount == Decimal(0))
        #expect(expense.currencyCode == "INR", "currencyCode must default to INR")
        #expect(expense.note == nil, "note must be optional and default to nil")
    }
}
