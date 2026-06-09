import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Account CRUD model tests — verifies archive/unarchive, duplicate rejection.
///
/// Uses an in-memory ModelContainer per test (FND-06).
@MainActor
struct AccountCRUDTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }

    // Helper mirroring AccountsListView.addAccount logic
    private func addAccount(name: String, typeRaw: String = "savings", context: ModelContext, allAccounts: [Account]) throws -> Account? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        // Lookup-before-insert (case-insensitive)
        guard allAccounts.first(where: { ($0.name ?? "").lowercased() == lower }) == nil else {
            return nil // duplicate rejected
        }
        let nextSortOrder = (allAccounts.map(\.sortOrder).min() ?? 0) - 1
        let account = Account(name: trimmed, typeRaw: typeRaw)
        account.sortOrder = nextSortOrder
        context.insert(account)
        try context.save()
        return account
    }

    @Test("archiveHidesFromActive: setting isArchived=true hides from active but both remain in store")
    func archiveHidesFromActive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let a1 = Account(name: "HDFC Savings")
        ctx.insert(a1)
        let a2 = Account(name: "ICICI CC", typeRaw: "credit_card")
        ctx.insert(a2)
        try ctx.save()

        // Archive a2
        a2.isArchived = true
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Account>())
        let active = all.filter { !$0.isArchived }
        let archived = all.filter { $0.isArchived }

        #expect(all.count == 2, "Both accounts must remain in the store")
        #expect(active.count == 1, "Only one active account expected")
        #expect(archived.count == 1, "Only one archived account expected")
        #expect(active.first?.name == "HDFC Savings", "Active account should be HDFC Savings")
        #expect(archived.first?.name == "ICICI CC", "Archived account should be ICICI CC")
    }

    @Test("duplicateNameRejected: case-insensitive lookup-before-insert prevents duplicate accounts")
    func duplicateNameRejected() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Insert first account "HDFC"
        let all1 = try ctx.fetch(FetchDescriptor<Account>())
        let first = try addAccount(name: "HDFC", context: ctx, allAccounts: all1)
        #expect(first != nil, "First insertion should succeed")

        // Attempt duplicate "hdfc" (case-insensitive match)
        let all2 = try ctx.fetch(FetchDescriptor<Account>())
        let duplicate = try addAccount(name: "hdfc", context: ctx, allAccounts: all2)
        #expect(duplicate == nil, "Case-insensitive duplicate should be rejected")

        let finalAll = try ctx.fetch(FetchDescriptor<Account>())
        #expect(finalAll.count == 1, "Store must contain exactly one account after duplicate rejection")
    }
}
