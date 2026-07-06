import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests for the Gmail auto-attribution helper (D-05).
///
/// Exercises `AccountAttributionHelper.buildAccountIDsByLabel` and
/// `AccountAttributionHelper.accountID(forSourceLabel:in:)`.
///
/// Security: T-09-09 — archived accounts must not be matched.
/// STAB-02: the helper operates on plain UUID values, not @Model refs.
@MainActor
struct GmailAccountAttributionTests {

    // MARK: - attributesBySourceLabel

    @Test("sourceLabel → accountID: matching account is returned")
    func attributesBySourceLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self,
            configurations: config
        )
        let ctx = container.mainContext

        let account = Account(name: "HDFC CC", typeRaw: "credit_card", sourceLabel: "HDFC CC")
        ctx.insert(account)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let map = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)

        // Exact sourceLabel match
        let resolved = AccountAttributionHelper.accountID(forSourceLabel: "HDFC CC", in: map)
        #expect(resolved == account.id, "HDFC CC sourceLabel must resolve to account id")

        // Non-matching label returns nil (D-05: no match → Unassigned)
        let noMatch = AccountAttributionHelper.accountID(forSourceLabel: "Unknown Bank", in: map)
        #expect(noMatch == nil, "Unknown label must return nil (Unassigned)")
    }

    // MARK: - archivedAccountNotMatched

    @Test("archived account is NOT returned by attribution resolver (T-09-09 / Pitfall 6)")
    func archivedAccountNotMatched() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self,
            configurations: config
        )
        let ctx = container.mainContext

        let archivedAccount = Account(name: "Old Bank", typeRaw: "savings", sourceLabel: "Old Bank")
        archivedAccount.isArchived = true
        ctx.insert(archivedAccount)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let map = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)

        let resolved = AccountAttributionHelper.accountID(forSourceLabel: "Old Bank", in: map)
        #expect(resolved == nil, "Archived account must not be matched (T-09-09)")
    }

    // MARK: - unmatchedSourceLabels (07-07 auto-create)

    @Test("unmatchedSourceLabels: returns distinct labels with no matching account; skips matched — 07-07")
    func unmatchedSourceLabelsReturnsGaps() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        // One existing account that DOES match "ICICI CC ••5005" by sourceLabel.
        let existing = Account(name: "ICICI Credit", typeRaw: "credit_card", sourceLabel: "ICICI CC ••5005")
        ctx.insert(existing)

        // Expenses: one matches the existing account; two others (HDFC, CUB) have no account.
        let e1 = Expense(amount: 100, date: Date()); e1.sourceLabel = "ICICI CC ••5005"
        let e2 = Expense(amount: 200, date: Date()); e2.sourceLabel = "HDFC ••1329"
        let e3 = Expense(amount: 300, date: Date()); e3.sourceLabel = "CUB ••45"
        let e4 = Expense(amount: 400, date: Date()); e4.sourceLabel = "HDFC ••1329"  // duplicate label
        let e5 = Expense(amount: 500, date: Date()); e5.sourceLabel = nil            // no label → ignored
        [e1, e2, e3, e4, e5].forEach { ctx.insert($0) }
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        let unmatched = AccountAttributionHelper.unmatchedSourceLabels(in: expenses, accounts: accounts)

        #expect(Set(unmatched) == ["HDFC ••1329", "CUB ••45"], "Expected the two unmatched labels, got \(unmatched)")
        #expect(!unmatched.contains("ICICI CC ••5005"), "Already-matched label must be excluded")
        #expect(unmatched.count == 2, "Duplicate labels must be de-duplicated; nil labels ignored")
    }
}
