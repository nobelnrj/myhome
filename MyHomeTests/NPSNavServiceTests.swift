import Testing
import Foundation
@testable import MyHome

/// NPSNavService unit tests — ASSET-04 reversed, T-113-01, T-113-02.
///
/// Covers:
///   - parseNPSLatest: fixture returns >0 NPSSchemes with non-zero Decimal NAVs
///   - parseNPSLatest: JSON Number nav round-trips to Decimal via String intermediary (T-113-02)
///   - parseNPSLatest: garbage / empty Data yields [] — silent fail, no throw (T-113-01)
///   - shouldFetch: false when lastFetch == startOfTodayIST
///   - shouldFetch: true when lastFetch is yesterday IST
///   - NPSScheme: id == code (Identifiable conformance)
///
/// All tests run offline using committed fixtures under MyHomeTests/Fixtures/nps/.
@Suite("NPSNavServiceTests")
@MainActor
struct NPSNavServiceTests {

    // MARK: - Helpers

    /// Load a fixture file from MyHomeTests/Fixtures/nps/
    ///
    /// Uses #filePath to resolve relative to source file (reliable in xcodebuild).
    /// Falls back to bundle resource lookup for Fixtures folder reference.
    private func fixtureData(named name: String) -> Data {
        // Primary: resolve via #filePath (works in xcodebuild simulator runs)
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsDir = thisFile.deletingLastPathComponent()  // MyHomeTests/
        let fileURL = testsDir.appendingPathComponent("Fixtures/nps/\(name)")
        if let data = try? Data(contentsOf: fileURL) { return data }

        // Fallback: bundle resource (Fixtures is a folder reference in pbxproj)
        let bundle = Bundle(for: NPSNavServiceTestsHelper.self)
        let nsName = name as NSString
        let stem = nsName.deletingPathExtension
        let ext  = nsName.pathExtension
        if let url = bundle.url(forResource: stem,
                                withExtension: ext.isEmpty ? nil : ext,
                                subdirectory: "Fixtures/nps") {
            return (try? Data(contentsOf: url)) ?? Data()
        }
        return Data()
    }

    // MARK: - parseNPSLatest: fixture

    @Test("parseNPSLatest: fixture latest-min.json returns >0 NPSSchemes with non-zero Decimal NAVs")
    func parseFixtureReturnsSchemes() {
        let service = NPSNavService()
        let data = fixtureData(named: "latest-min.json")
        #expect(!data.isEmpty, "Fixture file must be loadable")

        let schemes = service.parseNPSLatest(data)
        #expect(schemes.count > 0, "Must parse at least one NPSScheme from the fixture")
        for scheme in schemes {
            #expect(scheme.nav > 0, "Every parsed NAV must be non-zero; got \(scheme.nav) for \(scheme.code)")
        }
    }

    // MARK: - parseNPSLatest: live object-wrapper shape (regression — UAT 11.1)

    @Test("parseNPSLatest: live {\"data\":[...],\"metadata\":{...}} wrapper parses (metadata sibling ignored)")
    func objectWrapperWithMetadataParses() {
        let service = NPSNavService()
        // The REAL npsnav.in/api/latest-min shape: object with a `data` array AND a `metadata`
        // sibling object. The old [String:[NPSEntry]] fallback threw on the metadata key, so the
        // picker showed "No Schemes Loaded" against the live endpoint. Lock the fix.
        let json = """
        {"data": [["SM001001", 49.5087], ["SM001002", 42.5581]],
         "metadata": {"source": "npsnav.in", "updated": "2026-06-12"}}
        """.data(using: .utf8)!
        let schemes = service.parseNPSLatest(json)
        #expect(schemes.count == 2, "Wrapper-shaped payload must parse both schemes; got \(schemes.count)")
        #expect(schemes.contains { $0.code == "SM001001" && $0.nav > 0 })
    }

    // MARK: - parseNPSLatest: Number nav precision (T-113-02)

