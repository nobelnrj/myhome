import Foundation
import SwiftData

// MARK: - NPSScheme

/// A parsed record from the npsnav.in /api/latest-min endpoint (D-01, ASSET-04 reversed, ASSET-03 reused).
///
/// id == code so that [NPSScheme] can drive SwiftUI lists without a separate Identifiable wrapper.
/// NPSScheme.name is empty from the bulk /latest-min endpoint — it is populated lazily from
/// /api/detailed if needed (Open Question 2: both Tier I/II appear; picker shows code prominently).
struct NPSScheme: Identifiable {
    /// NPS canonical scheme code (e.g. "SM001001").
    let code: String
    /// Scheme name — empty string until resolved from /api/detailed/{code}.
    let name: String
    /// NAV parsed as Decimal (never Double — Pitfall 17 / T-113-02).
    let nav: Decimal

    /// Identifiable conformance — id == code for exact dict lookup.
    var id: String { code }
}

// MARK: - NPSNavService

/// Fetch, parse, and cache npsnav.in /api/latest-min for NPS NAV auto-refresh
/// (D-01, D-06, ASSET-03 reused, ASSET-04 reversed, ASSET-09 staleness).
///
/// Design clones AMFINavService verbatim; five things swapped:
///   1. Class name → NPSNavService
///   2. Scheme struct → NPSScheme (no navDate from bulk endpoint)
///   3. URL constant → https://npsnav.in/api/latest-min
///   4. lastFetchKey → "npsNavLastFetchDate"
///   5. Asset field → npsSchemeCode (was amfiSchemeCode)
///   6. Parser body → parseNPSLatest (JSON array-of-pairs instead of semicolon text)
///
/// Everything else (IST gate, isFetching re-entrancy guard, Task{}, defer,
/// silent-fail catch, currentNAV/navAsOfDate update loop, context.save()) is identical.
///
/// T-113-03: only HTTPS; https://npsnav.in/api/latest-min hard-coded; ATS blocks plain HTTP by default.
/// T-113-01: malformed/empty body yields [] — cached NAV preserved; no crash.
/// T-113-02: JSON Number nav decoded via Double → Decimal(string: String(format:"%.4f",)) — never Decimal(exactly:).
@MainActor
@Observable
final class NPSNavService {

    // MARK: - Public state

    /// Injected by RootView.onAppear (same pattern as amfiNavService.modelContext — 11.1-04).
    var modelContext: ModelContext?

    /// In-memory scheme dictionary keyed by NPS scheme code (picker source).
    private(set) var cachedSchemes: [String: NPSScheme] = [:]

    /// Sorted scheme list for the picker UI (code-sorted — names may be empty from bulk endpoint).
    var schemeList: [NPSScheme] {
        cachedSchemes.values.sorted { $0.code < $1.code }
    }

    /// True while a background fetch is in progress (drives a spinner in the picker).
    private(set) var isFetching: Bool = false

    // MARK: - Constants

    /// T-113-03: HTTPS only — ATS also blocks plain HTTP by default on iOS.
    private static let npsLatestURL = URL(string: "https://npsnav.in/api/latest-min")!

    /// UserDefaults key for the last successful fetch date (Pitfall 5: stored as Date, not String).
    private static let lastFetchKey = "npsNavLastFetchDate"

    // MARK: - IST daily gate (extracted for testability)

