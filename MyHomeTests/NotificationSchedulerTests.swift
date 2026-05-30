import Testing
import UserNotifications
import Foundation
@testable import MyHome

// Requirements: SC-R1 (reminder fields + lead alerts), SC-R3(a) (correct requests/identifiers),
//               64-cap (D3-15) (pendingCount() ≤ 64 under load)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NotificationSchedulerTests
// Wave 0 stub — tests FAIL via Issue.record until plan 03-03 (NotificationScheduler) ships.
// This suite uses SpyCenter (MyHomeTests/Support/SpyCenter.swift) as the NotificationCenterPort
// test double: NotificationScheduler(center: SpyCenter()).

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
        // NotificationScheduler.buildRequests does not exist until plan 03-03.
        Issue.record("not yet implemented — NotificationScheduler pending plan 03-03")
    }

    // MARK: - SC-R2(a): Weekly multi-weekday triggers

    @Test("weeklyMultiWeekday: weekly Mon/Wed/Fri produces one repeating trigger per weekday — SC-R1/SC-R2")
    func weeklyMultiWeekday() throws {
        // Recurrence handling does not exist until plan 03-03.
        Issue.record("not yet implemented — recurrence logic pending plan 03-03")
    }

    // MARK: - 64-cap (D3-15)

    @Test("pendingCountUnderCap: pending count stays ≤ 64 under multi-weekday + after-N load — D3-15")
    func pendingCountUnderCap() async throws {
        // 64-cap budgeting does not exist until plan 03-03.
        Issue.record("not yet implemented — 64-cap budgeting pending plan 03-03")
    }
}
