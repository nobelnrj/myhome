import Foundation
import UserNotifications

// MARK: - ReminderInfo

/// Input value type consumed by NotificationScheduler.buildRequests(for:).
///
/// Pure value type — no SwiftData dependencies. Maps the reminder fields stored
/// as Data? on Note/NoteBlock (ReminderRecurrence + ReminderEndRule) into a
/// decoded form ready for scheduling logic.
///
/// Identifier scheme (deterministic, enables exact cancel-by-identifier — D3-11):
///   Main fire:    "<reminderID>-main"
///   Lead alert N: "<reminderID>-lead-<index>"     (index 0-based, index 0 = first lead)
///   Weekly day D: "<reminderID>-weekday-<weekday>" (1=Sun…7=Sat)
public struct ReminderInfo: Sendable {
    /// Stable UUID matching the Note/NoteBlock that owns this reminder.
    public var id: UUID
    /// Display title for the notification content.
    public var title: String
    /// Fire date, stored UTC. buildRequests converts to device timezone for DateComponents.
    public var date: Date
    /// True = all-day reminder (builds DateComponents with [.year,.month,.day] only).
    public var isAllDay: Bool
    /// Recurrence rule. nil / type == .none means fire once.
    public var recurrence: ReminderRecurrence
    /// End rule. nil / type == .never means repeat forever.
    public var endRule: ReminderEndRule
    /// Lead-time advance alerts, expressed as minutes before the main fire date.
    /// e.g. [60, 1440] → alerts 1 hour and 1 day early.
    public var leadMinutes: [Int]

    /// UUID of the owning Note for deep-link routing. Set by ReminderEditView; nil
    /// is safe — the notification will fire but won't carry a deep-link payload.
    public var noteID: UUID? = nil
    /// UUID of the NoteBlock if this is a block-level reminder; nil for note-level.
    public var blockID: UUID? = nil

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        isAllDay: Bool = false,
        recurrence: ReminderRecurrence = ReminderRecurrence(),
        endRule: ReminderEndRule = ReminderEndRule(),
        leadMinutes: [Int] = [],
        noteID: UUID? = nil,
        blockID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.endRule = endRule
        self.leadMinutes = leadMinutes
        self.noteID = noteID
        self.blockID = blockID
    }
}

// MARK: - NotificationScheduler

/// Pure scheduling value type.
///
/// `buildRequests(for:)` is PURE — no async, no OS I/O, only value transformations.
/// `schedule(_:)`, `cancel(reminderID:leadCount:weekdays:)`, and `pendingCount()` are
/// the only members that touch the injected `NotificationCenterPort`.
///
/// 64-cap budget: iOS allows at most 64 pending notification requests at any time.
/// `schedule(_:)` enforces the budget by dropping requests beyond the cap after
/// all existing requests are counted (D3-15, T-03-05).
public struct NotificationScheduler {

    /// Maximum number of pending notification requests iOS allows (D3-15).
    public static let iOSPendingCap = 64

    /// Default hour-of-day for all-day reminders (WR-03).
    ///
    /// All-day reminders fire at 09:00 local rather than midnight, applied consistently
    /// across one-shot/daily/weekly/monthly/yearly so the contract never diverges by frequency.
    public static let allDayFireHour = 9

    /// Highest day-of-month a *repeating* monthly trigger can safely use in every month (WR-01).
    ///
    /// `UNCalendarNotificationTrigger(repeats: true)` does not fire on a missing day (e.g. day-31
    /// in April), so a `.never`-ending monthly reminder clamps its day to 28 to guarantee a fire
    /// every month. Bounded monthly reminders (after-N / end-on-date) are expanded into discrete
    /// dated triggers instead, which preserve the true day-of-month via Calendar clamping.
    public static let maxSafeMonthlyDay = 28

    private let center: any NotificationCenterPort

    public init(center: any NotificationCenterPort) {
        self.center = center
    }

    // MARK: - Pure request builder

