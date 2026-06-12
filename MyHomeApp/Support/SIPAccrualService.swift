import Foundation
import SwiftData
import UserNotifications

// MARK: - NAV History Entry

/// A parsed historical NAV entry (date + nav) for nearest-prior lookup.
typealias NAVHistoryEntry = (date: Date, nav: Decimal)

// MARK: - MF History Decodable

/// mfapi.in full history response shape.
/// Shape: {"meta":{...},"data":[{"date":"DD-MM-YYYY","nav":"string"}],"status":"SUCCESS"}
private struct MFHistoryResponse: Decodable {
    let data: [MFHistoryEntry]
    let status: String

    struct MFHistoryEntry: Decodable {
        let date: String
        let nav: String   // JSON String, e.g. "102.88080" — parse via Decimal(string:)
    }
}

// MARK: - NPS History Decodable

/// npsnav.in historical response shape.
/// Shape: [{"date":"DD-MM-YYYY","nav":double}, ...]
private struct NPSHistoryEntry: Decodable {
    let date: String
    let nav: Double   // JSON Number — convert via String(format:) intermediary (Pitfall 1)
}

// MARK: - Reconcile Category

/// UNNotificationCategory identifier for monthly SIP reconcile reminders.
/// Distinct from kReminderCategoryID (note domain) — keeps concerns separated (RESEARCH Pattern 5).
let kReconcileCategoryID = "com.myhome.sip.reconcile"

// MARK: - SIPAccrualService

/// SIP accrual engine: finds every elapsed installment date for every active SIP,
/// prices it at the exact-date historical NAV (mfapi.in for MF, npsnav.in for NPS,
/// nearest-prior fallback), splits NPS amounts across 3 strategy holdings by allocation %,
/// writes Contribution rows, bumps Asset.units, advances lastAccruedDate after save,
/// and schedules the monthly reconcile reminder.
///
/// Design mirrors AMFINavService:
/// - `@MainActor @Observable final class` with injected `modelContext: ModelContext?`
/// - `accrueIfNeeded()` is synchronous; URLSession work is wrapped in `Task {}`
/// - Silent failure on any network/parse error (T-112-01)
///
/// T-112-05: only HTTPS URLs; ATS blocks plain HTTP by default on iOS.
/// T-112-06: lastAccruedDate advances ONLY after context.save() succeeds (Pitfall 5).
@MainActor
@Observable
final class SIPAccrualService {

    // MARK: - Public state

    /// Injected by RootView.onAppear (same pattern as AMFINavService.modelContext).
    var modelContext: ModelContext?

    /// True while a background accrual pass is in progress (re-entrancy guard — Open Question 3).
    private(set) var isAccruing: Bool = false

    // MARK: - Session cache (Pitfall 8: one fetch per unique fund per accrual pass)

    /// In-memory history cache keyed by scheme code (amfi or nps).
    /// Cleared at the end of each accrual pass or on next call.
    private var historyCache: [String: [NAVHistoryEntry]] = [:]

    // MARK: - Date formatters

