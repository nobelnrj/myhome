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
struct NPSNavServiceTests {

    // MARK: - Helpers

    /// Load a fixture file from MyHomeTests/Fixtures/nps/
    private func fixtureData(named name: String) -> Data {
        // In Xcode unit test bundles the test bundle resources include files from the test target.
        // The fixture files are committed alongside the test sources; locate via Bundle.
        let bundle = Bundle(for: NPSNavServiceTestsHelper.self)
        if let url = bundle.url(forResource: name, withExtension: nil) {
            return (try? Data(contentsOf: url)) ?? Data()
        }
        // Fallback: locate relative to source file (works when running directly)
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // MyHomeTests/
            .appendingPathComponent("Fixtures/nps/\(name)")
        return (try? Data(contentsOf: sourceDir)) ?? Data()
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
