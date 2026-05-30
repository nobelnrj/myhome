import Testing
import UserNotifications
@testable import MyHome

// ---------------------------------------------------------------------------
// NotificationCenterPort — protocol seam for testable notification scheduling.
// Production conformer (plan 03-06): wraps UNUserNotificationCenter.current().
// Test conformer: SpyCenter below.
// ---------------------------------------------------------------------------

/// Protocol that abstracts the four UNUserNotificationCenter operations required
/// by NotificationScheduler. Injecting this protocol lets unit tests run without
/// touching the OS notification center.
public protocol NotificationCenterPort: Sendable {
    /// Requests user authorization for the given options.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    /// Adds a notification request to the center.
    func add(_ request: UNNotificationRequest) async throws
    /// Removes pending requests by identifier.
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    /// Returns all currently pending notification requests.
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

// ---------------------------------------------------------------------------
// ReminderInfo — placeholder value type consumed by NotificationScheduler.
// Plan 03-03 will move/replace this with the final Codable value types
// (ReminderRecurrence + ReminderEndRule) once the scheduler is implemented.
// ---------------------------------------------------------------------------

/// Input type for NotificationScheduler.buildRequests(for:).
/// Mirrors the reminder fields embedded on Note/NoteBlock (RESEARCH §Data Model Design).
public struct ReminderInfo: Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var isAllDay: Bool
    /// Lead-time advance alerts, expressed as minutes before the main reminder.
    public var leadMinutes: [Int]
    /// Encoded recurrence. nil = no recurrence (RecurrenceType.none).
    public var recurrenceData: Data?
    /// Encoded end rule. nil = never (EndRuleType.never).
    public var endRuleData: Data?

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        isAllDay: Bool = false,
        leadMinutes: [Int] = [],
        recurrenceData: Data? = nil,
        endRuleData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.leadMinutes = leadMinutes
        self.recurrenceData = recurrenceData
        self.endRuleData = endRuleData
    }
}

// ---------------------------------------------------------------------------
// SpyCenter — in-memory NotificationCenterPort test double.
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
// Fixture builders — convenience helpers for test stubs.
// Plan 03-03 will expand these with full recurrence/end-rule support.
// ---------------------------------------------------------------------------

/// Returns a timed ReminderInfo firing `leadMinutes` before a reference date.
public func timedReminder(
    leadMinutes: [Int] = [],
    date: Date = Date(timeIntervalSinceNow: 3600)
) -> ReminderInfo {
    ReminderInfo(
        title: "Test Reminder",
        date: date,
        isAllDay: false,
        leadMinutes: leadMinutes
    )
}

/// Returns a weekly ReminderInfo with a weekday set (1=Sun..7=Sat).
public func weeklyReminder(weekdays: [Int]) -> ReminderInfo {
    // Recurrence data will be properly encoded in plan 03-03.
    // For now, provide a bare info so stubs compile.
    ReminderInfo(
        title: "Weekly Reminder",
        date: Date(timeIntervalSinceNow: 3600),
        isAllDay: false,
        leadMinutes: []
    )
}