    /// History date formatter for BOTH mfapi.in and npsnav.in: "DD-MM-YYYY" (e.g. "10-06-2026").
    ///
    /// DIFFERENT from AMFINavService.navDateFormatter which uses "DD-MMM-YYYY" ("10-Jun-2026").
    /// Pitfall 2: never share these formatters. Define separately; never reuse AMFINavService's.
    nonisolated(unsafe) static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        f.isLenient = false   // Pitfall 2: strict parsing — must not accept "dd-MMM-yyyy" strings
        return f
    }()

    // MARK: - Entry point

    /// Accrual entry point — no-op when isAccruing is already true or modelContext is nil.
    ///
    /// Called synchronously from RootView.onChange(of: scenePhase) on `.active`.
    /// URLSession work is wrapped in Task {} — never blocks the main thread.
    func accrueIfNeeded() {
        guard let context = modelContext, !isAccruing else { return }  // re-entrancy guard
        isAccruing = true
        Task { await performAccrual(context: context) }
    }

    // MARK: - Private accrual

    private func performAccrual(context: ModelContext) async {
        defer { isAccruing = false }
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = istCal.startOfDay(for: Date())

        do {
            // Fetch all active SIPs (D-04: skip isActive == false)
            let allSIPs = try context.fetch(FetchDescriptor<SIP>())
            let activeSIPs = allSIPs.filter { $0.isActive }

            // Fetch all SIPAmountChange records for amount-history resolution
            let allChanges = try context.fetch(FetchDescriptor<SIPAmountChange>())

            // Clear session cache for this pass
            historyCache = [:]

            for sip in activeSIPs {
                guard let asset = fetchAsset(for: sip.assetID, context: context) else {
                    print("[SIPAccrualService] No asset found for SIP \(sip.id) — skipping")
                    continue
                }

                // Compute elapsed installment dates since last accrual
                let dates = elapsedInstallmentDates(
                    dayOfMonth: sip.dayOfMonth,
                    startDate: sip.startDate,
                    lastAccruedDate: sip.lastAccruedDate,
                    today: todayIST,
                    calendar: istCal
                )
                guard !dates.isEmpty else { continue }

                let sipChanges = allChanges.filter { $0.sipID == sip.id }
                var lastProcessedDate: Date? = nil

                // Determine if this is an NPS SIP (has allocation set)
                let isNPS = (sip.npsAllocationE + sip.npsAllocationC + sip.npsAllocationG) == 100
                    && (sip.npsAssetE != nil || sip.npsAssetC != nil || sip.npsAssetG != nil)

                for installmentDate in dates {
                    let effectiveAmt = effectiveAmount(forDate: installmentDate, sip: sip, changes: sipChanges)

                    if isNPS {
                        // NPS: split across 3 strategy holdings at each holding's own NAV
                        let split = splitAmount(effectiveAmt,
                                                eP: sip.npsAllocationE,
                                                cP: sip.npsAllocationC,
                                                gP: sip.npsAllocationG)

                        let strategies: [(assetIDOpt: UUID?, amount: Decimal, schemeCode: String?)] = [
                            (sip.npsAssetE, split.e, fetchNPSSchemeCode(for: sip.npsAssetE, context: context)),
                            (sip.npsAssetC, split.c, fetchNPSSchemeCode(for: sip.npsAssetC, context: context)),
                            (sip.npsAssetG, split.g, fetchNPSSchemeCode(for: sip.npsAssetG, context: context)),
                        ]

                        var allInserted = true
                        for (stratAssetIDOpt, stratAmt, schemeCode) in strategies {
                            guard let stratAssetID = stratAssetIDOpt else { continue }
                            guard let code = schemeCode else {
                                print("[SIPAccrualService] No NPS scheme code for asset \(stratAssetID) — skipping date \(installmentDate)")
                                allInserted = false
                                break
                            }
                            guard let stratAsset = fetchAsset(for: stratAssetID, context: context) else {
                                allInserted = false; break
                            }

                            // Fetch history (session-cached)
                            let history = await fetchNPSHistory(schemeCode: code)
                            guard let navEntry = navEntry(for: installmentDate, in: history) else {
                                print("[SIPAccrualService] No NAV for \(code) on \(installmentDate) — skipping date")
                                allInserted = false; break
                            }
                            guard navEntry.nav > 0 else {
                                print("[SIPAccrualService] nav <= 0 for \(code) — skipping date")
                                allInserted = false; break
                            }
                            guard let unitsAdded = units(amount: stratAmt, nav: navEntry.nav) else {
                                print("[SIPAccrualService] units returned nil (nav<=0) — skipping date")
                                allInserted = false; break
                            }

                            let contribution = Contribution(
                                assetID: stratAssetID,
                                sipID: sip.id,
                                date: installmentDate,
                                amount: stratAmt,
                                navUsed: navEntry.nav,
                                navDate: navEntry.date,
                                unitsAdded: unitsAdded,
                                isEstimate: true
                            )
                            context.insert(contribution)
                            stratAsset.units = (stratAsset.units ?? Decimal(0)) + unitsAdded
                        }
                        if allInserted { lastProcessedDate = installmentDate }

                    } else {
                        // MF SIP: single holding, 100% allocation
                        guard let amfiCode = asset.amfiSchemeCode else {
                            print("[SIPAccrualService] No AMFI scheme code for MF SIP \(sip.id) — skipping")
                            break
                        }

                        let history = await fetchMFHistory(schemeCode: amfiCode)
                        guard let navEntryResult = navEntry(for: installmentDate, in: history) else {
                            print("[SIPAccrualService] No NAV for \(amfiCode) on \(installmentDate) — skipping date")
                            continue
                        }
                        guard navEntryResult.nav > 0 else {
                            print("[SIPAccrualService] nav <= 0 for \(amfiCode) — skipping date")
                            continue
                        }
                        guard let unitsAdded = units(amount: effectiveAmt, nav: navEntryResult.nav) else {
                            continue
                        }

                        let contribution = Contribution(
                            assetID: sip.assetID,
                            sipID: sip.id,
                            date: installmentDate,
                            amount: effectiveAmt,
                            navUsed: navEntryResult.nav,
                            navDate: navEntryResult.date,
                            unitsAdded: unitsAdded,
                            isEstimate: true
                        )
                        context.insert(contribution)
                        asset.units = (asset.units ?? Decimal(0)) + unitsAdded
                        lastProcessedDate = installmentDate
                    }
                }

                // CR-01: explicit save — advance cursor ONLY after save succeeds (Pitfall 5 / T-112-06)
                if lastProcessedDate != nil {
                    try context.save()
                    sip.lastAccruedDate = lastProcessedDate
                    try context.save()

                    // Schedule monthly reconcile reminder after first successful accrual
                    await scheduleReconcileReminder(for: sip)
                }
            }
        } catch {
            // T-112-01: silent-fail — keep existing state; staleness badge / no-accrual is the UX signal
            print("[SIPAccrualService] accrual failed: \(error)")
        }
    }

    // MARK: - NAV Fetch (session-cached)

    private func fetchMFHistory(schemeCode: String) async -> [NAVHistoryEntry] {
        if let cached = historyCache[schemeCode] { return cached }
        guard let url = URL(string: "https://api.mfapi.in/mf/\(schemeCode)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsed = parseMFHistory(data)
            historyCache[schemeCode] = parsed
            return parsed
        } catch {
            print("[SIPAccrualService] MF history fetch failed for \(schemeCode): \(error)")
            return []
        }
    }

    private func fetchNPSHistory(schemeCode: String) async -> [NAVHistoryEntry] {
        if let cached = historyCache[schemeCode] { return cached }
        guard let url = URL(string: "https://npsnav.in/api/historical/\(schemeCode)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsed = parseNPSHistory(data)
            historyCache[schemeCode] = parsed
            return parsed
        } catch {
            print("[SIPAccrualService] NPS history fetch failed for \(schemeCode): \(error)")
            return []
        }
    }

    // MARK: - Parsers (nonisolated: pure functions — no actor state access)

    /// Parse mfapi.in full-history response.
    /// `nav` field is a String (e.g. "102.88080") — parse via Decimal(string:).
    /// Date format: "DD-MM-YYYY" — parse via historyDateFormatter.
    /// T-112-01: malformed rows silently dropped (never fatalError).
    nonisolated func parseMFHistory(_ data: Data) -> [NAVHistoryEntry] {
        guard let response = try? JSONDecoder().decode(MFHistoryResponse.self, from: data) else {
            return []
        }
        // Response is reverse-chronological (newest first) — preserve order for navEntry(for:in:)
        return response.data.compactMap { entry -> NAVHistoryEntry? in
            guard let date = Self.historyDateFormatter.date(from: entry.date),
                  let nav = Decimal(string: entry.nav),
                  nav > 0 else { return nil }
            return (date: date, nav: nav)
        }
    }

    /// Parse npsnav.in historical response.
    /// `nav` field is a JSON Number (Double) — convert via String(format:"%.4f",) (Pitfall 1).
    /// Date format: "DD-MM-YYYY" — parse via historyDateFormatter.
    /// T-112-01: malformed rows silently dropped.
    nonisolated func parseNPSHistory(_ data: Data) -> [NAVHistoryEntry] {
        guard let entries = try? JSONDecoder().decode([NPSHistoryEntry].self, from: data) else {
            return []
        }
        return entries.compactMap { entry -> NAVHistoryEntry? in
            guard let date = Self.historyDateFormatter.date(from: entry.date),
                  // Pitfall 1: never Decimal(exactly:); go through String intermediary
                  let nav = Decimal(string: String(format: "%.4f", entry.nav)),
                  nav > 0 else { return nil }
            return (date: date, nav: nav)
        }
    }

    // MARK: - Nearest-prior NAV lookup (D-02)

    /// Returns the first entry whose date <= targetDate in a reverse-chronological array.
    ///
    /// This implements the nearest-prior fallback (D-02): on holidays/weekends where no NAV
    /// was published, returns the last published NAV on or before the installment date.
    /// Returns nil when targetDate precedes the oldest entry in the array.
    nonisolated func navEntry(for targetDate: Date, in history: [NAVHistoryEntry]) -> NAVHistoryEntry? {
        // history is sorted newest-first; first entry with date <= target is the nearest-prior
        history.first { $0.date <= targetDate }
    }

    // MARK: - Elapsed installment date enumeration (D-02, Pattern 3)

    /// Enumerates all installment dates from lastAccruedDate (exclusive) up to today (inclusive),
    /// walking month-by-month using an IST Gregorian calendar.
    ///
    /// Day-of-month clamping: uses `calendar.range(of: .day, in: .month, for:)` to find the last
    /// valid day in each month, then clamps dayOfMonth to that max (e.g. Feb 31 → Feb 28/29).
    /// This avoids Foundation's `date(from:)` / `date(bySetting:)` overflow behavior where
    /// day > monthLength rolls over into the next month instead of clamping.
    ///
    /// - Parameters:
    ///   - dayOfMonth: SIP installment day (1–31; manually clamped to month-end per month)
    ///   - startDate: First date from which accrual is allowed (SIP.startDate)
    ///   - lastAccruedDate: Exclusive lower bound; nil means accrue from startDate
    ///   - today: IST start-of-day (inclusive upper bound)
    ///   - calendar: IST Gregorian calendar
    nonisolated func elapsedInstallmentDates(
        dayOfMonth: Int,
        startDate: Date,
        lastAccruedDate: Date?,
        today: Date,
        calendar: Calendar
    ) -> [Date] {
        var results: [Date] = []

        // Determine the starting year+month by decomposing lowerBound
        let lowerBound: Date = lastAccruedDate ?? startDate.addingTimeInterval(-1)
        let lbComps = calendar.dateComponents([.year, .month], from: lowerBound)
        guard var year = lbComps.year, var month = lbComps.month else { return results }

        // Safety limit: no SIP can have more than 600 months of history (50 years)
        for _ in 0..<600 {
            // Clamp dayOfMonth to the actual max day in this year+month
            let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!
            let clampedDay = min(dayOfMonth, range.upperBound - 1)

            // Build the installment date at midnight IST (hour=0, minute=0, second=0)
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = clampedDay
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            guard let installmentDate = calendar.date(from: comps) else { break }

            if installmentDate > today { break }

            if installmentDate > lowerBound && installmentDate >= startDate {
                results.append(installmentDate)
            }

            // Advance to next month
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }

        return results
    }

    // MARK: - Amount-history resolution (D-07)

    /// Returns the effective SIP amount for a given installment date.
    ///
    /// Applies the latest SIPAmountChange whose effectiveFrom <= date.
    /// Falls back to sip.amount when no change precedes the date (D-07: next-installment-only).
    nonisolated func effectiveAmount(forDate date: Date, sip: SIP, changes: [SIPAmountChange]) -> Decimal {
        // Filter to changes that apply on or before the installment date
        let applicable = changes
            .filter { $0.sipID == sip.id && $0.effectiveFrom <= date }
            .sorted { $0.effectiveFrom > $1.effectiveFrom } // latest first
        return applicable.first?.amount ?? sip.amount
    }

    // MARK: - NPS allocation split (D-01)

    /// Splits a total SIP amount across 3 NPS strategy allocations.
    ///
    /// Rounds E and C down to 2dp via NSDecimalNumberHandler(.down, scale:2).
    /// Residual (total − e − c) assigned to whichever slice has the largest allocation %
    /// so the three values sum EXACTLY to total (D-01 remainder-paisa rule).
    ///
    /// For MF SIPs (single holding, 100%) this degenerates to the whole amount on one slice.
    nonisolated func splitAmount(_ total: Decimal, eP: Int, cP: Int, gP: Int) -> (e: Decimal, c: Decimal, g: Decimal) {
        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )

        // Compute E and C with round-down
        let rawE = (total as NSDecimalNumber)
            .multiplying(by: NSDecimalNumber(value: eP))
            .dividing(by: NSDecimalNumber(value: 100), withBehavior: handler)
            .decimalValue
        let rawC = (total as NSDecimalNumber)
            .multiplying(by: NSDecimalNumber(value: cP))
            .dividing(by: NSDecimalNumber(value: 100), withBehavior: handler)
            .decimalValue

        // Determine largest-allocation slice for remainder
        let maxP = max(eP, cP, gP)

        if maxP == eP && eP >= cP && eP >= gP {
            // Remainder goes to E (largest)
            let rawG = (total as NSDecimalNumber)
                .multiplying(by: NSDecimalNumber(value: gP))
                .dividing(by: NSDecimalNumber(value: 100), withBehavior: handler)
                .decimalValue
            let eShare = total - rawC - rawG
            return (e: eShare, c: rawC, g: rawG)
        } else if maxP == cP && cP >= gP {
            // Remainder goes to C
            let rawG = (total as NSDecimalNumber)
                .multiplying(by: NSDecimalNumber(value: gP))
                .dividing(by: NSDecimalNumber(value: 100), withBehavior: handler)
                .decimalValue
            let cShare = total - rawE - rawG
            return (e: rawE, c: cShare, g: rawG)
        } else {
            // Remainder goes to G (largest)
            let gShare = total - rawE - rawC
            return (e: rawE, c: rawC, g: gShare)
        }
    }

    // MARK: - Units calculation (D-02, T-112-02)

    /// Computes units = amount ÷ nav, rounded down to 4 decimal places.
    ///
    /// T-112-02: returns nil when nav <= 0 to guard against division by zero/negative.
    nonisolated func units(amount: Decimal, nav: Decimal) -> Decimal? {
        guard nav > 0 else { return nil }
        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 4,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let result = (amount as NSDecimalNumber)
            .dividing(by: nav as NSDecimalNumber, withBehavior: handler)
            .decimalValue
        return result
    }

    // MARK: - Reconcile reminder scheduling (RESEARCH Pattern 5, Pitfall 6)

    /// Schedules a monthly reconcile reminder for a SIP using direct UNUserNotificationCenter.
    ///
    /// NOT using NotificationScheduler.makeRequest — different domain (asset vs note).
    /// Identifier: "sip-reconcile-{sip.id.uuidString}" (distinct from kReminderCategoryID domain).
    /// Day clamped to min(sip.dayOfMonth + 3, NotificationScheduler.maxSafeMonthlyDay) (Pitfall 6).
    func scheduleReconcileReminder(for sip: SIP) async {
        // Pitfall 6: clamp to maxSafeMonthlyDay (28) so the trigger fires every month
        let clampedDay = min(sip.dayOfMonth + 3, NotificationScheduler.maxSafeMonthlyDay)
        var comps = DateComponents()
        comps.day = clampedDay
        comps.hour = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Confirm SIP units from statement"
        content.sound = .default
        content.categoryIdentifier = kReconcileCategoryID
        content.userInfo = ["sipID": sip.id.uuidString]
        let identifier = "sip-reconcile-\(sip.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Cancels the monthly reconcile reminder for a deactivated SIP.
    func cancelReconcileReminder(for sip: SIP) {
        let identifier = "sip-reconcile-\(sip.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Private helpers

    private func fetchAsset(for assetID: UUID, context: ModelContext) -> Asset? {
        let descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
        return try? context.fetch(descriptor).first
    }

    private func fetchNPSSchemeCode(for assetID: UUID?, context: ModelContext) -> String? {
        guard let id = assetID else { return nil }
        let descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor).first)?.npsSchemeCode
    }
}
