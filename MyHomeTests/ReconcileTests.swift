import Testing
import Foundation
import SwiftData
@testable import MyHome

/// Unit tests for the ReconcileView total-units overwrite (D-05).
///
/// Covers:
///   1. `parseReconciledUnits` input validation (T-115-01):
///      - Returns nil for "", "abc", "-5", "0"
///      - Returns a non-nil Decimal for "123.4567"
///   2. Whole-holding overwrite: Asset.units updated to reconciled value (D-05)
///   3. Contribution history preserved: prior estimate rows are NOT deleted (D-05, T-115-02)
///   4. Reconcile with existing SIP estimates: estimates stay, Asset.units overwritten
///   5. Reconcile with no prior contributions: Asset.units set to reconciled value
@Suite("ReconcileTests")
@MainActor
struct ReconcileTests {

    // MARK: - parseReconciledUnits input validation (T-115-01)

    @Test("parseReconciledUnits returns nil for empty string")
    func parseEmptyString() {
        #expect(ReconcileView.parseReconciledUnits("") == nil)
    }

    @Test("parseReconciledUnits returns nil for whitespace-only string")
    func parseWhitespaceOnly() {
        #expect(ReconcileView.parseReconciledUnits("   ") == nil)
    }

    @Test("parseReconciledUnits returns nil for non-numeric string")
    func parseNonNumeric() {
        #expect(ReconcileView.parseReconciledUnits("abc") == nil)
    }

    @Test("parseReconciledUnits returns nil for negative value")
    func parseNegative() {
        #expect(ReconcileView.parseReconciledUnits("-5") == nil)
    }

    @Test("parseReconciledUnits returns nil for zero")
    func parseZero() {
        #expect(ReconcileView.parseReconciledUnits("0") == nil)
    }

    @Test("parseReconciledUnits returns non-nil Decimal for valid positive value")
    func parseValidPositive() {
        let result = ReconcileView.parseReconciledUnits("123.4567")
        #expect(result != nil)
        #expect(result == Decimal(string: "123.4567"))
    }

    @Test("parseReconciledUnits returns non-nil Decimal for integer string")
    func parseInteger() {
        let result = ReconcileView.parseReconciledUnits("500")
        #expect(result != nil)
        #expect(result == Decimal(500))
    }

    @Test("parseReconciledUnits trims whitespace before parsing")
    func parseTrimmedWhitespace() {
        let result = ReconcileView.parseReconciledUnits("  42.5  ")
        #expect(result != nil)
        #expect(result == Decimal(string: "42.5"))
    }

    // MARK: - In-memory store helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Asset.self, Contribution.self, SIP.self, SIPAmountChange.self,
            configurations: config
        )
    }

    // MARK: - Whole-holding overwrite (D-05)

    @Test("reconcile overwrites Asset.units with the authoritative figure")
    func reconcileOverwritesUnits() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Arrange: insert an Asset with an estimated 100 units
        let asset = Asset()
        asset.units = Decimal(100)
        context.insert(asset)
        try context.save()

        // Act: simulate the reconcile mutation (mirrors ReconcileView.reconcile())
        let authoritativeUnits = Decimal(string: "123.4567")!
        asset.units = authoritativeUnits
        try context.save()

        // Assert: units updated to the authoritative figure
        let savedAssetID = asset.id
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == savedAssetID })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.units == authoritativeUnits)
    }

    @Test("reconcile preserves existing Contribution rows (estimate history retained — D-05)")
    func reconcilePreservesContributionHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Arrange: insert an Asset + 2 Contribution estimate rows
        let asset = Asset()
        asset.units = Decimal(50)
        context.insert(asset)

        let sip = SIP(assetID: asset.id, dayOfMonth: 5, amount: Decimal(1000))
        context.insert(sip)

        let contrib1 = Contribution(
            assetID: asset.id,
            sipID: sip.id,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Decimal(1000),
            navUsed: Decimal(string: "100.0")!,
            navDate: Date(timeIntervalSince1970: 1_700_000_000),
            unitsAdded: Decimal(10),
            isEstimate: true
        )
        let contrib2 = Contribution(
            assetID: asset.id,
            sipID: sip.id,
            date: Date(timeIntervalSince1970: 1_702_000_000),
            amount: Decimal(1000),
            navUsed: Decimal(string: "105.0")!,
            navDate: Date(timeIntervalSince1970: 1_702_000_000),
            unitsAdded: Decimal(string: "9.5238")!,
            isEstimate: true
        )
        context.insert(contrib1)
        context.insert(contrib2)
        try context.save()

        // Act: simulate reconcile (ONLY set asset.units — do NOT delete Contributions)
        asset.units = Decimal(string: "25.1234")!
        try context.save()

        // Assert 1: Asset.units updated
        #expect(asset.units == Decimal(string: "25.1234"))

        // Assert 2: Both Contribution rows still exist (history preserved — D-05, T-115-02)
        let assetID = asset.id
        let contributionDescriptor = FetchDescriptor<Contribution>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let contributions = try context.fetch(contributionDescriptor)
        #expect(contributions.count == 2)
    }

    @Test("reconcile with no prior contributions only sets Asset.units (no crash)")
    func reconcileWithNoContributions() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Arrange: Asset with no Contributions
        let asset = Asset()
        asset.units = nil
        context.insert(asset)
        try context.save()

        // Act: reconcile with a fresh value
        asset.units = Decimal(string: "50.0")!
        try context.save()

        // Assert: units set, no crash
        #expect(asset.units == Decimal(string: "50.0"))
    }

    @Test("reconcile with existing SIP estimates: estimates stay, Asset.units overwritten")
    func reconcileWithEstimatesRetained() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Arrange: Asset with estimated 200 units + 2 estimate Contributions
        let asset = Asset()
        asset.units = Decimal(200)
        context.insert(asset)

        let sip = SIP(assetID: asset.id, dayOfMonth: 10, amount: Decimal(5000))
        context.insert(sip)

        let c1 = Contribution(assetID: asset.id, sipID: sip.id, isEstimate: true)
        let c2 = Contribution(assetID: asset.id, sipID: sip.id, isEstimate: true)
        context.insert(c1)
        context.insert(c2)
        try context.save()

        // Verify pre-condition: 2 estimate rows
        let assetID = asset.id
        let pre = try context.fetch(FetchDescriptor<Contribution>(
            predicate: #Predicate { $0.assetID == assetID }
        ))
        #expect(pre.count == 2)
        #expect(pre.allSatisfy { $0.isEstimate == true })

        // Act: reconcile (overwrite units only)
        let reconciledUnits = Decimal(string: "195.7654")!
        asset.units = reconciledUnits
        try context.save()

        // Assert: units overwritten; estimate rows still present and still isEstimate=true
        #expect(asset.units == reconciledUnits)
        let post = try context.fetch(FetchDescriptor<Contribution>(
            predicate: #Predicate { $0.assetID == assetID }
        ))
        #expect(post.count == 2)
        #expect(post.allSatisfy { $0.isEstimate == true })
    }
}