    /// Builds the UNNotificationRequest array for a reminder — PURE (no async / OS I/O).
    ///
    /// Rules applied (in order):
    /// 1. End-on-date: if endRule.type == .onDate and reminder.date > endDate → return []
    /// 2. After-N: if endRule.type == .afterCount and occurrenceIndex >= count → return []
    /// 3. All-day vs timed: DateComponents from device timezone (Pitfall 5).
    /// 4. Recurrence expansion:
    ///    - .none:    one-shot trigger (UNCalendarNotificationTrigger(repeats: false))
    ///    - .daily:   one repeating trigger (UNCalendarNotificationTrigger(repeats: true))
    ///    - .weekly with weekdays: one repeating trigger per weekday (repeats: true each)
    ///    - .weekly no weekdays: one repeating trigger on the weekday of reminder.date
    ///    - .monthly: one repeating trigger (clamp day to last-valid for the month — D3-14)
    ///    - .yearly:  one repeating trigger (clamp Feb-29 to Feb-28 in non-leap-years)
    /// 5. Lead-time alerts: one non-repeating trigger per leadMinutes entry (only when recurrence == .none).
    ///
    /// - Parameters:
    ///   - info: The reminder to schedule.
    ///   - occurrenceIndex: App-side counter for "after N" tracking (0-based). Default 0.
    /// - Returns: Array of UNNotificationRequest ready to be passed to center.add(_:).
    public func buildRequests(
        for info: ReminderInfo,
        occurrenceIndex: Int = 0
    ) throws -> [UNNotificationRequest] {

        // --- End-rule guard ------------------------------------------------
        switch info.endRule.type {
        case .onDate:
            if let endDate = info.endRule.endDate, info.date > endDate {
                return []
            }
        case .afterCount:
            if let count = info.endRule.occurrenceCount, occurrenceIndex >= count {
                return []
            }
        case .never:
            break
        }

        // --- Build DateComponents in device timezone (Pitfall 5) -----------
        let deviceCal = deviceCalendar()

        switch info.recurrence.type {
        case .none:
            return oneShotRequests(for: info, calendar: deviceCal)
        case .daily, .weekly, .monthly, .yearly:
            // WR-02: bounded recurrences (after-N / end-on-date) expand into discrete dated
            // triggers so they actually stop. Only `.never` uses a single repeating trigger.
            switch info.endRule.type {
            case .never:
                return repeatingRequests(for: info, calendar: deviceCal)
            case .afterCount:
                let n = max(0, min(info.endRule.occurrenceCount ?? 1, Self.iOSPendingCap))
                let dates = occurrenceDates(for: info, calendar: deviceCal, limit: n)
                return discreteRequests(for: info, dates: dates, calendar: deviceCal)
            case .onDate:
                guard let endDate = info.endRule.endDate else {
                    return repeatingRequests(for: info, calendar: deviceCal)
                }
                // Cutoff is the end of the chosen end-day (inclusive of that whole day).
                let cutoff = deviceCal.startOfDay(for: endDate).addingTimeInterval(86_400)
                let candidates = occurrenceDates(for: info, calendar: deviceCal, limit: Self.iOSPendingCap)
                let dates = candidates.filter { $0 < cutoff }
                return discreteRequests(for: info, dates: dates, calendar: deviceCal)
            }
        }
    }

    // MARK: - Request builders (pure)

    /// One-shot main fire plus any lead-time advance alerts (recurrence == .none).
    private func oneShotRequests(for info: ReminderInfo, calendar: Calendar) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []

        let mainComponents = dateComponents(from: info.date, isAllDay: info.isAllDay, calendar: calendar)
        let mainTrigger = UNCalendarNotificationTrigger(dateMatching: mainComponents, repeats: false)
        requests.append(makeRequest(identifier: "\(info.id)-main", info: info, trigger: mainTrigger))

        // Lead-time alerts (only meaningful for one-shot reminders)
        for (index, leadMin) in info.leadMinutes.enumerated() {
            guard leadMin >= 0 else { continue }
            let leadDate = info.date.addingTimeInterval(-Double(leadMin) * 60)
            let leadComponents = dateComponents(from: leadDate, isAllDay: false, calendar: calendar)
            let leadTrigger = UNCalendarNotificationTrigger(dateMatching: leadComponents, repeats: false)
            requests.append(makeRequest(identifier: "\(info.id)-lead-\(index)", info: info, trigger: leadTrigger))
        }

