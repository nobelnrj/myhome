import Testing
import Foundation
import UserNotifications
@testable import MyHome

// Requirements: SC-R2 ("after N" stops, end-on-date stops, weekly weekdays)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/RecurrenceTests
// Plan 03-03 implementation — turns the Wave 0 stubs green.

/// RecurrenceTests — pure-logic tests for recurrence expansion and end-rule enforcement.
///
/// SC-R2: Daily/Weekly(weekdays)/Monthly/Yearly produce correct repeating triggers;
///        "After N" end rule stops scheduling after the Nth occurrence;
///        "End on date" end rule stops scheduling after the specified date.
@MainActor
struct RecurrenceTests {

    // MARK: - SC-R2: After-N end rule

    @Test("afterNStops: after-N end rule stops rescheduling after Nth occurrence — SC-R2")
    func afterNStops() throws {
        let spy = SpyCenter()
        let scheduler = NotificationScheduler(center: spy)

        let reminderID = UUID()
        let info = ReminderInfo(
            id: reminderID,
            title: "After-N Reminder",
            date: Date(timeIntervalSinceNow: 3600),
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .afterCount, occurrenceCount: 3),
            leadMinutes: []
        )

        // Before the count is reached — should produce requests
        let requestsBefore = try scheduler.buildRequests(for: info, occurrenceIndex: 0)
        #expect(!requestsBefore.isEmpty, "Should produce requests before N occurrences")

        // At index N-1 (last allowed) — should still produce requests
        let requestsAtLastOccurrence = try scheduler.buildRequests(for: info, occurrenceIndex: 2)
        #expect(!requestsAtLastOccurrence.isEmpty, "Should produce requests at last occurrence (index N-1)")

        // At index N (reached the count) — should produce no requests
        let requestsAtCount = try scheduler.buildRequests(for: info, occurrenceIndex: 3)
        #expect(requestsAtCount.isEmpty, "Should produce no requests after N occurrences (index == N)")

