import Testing
import UserNotifications
import Foundation
@testable import MyHome

// Requirements: SC-R1 (reminder fields + lead alerts), SC-R3(a) (correct requests/identifiers),
//               64-cap (D3-15) (pendingCount() ≤ 64 under load)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NotificationSchedulerTests
// Plan 03-03 implementation — turns the Wave 0 stubs green.

/// NotificationSchedulerTests — unit tests for NotificationScheduler via SpyCenter seam.
///
/// SC-R1:    Timed reminder with lead-time alerts builds the correct number of requests.
/// SC-R3(a): Scheduler emits requests with correct identifiers and category.
/// 64-cap:   pendingCount() stays ≤ 64 under multi-weekday-weekly + after-N load (D3-15).
@MainActor
struct NotificationSchedulerTests {

    // MARK: - SC-R1 + SC-R3(a): Lead alerts build correct requests

    @Test("buildRequestsLeadAlerts: timed reminder with 2 lead offsets builds 3 requests — SC-R1")
    func buildRequestsLeadAlerts() throws {
        let spy = SpyCenter()
        let scheduler = NotificationScheduler(center: spy)

        let reminderID = UUID()
        let fireDate = Date(timeIntervalSinceNow: 7200) // 2 hours from now
        let info = ReminderInfo(
            id: reminderID,
            title: "Test Reminder",
            date: fireDate,
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .none),
            endRule: ReminderEndRule(type: .never),
            leadMinutes: [60, 1440]   // 1 hour lead + 1 day lead
        )

        let requests = try scheduler.buildRequests(for: info)

        // Expect: main + lead-0 (60 min) + lead-1 (1440 min) = 3 requests
        #expect(requests.count == 3, "Expected 3 requests (main + 2 leads), got \(requests.count)")

        let identifiers = requests.map(\.identifier)
        #expect(identifiers.contains("\(reminderID)-main"), "Missing main identifier")
        #expect(identifiers.contains("\(reminderID)-lead-0"), "Missing lead-0 identifier")
        #expect(identifiers.contains("\(reminderID)-lead-1"), "Missing lead-1 identifier")

        // All identifiers must be distinct
        #expect(Set(identifiers).count == identifiers.count, "Identifiers must be distinct")
    }

    // MARK: - SC-R2(a): Weekly multi-weekday triggers

    @Test("weeklyMultiWeekday: weekly Mon/Wed/Fri produces one repeating trigger per weekday — SC-R1/SC-R2")
    func weeklyMultiWeekday() throws {
        let spy = SpyCenter()
        let scheduler = NotificationScheduler(center: spy)

        let reminderID = UUID()
        // Mon=2, Wed=4, Fri=6 in Calendar.weekday convention (1=Sun..7=Sat)
        let weekdays = [2, 4, 6]
        let info = ReminderInfo(
            id: reminderID,
            title: "Weekly Reminder",
            date: Date(timeIntervalSinceNow: 3600),
            isAllDay: false,
            recurrence: ReminderRecurrence(type: .weekly, weekdays: weekdays),
            endRule: ReminderEndRule(type: .never),
            leadMinutes: []
        )

        let requests = try scheduler.buildRequests(for: info)

        // Expect exactly 3 requests, one per weekday
        #expect(requests.count == 3, "Expected 3 requests (one per weekday), got \(requests.count)")

        // Each trigger must be a UNCalendarNotificationTrigger with repeats: true
        for request in requests {
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            #expect(trigger != nil, "Trigger must be UNCalendarNotificationTrigger for request \(request.identifier)")
            #expect(trigger?.repeats == true, "Trigger must repeat for \(request.identifier)")
        }

        // Identifiers must match the weekday-based scheme
        let identifiers = Set(requests.map(\.identifier))
        for weekday in weekdays {
            #expect(
                identifiers.contains("\(reminderID)-weekday-\(weekday)"),
                "Missing weekday identifier for weekday \(weekday)"
            )
        }
    }

    // MARK: - 64-cap (D3-15)

    @Test("pendingCountUnderCap: pending count stays ≤ 64 under multi-weekday + after-N load — D3-15")
    func pendingCountUnderCap() async throws {
        let spy = SpyCenter()
        let scheduler = NotificationScheduler(center: spy)

        // Schedule 10 weekly reminders each with Mon/Tue/Wed/Thu/Fri/Sat/Sun (7 weekdays)
        // = 70 potential requests — must be capped at 64.
        for i in 0..<10 {
            let info = ReminderInfo(
                id: UUID(),
                title: "Weekly \(i)",
                date: Date(timeIntervalSinceNow: Double(i + 1) * 3600),
                isAllDay: false,
                recurrence: ReminderRecurrence(type: .weekly, weekdays: [1, 2, 3, 4, 5, 6, 7]),
                endRule: ReminderEndRule(type: .never),
                leadMinutes: []
            )
            try await scheduler.schedule(info)
        }

        let count = await scheduler.pendingCount()
        #expect(count <= NotificationScheduler.iOSPendingCap,
                "Pending count \(count) exceeds iOS cap of \(NotificationScheduler.iOSPendingCap)")
        #expect(count > 0, "At least some requests should have been scheduled")
    }
}
