import Testing
import SwiftData
import Foundation
@testable import MyHome

/// AMFINavService tests — ASSET-03, T-11-04, T-11-05.
///
/// Covers:
///   - parseNAVAll: correct parsing of the real 6-column semicolon format
///   - parseNAVAll: section-header lines (no semicolons) are skipped
///   - parseNAVAll: rows with <6 fields are skipped (malformed)
///   - parseNAVAll: rows with non-numeric NAV are skipped (never fatalError)
///   - parseNAVAll: NAV is typed Decimal (not Double)
///   - parseNAVAll: date parsed with DD-MMM-yyyy, en_US_POSIX, Asia/Kolkata
///   - refreshIfNeeded: no-op when last fetch date >= startOfTodayIST
///   - refreshIfNeeded: kicks a fetch when last fetch date is .distantPast
///   - AMFIScheme: Identifiable, id == code
@MainActor
struct AMFINavServiceTests {

    // MARK: - Fixtures

    /// A representative NAVAll.txt fragment with:
    ///  - a column header line (line 0 — skipped by dropFirst)
    ///  - a section-header line (no semicolons — must be skipped)
    ///  - one valid data row
    ///  - one row with fewer than 6 semicolon-delimited fields (malformed — must be skipped)
    ///  - one row with a non-numeric NAV (NaN — must be skipped)
    private let sampleNAVText = """
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
Open Ended Schemes(Debt Scheme - Banking and PSU Fund)
119551;INF209KA12Z1;INF209KA13Z9;Aditya Birla Sun Life Banking & PSU Debt Fund - DIRECT - IDCW;105.6569;10-Jun-2026
119552;INF209KA14Z7
119553;INF209KA15Z4;INF209KA16Z2;Bad NAV Fund;NOT_A_NUMBER;10-Jun-2026
"""

    // MARK: - parseNAVAll: valid rows

    @Test("parseNAVAll: valid data row returns one AMFIScheme with correct code, name, nav, navDate")
    func parseValidRow() {
        let service = AMFINavService()
        let schemes = service.parseNAVAll(sampleNAVText)
        #expect(schemes.count == 1, "Only the one valid data row should be parsed; header/section/malformed/nan rows skipped")
        let scheme = schemes.first!
        #expect(scheme.code == "119551", "code must be column 0")
        #expect(scheme.name == "Aditya Birla Sun Life Banking & PSU Debt Fund - DIRECT - IDCW",
                "name must be column 3")
        #expect(scheme.nav == Decimal(string: "105.6569")!, "nav must be Decimal from column 4")
    }

    @Test("parseNAVAll: nav field is Decimal — not Double")
    func navIsDecimal() {
        let service = AMFINavService()
        let schemes = service.parseNAVAll(sampleNAVText)
        #expect(schemes.count == 1)
        // Verify the type is Decimal; the test will fail at compile time if nav were Double
        let nav: Decimal = schemes.first!.nav
        #expect(nav == Decimal(string: "105.6569")!, "NAV must be exact Decimal, not Double")
    }

    @Test("parseNAVAll: navDate is parsed from DD-MMM-yyyy string using Asia/Kolkata calendar")
    func navDateParsed() {
        let service = AMFINavService()
        let schemes = service.parseNAVAll(sampleNAVText)
        #expect(schemes.count == 1)
        let navDate = schemes.first!.navDate

        // Reconstruct expected date: "10-Jun-2026" in IST
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let comps = cal.dateComponents([.year, .month, .day], from: navDate)
        #expect(comps.year == 2026, "year must be 2026")
        #expect(comps.month == 6,   "month must be 6 (June)")
        #expect(comps.day == 10,    "day must be 10")
    }

    // MARK: - parseNAVAll: guard cases

    @Test("parseNAVAll: section-header line (no semicolons) is skipped — not counted as a record")
    func sectionHeaderSkipped() {
        let service = AMFINavService()
        // text with ONLY a section header after the column header
        let text = """
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
Open Ended Schemes(Debt Scheme - Banking and PSU Fund)
"""
        let schemes = service.parseNAVAll(text)
        #expect(schemes.isEmpty, "Section-header lines must be skipped — no records emitted")
    }

    @Test("parseNAVAll: row with fewer than 6 semicolon-delimited fields is skipped")
    func malformedRowSkipped() {
        let service = AMFINavService()
        let text = """
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
119552;INF209KA14Z7
"""
        let schemes = service.parseNAVAll(text)
        #expect(schemes.isEmpty, "Malformed rows (< 6 fields) must be skipped")
    }

    @Test("parseNAVAll: row with non-numeric NAV is skipped — never fatalError")
    func nanNAVRowSkipped() {
        let service = AMFINavService()
        let text = """
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
119553;INF209KA15Z4;INF209KA16Z2;Bad NAV Fund;NOT_A_NUMBER;10-Jun-2026
"""
        let schemes = service.parseNAVAll(text)
        #expect(schemes.isEmpty, "Rows with non-numeric NAV must be skipped; no fatalError")
    }

    @Test("parseNAVAll: column header line (first line) is skipped by dropFirst")
    func columnHeaderSkipped() {
        let service = AMFINavService()
        // If the column header were parsed as data, it would have "Scheme Code" as code
        // and "Net Asset Value" as NAV-string — which would be non-numeric and thus skipped anyway.
        // We use a text where the header line IS numeric-looking to surface the dropFirst guard.
        let text = """
111111;A;B;Header Fund;999.99;10-Jun-2026
119551;INF209KA12Z1;INF209KA13Z9;Real Fund;105.6569;10-Jun-2026
"""
        // dropFirst skips the first line (column-header row), so only 1 record
        let schemes = service.parseNAVAll(text)
        #expect(schemes.count == 1, "First line is always skipped by dropFirst")
        #expect(schemes.first?.code == "119551", "Only the second line (real data row) should be parsed")
    }

    // MARK: - AMFIScheme: Identifiable

    @Test("AMFIScheme.id equals code (Identifiable conformance)")
    func amfiSchemeIDEqualsCode() {
        let service = AMFINavService()
        let schemes = service.parseNAVAll(sampleNAVText)
        #expect(schemes.count == 1)
        let scheme = schemes.first!
        #expect(scheme.id == scheme.code, "AMFIScheme.id must equal scheme.code (Identifiable)")
    }

    // MARK: - IST daily gate (testable without network)

    @Test("refreshIfNeeded is a no-op when lastFetchDate equals startOfTodayIST")
    func refreshNeededReturnsFalseWhenAlreadyFetchedToday() {
        // The AMFINavService exposes shouldFetch(lastFetchDate:referenceDate:) for testability.
        // We call it with lastFetch = startOfTodayIST → must return false.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = Date()
        let todayIST = cal.startOfDay(for: now)
        #expect(AMFINavService.shouldFetch(lastFetchDate: todayIST, referenceDate: now) == false,
                "When lastFetch >= startOfTodayIST the gate must return false (no-op)")
    }

    @Test("refreshIfNeeded kicks a fetch when lastFetchDate is .distantPast")
    func refreshNeededReturnsTrueWhenNeverFetched() {
        let now = Date()
        #expect(AMFINavService.shouldFetch(lastFetchDate: .distantPast, referenceDate: now) == true,
                "When lastFetch is .distantPast the gate must return true (fetch needed)")
    }

    @Test("refreshIfNeeded kicks a fetch when lastFetchDate is yesterday IST")
    func refreshNeededReturnsTrueWhenYesterday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let now = Date()
        #expect(AMFINavService.shouldFetch(lastFetchDate: yesterday, referenceDate: now) == true,
                "When lastFetch is yesterday IST the gate must return true")
    }
}
