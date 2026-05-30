import Foundation

// MARK: - RecurrenceType

/// Recurrence frequency for a reminder.
///
/// Stored as `String` raw value via `ReminderRecurrence.type` — NOT stored directly in SwiftData
/// (no stored enums, CloudKit rule 5 / Pitfall 6). Serialized to `Data?` on `Note` and `NoteBlock`.
///
/// Weekly allows multiple weekdays (one repeating trigger per day — D3-10, D3-15).
public enum RecurrenceType: String, Codable, Sendable {
    case none
    case daily
    case weekly
    case monthly
    case yearly
}

// MARK: - ReminderRecurrence

/// Codable value type encoding recurrence frequency + weekly day selection.
///
/// Only `weekdays` is meaningful when `type == .weekly`; ignored otherwise.
/// Weekday convention: 1 = Sunday, 7 = Saturday (Calendar component convention — D3-10).
/// Serialized to `Data?` via `JSONEncoder` / `JSONDecoder` (no SwiftData stored enum — rule 5).
public struct ReminderRecurrence: Codable, Equatable, Sendable {
    public var type: RecurrenceType = .none
    /// Selected weekdays (1=Sun..7=Sat) when type == .weekly; nil / empty otherwise.
    public var weekdays: [Int]? = nil

    public init(type: RecurrenceType = .none, weekdays: [Int]? = nil) {
        self.type = type
        self.weekdays = weekdays
    }
}

// MARK: - EndRuleType

/// Determines when a recurring reminder stops firing.
///
/// `afterCount` requires app-side occurrence tracking (native repeating triggers do not self-stop — D3-11).
public enum EndRuleType: String, Codable, Sendable {
    case never
    case onDate
    case afterCount
}

// MARK: - ReminderEndRule

/// Codable value type encoding the end rule for a recurring reminder.
///
/// Only `endDate` is meaningful when `type == .onDate`; only `occurrenceCount` when `type == .afterCount`.
/// Serialized to `Data?` via `JSONEncoder` / `JSONDecoder` (no stored enum — rule 5).
public struct ReminderEndRule: Codable, Equatable, Sendable {
    public var type: EndRuleType = .never
    /// UTC date on which recurrence stops (inclusive) — meaningful only when `type == .onDate`.
    public var endDate: Date? = nil
    /// Number of occurrences after which recurrence stops — meaningful only when `type == .afterCount`.
    public var occurrenceCount: Int? = nil

    public init(type: EndRuleType = .never, endDate: Date? = nil, occurrenceCount: Int? = nil) {
        self.type = type
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
    }
}
