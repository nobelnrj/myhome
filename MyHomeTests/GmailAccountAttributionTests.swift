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
}