    /// Returns true when a fetch is needed: last fetch date is before startOfTodayIST(referenceDate).
    ///
    /// Verbatim copy from AMFINavService.shouldFetch — extracted as static for testability (AC#5).
    nonisolated static func shouldFetch(lastFetchDate: Date, referenceDate: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: referenceDate)
        return lastFetchDate < startOfTodayIST
    }

    // MARK: - Entry points

    /// IST-gated refresh — no-op if already fetched today (D-06).
    ///
    /// Called synchronously from RootView.onChange(of: scenePhase) on .active.
    /// URLSession work is wrapped in Task {} — never blocks the main thread.
    func refreshIfNeeded() {
        guard let context = modelContext, !isFetching else { return }  // WR-02: re-entrancy guard
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
        guard let context = modelContext, !isFetching else { return }  // WR-02: no overlapping fetch
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
            // T-113-03: HTTPS only; ATS blocks plain HTTP by default
            let (data, _) = try await URLSession.shared.data(from: Self.npsLatestURL)

            let schemes = parseNPSLatest(data)

            // Rebuild the in-memory cache (picker reads this)
            var newCache: [String: NPSScheme] = [:]
            for scheme in schemes {
                newCache[scheme.code] = scheme
            }
            cachedSchemes = newCache

            // Update Asset.currentNAV + navAsOfDate for matching npsSchemeCode (D-01)
            let assets = try context.fetch(FetchDescriptor<Asset>())
            var didChange = false
            for asset in assets {
                guard let code = asset.npsSchemeCode,    // was asset.amfiSchemeCode
                      let scheme = newCache[code] else { continue }
                asset.currentNAV = scheme.nav
                // npsnav.in /latest-min has no per-entry date — use today IST start-of-day
                asset.navAsOfDate = todayIST
                didChange = true
            }
            if didChange {
                try context.save()
            }

            // Persist last-fetch date (Pitfall 5: store as Date, not String)
            UserDefaults.standard.set(todayIST, forKey: Self.lastFetchKey)

        } catch {
            // T-113-01, T-113-05: fail silently — log only; keep cached NAV; staleness badge signals age
            print("[NPSNavService] fetch/parse failed: \(error)")
        }
    }

    // MARK: - History date formatter (for SIPAccrualService reuse)

    /// npsnav.in and mfapi.in history endpoints use "dd-MM-yyyy" (e.g. "10-06-2026").
    /// DIFFERENT from AMFINavService.navDateFormatter which uses "dd-MMM-yyyy" (e.g. "10-Jun-2026").
    /// Never share these two formatters — PATTERNS.md Cross-Cutting Warning #3.
    static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f
    }()

    // MARK: - Parser

    /// Decode npsnav.in /api/latest-min JSON into [NPSScheme].
    ///
    /// Shape: `[["SM001001", 49.5429], ...]` — nav is a JSON Number (bare float).
    ///
    /// T-113-01: malformed/empty body → [] (never throw, never fatalError).
    /// T-113-02: nav decoded via Double intermediate then Decimal(string: String(format:"%.4f",))
    ///           — never Decimal(exactly: doubleValue) which is lossy (Pitfall 17).
    ///
    /// Open Question 1: defensive parse handles BOTH a bare top-level array
    /// AND a future object-with-data wrapper (try array first; fall through silently).
    func parseNPSLatest(_ data: Data) -> [NPSScheme] {
        // Primary shape: bare array [[code, nav], ...]
        if let entries = try? JSONDecoder().decode([NPSEntry].self, from: data) {
            return entries.compactMap { entry in
                // T-113-02: String intermediary — Decimal(string: String(format:"%.4f",))
                guard let nav = Decimal(string: String(format: "%.4f", entry.nav)) else { return nil }
                return NPSScheme(code: entry.code, name: "", nav: nav)
            }
        }

        // Live shape (confirmed 2026-06): object wrapper {"data": [[code, nav], ...], "metadata": {…}}.
        // Decode via a dedicated struct that extracts ONLY "data" and ignores sibling keys
        // (e.g. "metadata"). A [String: [NPSEntry]] dictionary decode would throw the moment any
        // sibling key's value is not [NPSEntry] (metadata is an object) — that bug made the picker
        // show "No Schemes Loaded" against the real endpoint while the bare-array fixture passed.
        if let wrapper = try? JSONDecoder().decode(NPSLatestWrapper.self, from: data) {
            return wrapper.data.compactMap { entry in
                guard let nav = Decimal(string: String(format: "%.4f", entry.nav)) else { return nil }
                return NPSScheme(code: entry.code, name: "", nav: nav)
            }
        }

        // T-113-01: all decode paths failed — return [] silently
        return []
    }

    // MARK: - NPSLatestWrapper (live object-shape decoder)

    /// Decodes the live `/api/latest-min` object shape `{"data": [[code, nav], ...], "metadata": {…}}`.
    /// Only `data` is read; unknown sibling keys (e.g. `metadata`) are ignored by Decodable.
    private struct NPSLatestWrapper: Decodable {
        let data: [NPSEntry]
    }

    // MARK: - NPSEntry (private Decodable helper)

    /// Decodes one element of the [[code, nav], ...] array-of-pairs.
    ///
    /// nav is a JSON Number — decoded as Double intermediate, never as String.
    /// Conversion to Decimal happens in parseNPSLatest via String(format:"%.4f",).
    private struct NPSEntry: Decodable {
        let code: String
        let nav: Double   // intermediate — converted to Decimal immediately (T-113-02)

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            code = try c.decode(String.self)
            nav  = try c.decode(Double.self)
        }
    }
}
