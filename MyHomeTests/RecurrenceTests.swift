import Testing
import Foundation
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
}
