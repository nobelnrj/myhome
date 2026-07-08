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

    // MARK: - Aliasing (D-MERGE-01): one account, several ingestion identities

    @Test("multi-line sourceLabel: every alias resolves to the same account")
    func aliasesResolveToOneAccount() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, configurations: config)
        let ctx = container.mainContext

        // A savings account merged with its debit-card identity (newline-separated aliases).
        let account = Account(name: "ICICI Savings", typeRaw: "savings",
                              sourceLabel: "ICICI Savings\nICICI Debit Card")
        ctx.insert(account)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let map = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)

        #expect(AccountAttributionHelper.accountID(forSourceLabel: "ICICI Savings", in: map) == account.id)
        #expect(AccountAttributionHelper.accountID(forSourceLabel: "ICICI Debit Card", in: map) == account.id,
                "The debit-card alias must resolve to the same savings account")
    }

    @Test("aliases(of:) / sourceLabel(fromAliases:) round-trips and de-dupes")
    func aliasRoundTrip() {
        #expect(AccountAttributionHelper.aliases(fromSourceLabel: "A\nB\nA") == ["A", "B"])
        #expect(AccountAttributionHelper.aliases(fromSourceLabel: nil) == [])
        #expect(AccountAttributionHelper.sourceLabel(fromAliases: ["A", "B", "A"]) == "A\nB")
        #expect(AccountAttributionHelper.sourceLabel(fromAliases: ["  ", ""]) == nil,
                "All-empty alias list packs back to nil")
    }

    // MARK: - Suffix matching (D-MERGE-02): ••843 vs ••6843

    @Test("labelIdentity splits prefix and trailing digits, ignoring mask glyphs")
    func labelIdentitySplit() {
        let id = AccountAttributionHelper.labelIdentity("ICICI ••6843")
        #expect(id?.prefix == "icici")
        #expect(id?.digits == "6843")
        // No trailing digits → nil
        #expect(AccountAttributionHelper.labelIdentity("Manual Cash") == nil)
    }

    @Test("digitsMatchBySuffix: 843 ⊂ 6843 matches; short/unrelated tails do not")
    func suffixDigitRules() {
        #expect(AccountAttributionHelper.digitsMatchBySuffix("843", "6843"))
        #expect(AccountAttributionHelper.digitsMatchBySuffix("6843", "843"))
        #expect(AccountAttributionHelper.digitsMatchBySuffix("5005", "5005"))
        #expect(!AccountAttributionHelper.digitsMatchBySuffix("45", "6845"), "2-digit overlap is too weak")
        #expect(!AccountAttributionHelper.digitsMatchBySuffix("1234", "5678"))
    }

    @Test("accountIDBySuffix resolves ••843 to the existing ••6843 ICICI account")
    func suffixResolvesMaskingVariance() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, configurations: config)
        let ctx = container.mainContext

        let icici = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI ••6843")
        let hdfc = Account(name: "HDFC", typeRaw: "savings", sourceLabel: "HDFC ••1329")
        ctx.insert(icici); ctx.insert(hdfc)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(AccountAttributionHelper.accountIDBySuffix(forSourceLabel: "ICICI ••843", accounts: accounts) == icici.id)
        // Different institution → no cross-bank suffix match.
        #expect(AccountAttributionHelper.accountIDBySuffix(forSourceLabel: "SBI ••843", accounts: accounts) == nil)
    }

    @Test("suffix match never merges a savings account with its debit card (different prefix)")
    func suffixDoesNotMergeDebitCard() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, configurations: config)
        let ctx = container.mainContext

        // Same digits, different institution prefix → NOT a suffix match; needs manual merge.
        let savings = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI Savings ••6843")
        ctx.insert(savings)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(AccountAttributionHelper.accountIDBySuffix(forSourceLabel: "ICICI Debit Card ••6843", accounts: accounts) == nil)
    }

    @Test("value-typed suffix index (used in the sync loop) resolves ••843 to ••6843")
    func suffixIndexResolves() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, configurations: config)
        let ctx = container.mainContext

        let icici = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI ••6843")
        let archived = Account(name: "Old ICICI", typeRaw: "savings", sourceLabel: "ICICI ••6843")
        archived.isArchived = true
        ctx.insert(icici); ctx.insert(archived)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let index = AccountAttributionHelper.buildSuffixIndex(from: accounts)

        // Archived account excluded from the index (T-09-09), so only the active one resolves.
        #expect(index.allSatisfy { $0.id == icici.id })
        #expect(AccountAttributionHelper.accountIDBySuffix(forSourceLabel: "ICICI ••843", in: index) == icici.id)
        #expect(AccountAttributionHelper.accountIDBySuffix(forSourceLabel: "SBI ••843", in: index) == nil)
    }

    @Test("unmatchedSourceLabels collapses ••843 and ••6843 into a single auto-create")
    func unmatchedCollapsesSuffixDupes() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let e1 = Expense(amount: 100, date: Date()); e1.sourceLabel = "ICICI ••6843"
        let e2 = Expense(amount: 200, date: Date()); e2.sourceLabel = "ICICI ••843"   // masking variant of e1
        [e1, e2].forEach { ctx.insert($0) }
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        let unmatched = AccountAttributionHelper.unmatchedSourceLabels(in: expenses, accounts: accounts)

        #expect(unmatched.count == 1, "Masking variants must collapse to one auto-create, got \(unmatched)")
    }
}
