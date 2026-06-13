import Testing
@testable import MyHome
import UserNotifications

/// Unit tests for RoutineNotificationService (NOTE-03, D-05, Phase 12).
///
/// Uses SpyCenter (MyHomeTests/Support/SpyCenter.swift) injected into the service.
/// SpyCenter's removePendingNotificationRequests removes from addedRequests, so
/// addedRequests == current pending set after each operation.
@MainActor
struct RoutineNotificationServiceTests {

    private func makeSpy() -> SpyCenter { SpyCenter() }

    /// Helper: a fixed Date for the daily reminder time (7:00 AM).
    private func time7am() -> Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    }

    /// Helper: a fixed Date for the daily reminder time (8:30 AM).
    private func time830am() -> Date {
        Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!
    }

    // MARK: - Identifier

    @Test("identifier(for:) returns the stable 'routine-daily-' prefixed string")
    func identifierHasCorrectPrefix() {
        let id = UUID()
        let result = RoutineNotificationService.identifier(for: id)
        #expect(result == "routine-daily-\(id.uuidString)", "Stable identifier must be 'routine-daily-{uuidString}'")
    }

    // MARK: - D-05: Cancel-then-add ordering

    @Test("D-05: re-scheduling cancels prior request before adding new one")
    func rescheduleIsAtomicCancelThenAdd() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        // Schedule once
        await service.schedule(noteID: noteID, title: "Morning Run", time: time7am())

        // Assert cancel was called before add on the first schedule
        // (cancel is always called first — even on a fresh note with no pending request)
        #expect(spy.removedIdentifierSets.count == 1, "cancel must be called once before the first add")
        #expect(spy.removedIdentifierSets[0].contains(RoutineNotificationService.identifier(for: noteID)),
                "Removed identifier set must contain this note's stable identifier")
        #expect(spy.addedRequests.count == 1, "Exactly one request must be pending after first schedule")

        // Schedule again (re-schedule) — should cancel the previous and add a new one
        await service.schedule(noteID: noteID, title: "Morning Run", time: time830am())

        #expect(spy.removedIdentifierSets.count == 2, "cancel must be called again on re-schedule")
        #expect(spy.addedRequests.count == 1, "D-05: after re-schedule, still exactly 1 pending request")
    }

    // MARK: - D-05: Single-pending guarantee

    @Test("D-05: exactly one pending request per routine note after multiple schedules")
    func exactlyOnePendingRequest() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        // Schedule the same note three times with different times
        await service.schedule(noteID: noteID, title: "Morning Run", time: time7am())
        await service.schedule(noteID: noteID, title: "Morning Run", time: time830am())
        await service.schedule(noteID: noteID, title: "Morning Run Updated", time: time7am())

        let expectedID = RoutineNotificationService.identifier(for: noteID)
        let pendingForThisNote = spy.addedRequests.filter { $0.identifier == expectedID }
        #expect(pendingForThisNote.count == 1,
                "D-05: after 3 schedules, exactly 1 pending request must exist for this note (no stacking)")
        #expect(spy.removedIdentifierSets.count == 3,
                "cancel must have been called 3 times (once per schedule call)")
    }

    // MARK: - Cancel

    @Test("cancel removes pending request for that noteID")
    func cancelRemovesPendingRequest() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        // Schedule first
        await service.schedule(noteID: noteID, title: "Morning Run", time: time7am())
        #expect(spy.addedRequests.count == 1, "Request must be pending before cancel")

        // Cancel
        service.cancel(noteID: noteID)

        let expectedID = RoutineNotificationService.identifier(for: noteID)
        let pendingForThisNote = spy.addedRequests.filter { $0.identifier == expectedID }
        #expect(pendingForThisNote.isEmpty, "After cancel, no pending request must remain for this note")
    }

    // MARK: - Cancel does not affect other notes

    @Test("cancel for one noteID does not remove requests for another noteID")
    func cancelIsNoteSpecific() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID1 = UUID()
        let noteID2 = UUID()

        await service.schedule(noteID: noteID1, title: "Note 1", time: time7am())
        await service.schedule(noteID: noteID2, title: "Note 2", time: time7am())
        #expect(spy.addedRequests.count == 2, "Both notes should be pending")

        // Cancel only noteID1
        service.cancel(noteID: noteID1)

        let pending2 = spy.addedRequests.filter {
            $0.identifier == RoutineNotificationService.identifier(for: noteID2)
        }
        #expect(pending2.count == 1, "Cancelling note1 must not affect note2's pending request")
    }

    // MARK: - Content / userInfo security (T-12-05)

    @Test("userInfo contains exactly noteID and isRoutineReminder keys — no note body text")
    func userInfoHasExactlyNoteIDAndRoutineFlag() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        await service.schedule(noteID: noteID, title: "Morning Routine", time: time7am())

        guard let request = spy.addedRequests.first else {
            Issue.record("No request was added")
            return
        }
        let userInfo = request.content.userInfo as? [String: String] ?? [:]
        #expect(userInfo.keys.count == 2, "T-12-05: userInfo must have exactly 2 keys (noteID + isRoutineReminder)")
        #expect(userInfo["noteID"] == noteID.uuidString, "noteID must be the UUID string of the note")
        #expect(userInfo["isRoutineReminder"] == "true", "isRoutineReminder must be 'true'")
    }

    // MARK: - Category identifier

    @Test("content.categoryIdentifier equals kReminderCategoryID so the Complete action is available")
    func categoryIdentifierIsReminder() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        await service.schedule(noteID: noteID, title: "Morning Routine", time: time7am())

        guard let request = spy.addedRequests.first else {
            Issue.record("No request was added")
            return
        }
        #expect(request.content.categoryIdentifier == kReminderCategoryID,
                "categoryIdentifier must be kReminderCategoryID so the Complete action surfaces on the banner")
    }

    // MARK: - Trigger type

    @Test("trigger is UNCalendarNotificationTrigger with repeats: true")
    func triggerIsCalendarRepeating() async {
        let spy = makeSpy()
        let service = RoutineNotificationService(center: spy)
        let noteID = UUID()

        await service.schedule(noteID: noteID, title: "Morning Routine", time: time7am())

        guard let request = spy.addedRequests.first else {
            Issue.record("No request was added")
            return
        }
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            Issue.record("Trigger must be UNCalendarNotificationTrigger")
            return
        }
        #expect(trigger.repeats == true, "Trigger must repeat daily (repeats: true)")
    }
}
