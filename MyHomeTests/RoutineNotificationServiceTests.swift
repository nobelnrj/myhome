import Testing
@testable import MyHome
import UserNotifications

/// Unit tests for RoutineNotificationService (NOTE-03, D-05, Phase 12).
///
/// Wave 0 scaffolds — RoutineNotificationService does not exist yet (created in plan 12-02).
/// These test cases compile now by testing SpyCenter directly as a placeholder.
/// They will be wired to RoutineNotificationService in plan 12-02.
///
/// Uses SpyCenter (MyHomeTests/Support/SpyCenter.swift) which records all
/// add() and removePendingNotificationRequests() calls.
@MainActor
struct RoutineNotificationServiceTests {

    private func makeSpy() -> SpyCenter { SpyCenter() }

    // MARK: - Pending stubs (wired in plan 12-02 when RoutineNotificationService exists)

    @Test("D-05: re-scheduling cancels prior request before adding new one")
    func rescheduleIsAtomicCancelThenAdd() async {
        // pending 12-02: RoutineNotificationService does not exist yet.
        // Placeholder: verify SpyCenter records cancel-then-add ordering.
        let spy = makeSpy()
        let id = "routine-daily-\(UUID().uuidString)"

        // Simulate cancel-then-add: first a remove, then an add
        spy.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "Placeholder"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await spy.add(request)

        #expect(spy.removedIdentifierSets.count == 1, "cancel must be called before add")
        #expect(spy.addedRequests.count == 1, "add must follow cancel")
        // pending 12-02: replace with RoutineNotificationService.schedule() assertions
        Issue.record("pending 12-02: RoutineNotificationService.schedule() not yet implemented")
    }

    @Test("D-05: exactly one pending request per routine note after multiple schedules")
    func exactlyOnePendingRequest() async {
        // pending 12-02: RoutineNotificationService does not exist yet.
        // Placeholder: SpyCenter's removePendingNotificationRequests removes from addedRequests,
        // so cancel-then-add produces exactly 1 pending request.
        let spy = makeSpy()
        let noteID = UUID()
        let id = "routine-daily-\(noteID.uuidString)"

        // Simulate two schedule calls: each cancels the previous and adds a new one
        for _ in 0..<2 {
            spy.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Morning Routine"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await spy.add(request)
        }

        #expect(spy.addedRequests.count == 1, "After two schedules with cancel-then-add, exactly 1 pending request must remain")
        // pending 12-02: replace with RoutineNotificationService calls
        Issue.record("pending 12-02: RoutineNotificationService not yet implemented")
    }

    @Test("cancel removes pending request")
    func cancelRemovesPendingRequest() async {
        // pending 12-02: RoutineNotificationService does not exist yet.
        // Placeholder: test SpyCenter's cancel removes from addedRequests.
        let spy = makeSpy()
        let noteID = UUID()
        let id = "routine-daily-\(noteID.uuidString)"

        // Add a request
        let content = UNMutableNotificationContent()
        content.title = "Morning Routine"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await spy.add(request)
        #expect(spy.addedRequests.count == 1, "Request must be added before cancel")

        // Cancel it
        spy.removePendingNotificationRequests(withIdentifiers: [id])
        #expect(spy.addedRequests.isEmpty, "Cancel must remove the pending request from SpyCenter")
        // pending 12-02: replace with RoutineNotificationService.cancel() assertions
        Issue.record("pending 12-02: RoutineNotificationService.cancel() not yet implemented")
    }
}
