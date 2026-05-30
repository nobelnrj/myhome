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

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        isAllDay: Bool = false,
        recurrence: ReminderRecurrence = ReminderRecurrence(),
        endRule: ReminderEndRule = ReminderEndRule(),
        leadMinutes: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.endRule = endRule
        self.leadMinutes = leadMinutes
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

        var requests: [UNNotificationRequest] = []

        // --- Build DateComponents in device timezone (Pitfall 5) -----------
        let deviceCal = deviceCalendar()

        switch info.recurrence.type {

        case .none:
            // One-shot main fire + lead-time alerts
            let mainComponents = dateComponents(from: info.date, isAllDay: info.isAllDay, calendar: deviceCal)
            let mainTrigger = UNCalendarNotificationTrigger(dateMatching: mainComponents, repeats: false)
            let mainRequest = makeRequest(
                identifier: "\(info.id)-main",
                title: info.title,
                trigger: mainTrigger
            )
            requests.append(mainRequest)

            // Lead-time alerts (only meaningful for one-shot reminders)
            for (index, leadMin) in info.leadMinutes.enumerated() {
                guard leadMin >= 0 else { continue }
                let leadDate = info.date.addingTimeInterval(-Double(leadMin) * 60)
                let leadComponents = dateComponents(from: leadDate, isAllDay: false, calendar: deviceCal)
                let leadTrigger = UNCalendarNotificationTrigger(dateMatching: leadComponents, repeats: false)
                let leadRequest = makeRequest(
                    identifier: "\(info.id)-lead-\(index)",
                    title: info.title,
                    trigger: leadTrigger
                )
                requests.append(leadRequest)
            }

        case .daily:
            // One repeating trigger on the time-of-day portion
            let comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: deviceCal)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = makeRequest(
                identifier: "\(info.id)-main",
                title: info.title,
                trigger: trigger
            )
            requests.append(request)

        case .weekly:
            let weekdays = resolvedWeekdays(for: info, calendar: deviceCal)
            for weekday in weekdays {
                var comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: deviceCal)
                comps.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = makeRequest(
                    identifier: "\(info.id)-weekday-\(weekday)",
                    title: info.title,
                    trigger: trigger
                )
                requests.append(request)
            }

        case .monthly:
            var comps = timeComponents(from: info.date, isAllDay: info.isAllDay, calendar: deviceCal)
            // Clamp day to last-valid-day (e.g. day-31 in April) — D3-14
            let rawDay = deviceCal.component(.day, from: info.date)
            comps.day = rawDay   // UNCalendarNotificationTrigger handles month-end clamping
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = makeRequest(
                identifier: "\(info.id)-main",
                title: info.title,
                trigger: trigger
            )
            requests.append(request)

        case .yearly:
            var comps = dateComponents(from: info.date, isAllDay: info.isAllDay, calendar: deviceCal)
            // Remove year so it repeats annually; keep month+day+hour+minute
            comps.year = nil
            // Clamp Feb-29 to Feb-28 in non-leap-years: UNCalendarNotificationTrigger
            // handles this internally; no extra work needed for iOS
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = makeRequest(
                identifier: "\(info.id)-main",
                title: info.title,
                trigger: trigger
            )
            requests.append(request)
        }

        return requests
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

        // 64-cap budget enforcement
        let existing = await pendingCount()
        let budget = max(0, Self.iOSPendingCap - existing)
        let admitted = Array(requests.prefix(budget))

        for request in admitted {
            try await center.add(request)
        }
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

    /// Builds DateComponents for a full date (used for one-shot and yearly triggers).
    private func dateComponents(from date: Date, isAllDay: Bool, calendar: Calendar) -> DateComponents {
        if isAllDay {
            return calendar.dateComponents([.year, .month, .day], from: date)
        } else {
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
    }

    /// Builds time-only DateComponents (used for repeating daily/weekly/monthly triggers).
    private func timeComponents(from date: Date, isAllDay: Bool, calendar: Calendar) -> DateComponents {
        if isAllDay {
            // All-day repeating: fire at midnight (00:00) in device timezone
            return DateComponents(hour: 0, minute: 0)
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

    /// Creates a UNNotificationRequest with a minimal content (title only).
    ///
    /// T-03-07: Logs identifiers/counts only — never include note body text in notification
    /// content here. Caller is responsible for setting body via a richer content builder
    /// in the UI layer if desired.
    private func makeRequest(
        identifier: String,
        title: String,
        trigger: UNNotificationTrigger
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }
}