        return requests
    }

    /// Single repeating trigger(s) for an unbounded (`.never`) recurrence.
    ///
    /// - daily:   one repeating trigger on the time-of-day.
    /// - weekly:  one repeating trigger per resolved weekday.
    /// - monthly: one repeating trigger, day clamped to `maxSafeMonthlyDay` (WR-01) so it fires
    ///            every month. Bounded monthly reminders use `discreteRequests` for true days.
    /// - yearly:  one repeating trigger on month+day+time (Feb-29 clamped by iOS).
    private func repeatingRequests(for info: ReminderInfo, calendar: Calendar) -> [UNNotificationRequest] {
        switch info.recurrence.type {
        case .daily:
            let comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: calendar)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            return [makeRequest(identifier: "\(info.id)-main", info: info, trigger: trigger)]

        case .weekly:
            let weekdays = resolvedWeekdays(for: info, calendar: calendar)
            return weekdays.map { weekday in
                var comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: calendar)
                comps.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                return makeRequest(identifier: "\(info.id)-weekday-\(weekday)", info: info, trigger: trigger)
            }

        case .monthly:
            var comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: calendar)
            // WR-01: explicitly clamp day to a day present in every month so the trigger fires.
            let rawDay = calendar.component(.day, from: info.date)
            comps.day = min(rawDay, Self.maxSafeMonthlyDay)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            return [makeRequest(identifier: "\(info.id)-main", info: info, trigger: trigger)]

        case .yearly:
            var comps = dateComponents(from: info.date, isAllDay: info.isAllDay, calendar: calendar)
            comps.year = nil   // repeat annually; iOS clamps Feb-29 in non-leap years
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            return [makeRequest(identifier: "\(info.id)-main", info: info, trigger: trigger)]

        case .none:
            return []
        }
    }

    /// Non-repeating dated triggers for a bounded recurrence (after-N / end-on-date).
    ///
    /// Each occurrence gets identifier `<id>-occ-<index>` so it survives cancellation
    /// (`cancel(reminderID:…)` removes the whole `-occ-*` range).
    private func discreteRequests(for info: ReminderInfo, dates: [Date], calendar: Calendar) -> [UNNotificationRequest] {
        dates.enumerated().map { index, date in
            let comps = dateComponents(from: date, isAllDay: info.isAllDay, calendar: calendar)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            return makeRequest(identifier: "\(info.id)-occ-\(index)", info: info, trigger: trigger)
        }
    }

    /// Generates up to `limit` successive occurrence dates by stepping the recurrence interval
    /// forward from `info.date`. Used to expand bounded recurrences into discrete triggers.
    private func occurrenceDates(for info: ReminderInfo, calendar: Calendar, limit: Int) -> [Date] {
        guard limit > 0 else { return [] }
        let start = info.date

        switch info.recurrence.type {
        case .none:
            return [start]

        case .daily:
            return (0..<limit).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }

        case .weekly:
            let weekdays = resolvedWeekdays(for: info, calendar: calendar)
            if weekdays.count <= 1 {
                return (0..<limit).compactMap { calendar.date(byAdding: .day, value: $0 * 7, to: start) }
            }
            // Multiple weekdays: walk forward day-by-day collecting matches.
            let targetDays = Set(weekdays)
            var result: [Date] = []
            var cursor = start
            var safety = 0
            let maxSteps = limit * 7 + 14
            while result.count < limit && safety < maxSteps {
                if targetDays.contains(calendar.component(.weekday, from: cursor)) {
                    result.append(cursor)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                safety += 1
            }
            return result

        case .monthly:
            // Adding months to the original date clamps to month-end where needed (e.g. Jan-31 → Feb-28).
            return (0..<limit).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }

        case .yearly:
            return (0..<limit).compactMap { calendar.date(byAdding: .year, value: $0, to: start) }
        }
    }

    // MARK: - Port-touching members

    /// Schedules all requests for a reminder, enforcing the iOS 64-pending cap.
    ///
    /// Strategy (D3-15, T-03-05):
    /// 1. Count existing pending requests via `pendingCount()`.
    /// 2. Admit up to `iOSPendingCap - existingCount` new requests (oldest/later ones trimmed).
    /// 3. Add admitted requests to the center.
    public func schedule(_ info: ReminderInfo) async throws {
        let requests = try buildRequests(for: info)
        guard !requests.isEmpty else { return }

        // 64-cap budget enforcement.
        // CR-01: prioritize so the actual reminder fire is never dropped in favour of a
        // pre-alert. Main / first occurrence first, then other fires, then lead alerts last.
        let existing = await pendingCount()
        let budget = max(0, Self.iOSPendingCap - existing)
        let prioritized = requests.sorted { Self.admissionRank($0.identifier) < Self.admissionRank($1.identifier) }
        let admitted = Array(prioritized.prefix(budget))

        for request in admitted {
            try await center.add(request)
        }
    }

    /// Admission priority for the 64-cap (CR-01): lower fires first, so leads are trimmed before
    /// the reminder itself. The primary fire (`-main` / first `-occ-0`) is never dropped while a
    /// lead alert survives.
    static func admissionRank(_ identifier: String) -> Int {
        if identifier.hasSuffix("-main") || identifier.hasSuffix("-occ-0") { return 0 }
        if identifier.contains("-lead-") { return 2 }
        return 1   // weekday / later occurrences
    }

    /// Removes all pending requests for a reminder (main + leads + weekdays).
    ///
    /// Uses the deterministic identifier scheme so every possible identifier is
    /// computed locally — no need to query pending requests first (D3-11).
    ///
    /// - Parameters:
    ///   - reminderID: The UUID of the Note/NoteBlock whose requests should be removed.
    ///   - leadCount: Number of lead-time alerts to cancel (0 if none).
    ///   - weekdays: Weekly-weekday identifiers to cancel (empty if not weekly).
    public func cancel(reminderID: UUID, leadCount: Int = 0, weekdays: [Int] = []) {
        var ids: [String] = ["\(reminderID)-main"]
        for index in 0..<leadCount {
            ids.append("\(reminderID)-lead-\(index)")
        }
        for weekday in weekdays {
            ids.append("\(reminderID)-weekday-\(weekday)")
        }
        // WR-02: bounded recurrences schedule discrete `-occ-<n>` triggers (up to the cap).
        // Remove the whole range so an after-N / end-on-date reminder is fully cleared.
        for index in 0..<Self.iOSPendingCap {
            ids.append("\(reminderID)-occ-\(index)")
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Returns the current count of pending notification requests.
    public func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    // MARK: - Private helpers

    private func deviceCalendar() -> Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }

    /// Builds DateComponents for a full date (used for one-shot, yearly, and discrete triggers).
    ///
    /// WR-03: all-day reminders fire at `allDayFireHour` (09:00 local), never midnight.
    private func dateComponents(from date: Date, isAllDay: Bool, calendar: Calendar) -> DateComponents {
        if isAllDay {
            var comps = calendar.dateComponents([.year, .month, .day], from: date)
            comps.hour = Self.allDayFireHour
            comps.minute = 0
            return comps
        } else {
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
    }

    /// Builds time-only DateComponents (used for repeating daily/weekly/monthly triggers).
    ///
    /// WR-03: all-day repeating reminders fire at `allDayFireHour` (09:00 local), not midnight,
    /// consistent with the timed and yearly paths.
    private func timeComponents(from date: Date, isAllDay: Bool, calendar: Calendar) -> DateComponents {
        if isAllDay {
            return DateComponents(hour: Self.allDayFireHour, minute: 0)
        } else {
            return calendar.dateComponents([.hour, .minute], from: date)
        }
    }

    /// Resolves the effective weekdays for a weekly reminder.
    /// Falls back to the weekday of info.date if no weekdays are specified.
    private func resolvedWeekdays(for info: ReminderInfo, calendar: Calendar) -> [Int] {
        if let days = info.recurrence.weekdays, !days.isEmpty {
            return days
        }
        // Fall back to the weekday of the reminder's date
        let weekday = calendar.component(.weekday, from: info.date)
        return [weekday]
    }

    /// Creates a UNNotificationRequest with category + deep-link payload stamped.
    ///
    /// Sets `categoryIdentifier` to `kReminderCategoryID` so iOS attaches the
    /// Complete/Snooze action buttons (Fix A — T-03-14).
    /// Sets `userInfo` with noteID/blockID/originalTitle for deep-link routing
    /// (Fix A — T-03-14; userInfo consumed by NotificationActionDelegate).
    ///
    /// T-03-16: only UUIDs and title in userInfo — no note body text in logs.
    private func makeRequest(
        identifier: String,
        info: ReminderInfo,
        trigger: UNNotificationTrigger
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = info.title
        content.sound = .default
        // Stamp actionable category so Complete/Snooze buttons appear on delivery
        content.categoryIdentifier = kReminderCategoryID
        // Stamp deep-link payload so banner tap routes to the correct note/row
        var userInfo: [String: String] = [:]
        if let n = info.noteID { userInfo["noteID"] = n.uuidString }
        if let b = info.blockID { userInfo["blockID"] = b.uuidString }
        userInfo["originalTitle"] = info.title
        content.userInfo = userInfo
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }
}
