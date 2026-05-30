import Testing
import UserNotifications
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyCenter — in-memory NotificationCenterPort test double.
//
// NotificationCenterPort is defined in MyHomeApp/Support/NotificationCenterPort.swift
// (production file, plan 03-03). This file provides the test double only.
//
// ReminderInfo is defined in MyHomeApp/Support/NotificationScheduler.swift (plan 03-03).
// ---------------------------------------------------------------------------

/// In-memory spy that records all `add` and `removePendingNotificationRequests`
/// calls so unit tests can assert on scheduler output without touching the OS.
public final class SpyCenter: NotificationCenterPort, @unchecked Sendable {

    // MARK: - Settable stubs

    /// Controls the return value of requestAuthorization.
    public var authorizationResult: Bool = true

    // MARK: - Recorded calls

    /// All requests passed to add(_:), in call order.
    public private(set) var addedRequests: [UNNotificationRequest] = []

    /// All identifier arrays passed to removePendingNotificationRequests, in call order.
    public private(set) var removedIdentifierSets: [[String]] = []

    public init() {}

    // MARK: - Computed inspection helpers

    /// Flat list of all request identifiers that were added.
    public var addedIdentifiers: [String] {
        addedRequests.map(\.identifier)
    }

    /// Flat list of all identifiers removed across all remove calls.
    public var removedIdentifiers: [String] {
        removedIdentifierSets.flatMap { $0 }
    }

    // MARK: - NotificationCenterPort

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationResult
    }

    public func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    public func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        removedIdentifierSets.append(ids)
        addedRequests.removeAll { ids.contains($0.identifier) }
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        addedRequests
    }

    // MARK: - Reset

    /// Clears all recorded state (useful between tests if the same SpyCenter instance is reused).
    public func reset() {
        addedRequests = []
        removedIdentifierSets = []
    }
}

// ---------------------------------------------------------------------------
// Fixture builders — convenience helpers for scheduler tests (plan 03-03).
// ---------------------------------------------------------------------------

/// Returns a timed ReminderInfo firing with the given lead offsets.
public func timedReminder(
    leadMinutes: [Int] = [],
    date: Date = Date(timeIntervalSinceNow: 3600)
) -> ReminderInfo {
    ReminderInfo(
        title: "Test Reminder",
        date: date,
        isAllDay: false,
        recurrence: ReminderRecurrence(type: .none),
        endRule: ReminderEndRule(type: .never),
        leadMinutes: leadMinutes
    )
}

/// Returns a weekly ReminderInfo with the specified weekdays (1=Sun..7=Sat).
public func weeklyReminder(weekdays: [Int]) -> ReminderInfo {
    ReminderInfo(
        title: "Weekly Reminder",
        date: Date(timeIntervalSinceNow: 3600),
        isAllDay: false,
        recurrence: ReminderRecurrence(type: .weekly, weekdays: weekdays),
        endRule: ReminderEndRule(type: .never),
        leadMinutes: []
    )
}
