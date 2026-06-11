import Foundation
import SwiftData

// MARK: - AMFIScheme

/// A parsed record from the AMFI NAVAll.txt file (D-02, ASSET-03).
///
/// id == code so that [AMFIScheme] can drive SwiftUI lists without a separate Identifiable wrapper.
struct AMFIScheme: Identifiable {
    /// AMFI canonical scheme code (column 0 in NAVAll.txt).
    let code: String
    /// Scheme name trimmed from column 3.
    let name: String
    /// NAV parsed as Decimal (never Double — Pitfall 17).
    let nav: Decimal
    /// Date the NAV was published (parsed from DD-MMM-yyyy, Asia/Kolkata).
    let navDate: Date

    /// Identifiable conformance — id == code for exact dict lookup.
    var id: String { code }
}

// MARK: - AMFINavService

/// Fetch, parse, and cache AMFI NAVAll.txt for mutual fund NAV auto-refresh (D-02, D-06, ASSET-03).
///
/// Design mirrors `RoutineResetService` and `TransferScanService`:
/// - `@MainActor @Observable final class` with injected `modelContext: ModelContext?`
/// - `refreshIfNeeded()` is synchronous (IST gate) + wraps URLSession inside `Task {}`
/// - Silent failure on any network/parse error (D-07, T-11-06)
///
/// D-02: ONE NAVAll.txt fetch populates BOTH:
///   1. `cachedSchemes` — in-memory dictionary used by the AMFI scheme picker.
///   2. `Asset.currentNAV` / `Asset.navAsOfDate` — persistent NAV cache in SwiftData.
///
/// T-11-05: only HTTPS; `https://portal.amfiindia.com/spages/NAVAll.txt` hard-coded.
/// T-11-04: parser guards skip section headers, malformed rows, and non-Decimal NAVs; never fatalError.
@MainActor
@Observable
final class AMFINavService {

    // MARK: - Public state

    /// Injected by RootView.onAppear (same pattern as routineResetService.modelContext).
    var modelContext: ModelContext?

    /// In-memory scheme dictionary keyed by AMFI scheme code (D-02 picker source).
    private(set) var cachedSchemes: [String: AMFIScheme] = [:]

    /// Sorted scheme list for the picker UI (name-sorted for predictable search results).
    var schemeList: [AMFIScheme] {
        cachedSchemes.values.sorted { $0.name < $1.name }
    }

    /// True while a background fetch is in progress (drives a spinner in the picker, if desired).
    private(set) var isFetching: Bool = false

    // MARK: - Constants

    /// T-11-05: HTTPS only — ATS also blocks plain HTTP by default on iOS.
    private static let navAllURL = URL(string: "https://portal.amfiindia.com/spages/NAVAll.txt")!

    /// UserDefaults key for the last successful fetch date (Pitfall 5: stored as Date, not String).
    private static let lastFetchKey = "amfiNavLastFetchDate"

    // MARK: - IST daily gate (extracted for testability — AC#5)

    /// Returns true when a fetch is needed: last fetch date is before `startOfTodayIST(referenceDate)`.
    ///
    /// Extracted as a static func so AMFINavServiceTests can verify the gate logic without network.
    static func shouldFetch(lastFetchDate: Date, referenceDate: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: referenceDate)
        return lastFetchDate < startOfTodayIST
    }

    // MARK: - Entry points

    /// IST-gated refresh — no-op if already fetched today (D-06).
    ///
    /// Called synchronously from RootView.onChange(of: scenePhase) on `.active`.
    /// URLSession work is wrapped in Task {} — never blocks the main thread (T-11-08).
    func refreshIfNeeded() {
        guard let context = modelContext else { return }
        let now = Date()
        let lastFetch = UserDefaults.standard.object(forKey: Self.lastFetchKey) as? Date ?? .distantPast
        guard Self.shouldFetch(lastFetchDate: lastFetch, referenceDate: now) else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = cal.startOfDay(for: now)

        isFetching = true
        Task { await performFetch(context: context, todayIST: todayIST) }
    }

    /// Bypass the daily gate (for pull-to-refresh and "Fetch Now" button — D-06).
    func forceRefresh() {
        guard let context = modelContext else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = cal.startOfDay(for: Date())
        isFetching = true
        Task { await performFetch(context: context, todayIST: todayIST) }
    }

    // MARK: - Private fetch

    private func performFetch(context: ModelContext, todayIST: Date) async {
        defer { isFetching = false }
        do {
            // T-11-05: HTTPS only; ATS blocks plain HTTP by default
            let (data, _) = try await URLSession.shared.data(from: Self.navAllURL)

            guard let text = String(data: data, encoding: .utf8) else {
                print("[AMFINavService] Failed to decode UTF-8 from NAVAll.txt")
                return
            }

            let schemes = parseNAVAll(text)

            // Rebuild the in-memory cache (D-02: picker reads this)
            var newCache: [String: AMFIScheme] = [:]
            for scheme in schemes {
                newCache[scheme.code] = scheme
            }
            cachedSchemes = newCache

            // Update Asset.currentNAV + navAsOfDate for matching amfiSchemeCode (D-01)
            let assets = try context.fetch(FetchDescriptor<Asset>())
            var didChange = false
            for asset in assets {
                guard let code = asset.amfiSchemeCode,
                      let scheme = newCache[code] else { continue }
                asset.currentNAV = scheme.nav
                asset.navAsOfDate = scheme.navDate
                didChange = true
            }
            if didChange {
                try context.save()
            }

            // Persist last-fetch date (Pitfall 5: store as Date, not String)
            UserDefaults.standard.set(todayIST, forKey: Self.lastFetchKey)

        } catch {
            // D-07, T-11-06: fail silently — log only; keep cached NAV; staleness badge signals age
            print("[AMFINavService] fetch/parse failed: \(error)")
        }
    }

    // MARK: - Parser

    /// Date formatter for NAVAll.txt date column: "DD-MMM-yyyy" (e.g. "10-Jun-2026").
    ///
    /// Uses en_US_POSIX locale + Asia/Kolkata timezone (AMFI dates are IST — RESEARCH.md).
    private lazy var navDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f
    }()

    /// Parse the raw NAVAll.txt text into an array of AMFIScheme records.
    ///
    /// Format: 6 semicolon-delimited columns; first line is the column header (skipped by dropFirst).
    /// Section-header lines (no semicolons) are skipped.
    /// Rows with < 6 fields are skipped.
    /// Rows whose NAV column is not a valid Decimal are skipped (T-11-04: never fatalError).
    func parseNAVAll(_ text: String) -> [AMFIScheme] {
        var results: [AMFIScheme] = []
        let lines = text.components(separatedBy: "\n")
        // dropFirst skips the column-header line (line 0)
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // T-11-04: section-header lines have no semicolons — skip silently
            guard trimmed.contains(";") else { continue }
            let parts = trimmed.components(separatedBy: ";")
            // T-11-04: require at least 6 fields — skip malformed rows
            guard parts.count >= 6 else { continue }
            let code = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[3].trimmingCharacters(in: .whitespaces)
            let navString = parts[4].trimmingCharacters(in: .whitespaces)
            let dateString = parts[5].trimmingCharacters(in: .whitespaces)
            // T-11-04: non-numeric NAV → skip row; never fatalError
            guard let nav = Decimal(string: navString),
                  let navDate = navDateFormatter.date(from: dateString) else { continue }
            results.append(AMFIScheme(code: code, name: name, nav: nav, navDate: navDate))
        }
        return results
    }
}
