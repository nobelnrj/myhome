import Testing
@testable import MyHome

/// Wave 0 stub tests — these are intentionally failing (red).
/// They serve as the Nyquist sampling baseline for plans 02–04.
/// Each stub will be replaced with real assertions in the plan that implements the feature.
@MainActor
struct ExpenseModelTests {

    @Test("Expense CRUD lifecycle — insert, fetch, delete")
    func expenseCRUD() throws {
        // Stub — implemented in plan 02 when the Expense @Model is created.
        #expect(Bool(false), "stub — implemented in plan 02")
    }

    @Test("Expense update — edit fields and persist")
    func expenseUpdate() throws {
        // Stub — implemented in plan 02 when the Expense @Model is created.
        #expect(Bool(false), "stub — implemented in plan 02")
    }

    @Test("Currency formatting — en-IN lakh grouping")
    func currencyFormatting() {
        // Stub — implemented in plan 02 when Decimal.formattedINR() extension is added.
        #expect(Bool(false), "stub — implemented in plan 02")
    }

    @Test("Expense @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func expensePropertiesAreCloudKitReady() throws {
        // Stub — implemented in plan 02 when the Expense @Model is created.
        #expect(Bool(false), "stub — implemented in plan 02")
    }
}