        // Beyond N — also empty
        let requestsBeyond = try scheduler.buildRequests(for: info, occurrenceIndex: 10)
        #expect(requestsBeyond.isEmpty, "Should produce no requests beyond N occurrences")
    }

    // MARK: - SC-R2: End-on-date end rule

    @Test("endOnDateStops: end-on-date end rule stops rescheduling after the cutoff date — SC-R2")
    func endOnDateStops() throws {
        let spy = SpyCenter()
        let scheduler = NotificationScheduler(center: spy)

        // End date is yesterday
        let yesterday = Date(timeIntervalSinceNow: -86400)
        let reminderID = UUID()

        // Fire date in the past — should be stopped by end-on-date rule
        let infoPast = ReminderInfo(
            id: reminderID,
            title: "Past Reminder",
            date: Date(timeIntervalSinceNow: -3600),   // 1 hour ago (before endDate is moot, but date > endDate checks)
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .onDate, endDate: yesterday),
            leadMinutes: []
        )

        // Fire date is today (2 hours from now) — date > yesterday → no requests
        let infoFuture = ReminderInfo(
            id: reminderID,
            title: "Future Reminder",
            date: Date(timeIntervalSinceNow: 7200),    // 2 hours from now (> endDate)
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .onDate, endDate: yesterday),
            leadMinutes: []
        )

        // date > endDate → should return no requests
        let requestsFuture = try scheduler.buildRequests(for: infoFuture)
        #expect(requestsFuture.isEmpty, "Should return no requests when fire date is past the end date")

        // Reminder with end date far in the future — should produce requests
        let infoActive = ReminderInfo(
            id: UUID(),
            title: "Active Reminder",
            date: Date(timeIntervalSinceNow: 3600),
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .onDate, endDate: Date(timeIntervalSinceNow: 86400 * 30)),
            leadMinutes: []
        )

        let requestsActive = try scheduler.buildRequests(for: infoActive)
        #expect(!requestsActive.isEmpty, "Should produce requests when fire date is before end date")
    }

    // MARK: - WR-02: After-N expands into discrete non-repeating triggers (production path)

    @Test("afterNExpandsToDiscreteTriggers: daily after-3 builds 3 non-repeating -occ triggers — WR-02/SC-R2")
    func afterNExpandsToDiscreteTriggers() throws {
        let scheduler = NotificationScheduler(center: SpyCenter())
        let reminderID = UUID()
        let info = ReminderInfo(
            id: reminderID,
            title: "Daily After-3",
            date: Date(timeIntervalSinceNow: 3600),
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .afterCount, occurrenceCount: 3),
            leadMinutes: []
        )

        let requests = try scheduler.buildRequests(for: info)

        // After-N must NOT be a single infinite repeating trigger — it expands to N discrete fires.
        #expect(requests.count == 3, "Expected 3 discrete occurrences, got \(requests.count)")
        for request in requests {
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            #expect(trigger?.repeats == false, "After-N occurrences must be non-repeating: \(request.identifier)")
        }
        let identifiers = Set(requests.map(\.identifier))
        #expect(identifiers == ["\(reminderID)-occ-0", "\(reminderID)-occ-1", "\(reminderID)-occ-2"],
                "After-N must use -occ-<n> identifiers, got \(identifiers)")
    }

    @Test("endOnDateExpandsBounded: daily end-on-date 6 days out builds a bounded set of dated triggers — WR-02/SC-R2")
    func endOnDateExpandsBounded() throws {
        let scheduler = NotificationScheduler(center: SpyCenter())
        let start = Date(timeIntervalSinceNow: 3600)
        let info = ReminderInfo(
            id: UUID(),
            title: "Daily Until",
            date: start,
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .onDate, endDate: start.addingTimeInterval(86_400 * 6)),
            leadMinutes: []
        )

        let requests = try scheduler.buildRequests(for: info)

        // Bounded: today + 6 days inclusive ≈ 7 fires; must be finite and non-repeating.
        #expect(requests.count >= 6 && requests.count <= 8,
                "Expected ~7 bounded occurrences, got \(requests.count)")
        for request in requests {
            #expect((request.trigger as? UNCalendarNotificationTrigger)?.repeats == false,
                    "End-on-date occurrences must be non-repeating: \(request.identifier)")
        }
    }

    // MARK: - WR-01: Monthly day-of-month clamped so a repeating trigger always fires

    @Test("monthlyClampsDayToSafeRange: day-31 monthly (never) clamps to day-28 — WR-01/D3-14")
    func monthlyClampsDayToSafeRange() throws {
        let scheduler = NotificationScheduler(center: SpyCenter())

        // Build a date on the 31st (Jan 31 fires in every-month context only if clamped).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 31; comps.hour = 10; comps.minute = 0
        let date = Calendar.current.date(from: comps)!

        let info = ReminderInfo(
            id: UUID(),
            title: "Monthly-31",
            date: date,
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .monthly),
            endRule: ReminderEndRule(type: .never),
            leadMinutes: []
        )

        let requests = try scheduler.buildRequests(for: info)
        #expect(requests.count == 1, "Unbounded monthly is a single repeating trigger")
        let trigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true, "Unbounded monthly must repeat")
        #expect(trigger?.dateComponents.day == NotificationScheduler.maxSafeMonthlyDay,
                "Day-31 monthly must clamp to \(NotificationScheduler.maxSafeMonthlyDay) so it fires every month")
    }

    // MARK: - WR-03: All-day repeating reminders fire at the agreed hour, not midnight

    @Test("allDayDailyFiresAtNine: all-day daily fires at 09:00 local, not midnight — WR-03")
    func allDayDailyFiresAtNine() throws {
        let scheduler = NotificationScheduler(center: SpyCenter())
        let info = ReminderInfo(
            id: UUID(),
            title: "All-day Daily",
            date: Date(timeIntervalSinceNow: 3600),
            isAllDay: true,
            recurrence: ReminderRecurrence(type: .daily),
            endRule: ReminderEndRule(type: .never),
            leadMinutes: []
        )

        let requests = try scheduler.buildRequests(for: info)
        let trigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == NotificationScheduler.allDayFireHour,
                "All-day daily must fire at \(NotificationScheduler.allDayFireHour):00, not midnight")
        #expect(trigger?.dateComponents.minute == 0, "All-day fire minute must be 0")
    }
}