    @Test("parseNPSLatest: JSON Number nav 49.5429 round-trips to Decimal via String intermediary")
    func numberNavRoundTripsToDecimal() {
        let service = NPSNavService()
        // Fabricated single-entry payload — nav is a JSON Number (bare float, not string)
        let json = """
        [["SM001001", 49.5429]]
        """.data(using: .utf8)!

        let schemes = service.parseNPSLatest(json)
        #expect(schemes.count == 1, "Should parse exactly one scheme")
        let nav = schemes.first!.nav
        let expected = Decimal(string: "49.5429")!
        #expect(nav == expected,
                "Nav must equal Decimal(string:\"49.5429\") — not a lossy Double conversion; got \(nav)")
        // Verify the type is actually Decimal (compile-time check)
        let _: Decimal = nav
    }

    // MARK: - parseNPSLatest: silent-fail (T-113-01)

    @Test("parseNPSLatest: garbage Data yields [] — silent fail, no throw")
    func garbageDataYieldsEmpty() {
        let service = NPSNavService()
        let garbage = Data("not json at all !!!".utf8)
        let schemes = service.parseNPSLatest(garbage)
        #expect(schemes.isEmpty, "Garbage input must return [] — never throw")
    }

    @Test("parseNPSLatest: empty Data yields [] — silent fail")
    func emptyDataYieldsEmpty() {
        let service = NPSNavService()
        let schemes = service.parseNPSLatest(Data())
        #expect(schemes.isEmpty, "Empty Data must return []")
    }

    @Test("parseNPSLatest: malformed JSON (object instead of array) yields []")
    func malformedObjectYieldsEmpty() {
        let service = NPSNavService()
        let json = """
        {"error": "not an array"}
        """.data(using: .utf8)!
        let schemes = service.parseNPSLatest(json)
        #expect(schemes.isEmpty, "Object-shaped JSON must return [] — defensive parsing (Open Question 1)")
    }

    // MARK: - IST daily gate

    @Test("shouldFetch: false when lastFetchDate == startOfTodayIST")
    func shouldFetchFalseWhenAlreadyFetchedToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = Date()
        let todayIST = cal.startOfDay(for: now)
        #expect(NPSNavService.shouldFetch(lastFetchDate: todayIST, referenceDate: now) == false,
                "When lastFetch == startOfTodayIST the gate must return false")
    }

    @Test("shouldFetch: false when lastFetchDate is after startOfTodayIST (same day, later hour)")
    func shouldFetchFalseWhenFetchedLaterToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = Date()
        // lastFetch is the same IST day but 1 minute after start-of-day
        let todayIST = cal.startOfDay(for: now)
        let laterToday = todayIST.addingTimeInterval(60)
        #expect(NPSNavService.shouldFetch(lastFetchDate: laterToday, referenceDate: now) == false,
                "When lastFetch is later in the same IST day the gate must return false")
    }

    @Test("shouldFetch: true when lastFetchDate is yesterday IST")
    func shouldFetchTrueWhenYesterday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        #expect(NPSNavService.shouldFetch(lastFetchDate: yesterday, referenceDate: now) == true,
                "When lastFetch is yesterday IST the gate must return true")
    }

    @Test("shouldFetch: true when lastFetch is .distantPast")
    func shouldFetchTrueWhenNeverFetched() {
        let now = Date()
        #expect(NPSNavService.shouldFetch(lastFetchDate: .distantPast, referenceDate: now) == true,
                "When lastFetch is .distantPast the gate must return true")
    }

    // MARK: - NPSScheme: Identifiable

    @Test("NPSScheme.id equals code (Identifiable conformance)")
    func npsSchemeIDEqualsCode() {
        let service = NPSNavService()
        let json = """
        [["SM001001", 49.5429]]
        """.data(using: .utf8)!
        let schemes = service.parseNPSLatest(json)
        #expect(schemes.count == 1)
        let scheme = schemes.first!
        #expect(scheme.id == scheme.code, "NPSScheme.id must equal code (Identifiable)")
    }
}

// Dummy class for Bundle lookup — must be an ObjC-visible class to resolve the test bundle.
private class NPSNavServiceTestsHelper: NSObject {}
