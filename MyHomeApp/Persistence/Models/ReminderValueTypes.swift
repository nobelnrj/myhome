import Foundation

// MARK: - RecurrenceType

/// Recurrence frequency for a reminder.
///
/// Stored as `String` raw value via `ReminderRecurrence.type` — NOT stored directly in SwiftData
/// (no stored enums, CloudKit rule 5 / Pitfall 6). Serialized to `Data?` on `Note` and `NoteBlock`.
///
/// Weekly allows multiple weekdays (one repeating trigger per day — D3-10, D3-15).
enum RecurrenceType: String, Codable {
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
struct ReminderRecurrence: Codable, Equatable {
    var type: RecurrenceType = .none
    /// Selected weekdays (1=Sun..7=Sat) when type == .weekly; nil / empty otherwise.
    var weekdays: [Int]? = nil
}

// MARK: - EndRuleType

/// Determines when a recurring reminder stops firing.
///
/// `afterCount` requires app-side occurrence tracking (native repeating triggers do not self-stop — D3-11).
enum EndRuleType: String, Codable {
    case never
    case onDate
    case afterCount
}

// MARK: - ReminderEndRule

/// Codable value type encoding the end rule for a recurring reminder.
///
/// Only `endDate` is meaningful when `type == .onDate`; only `occurrenceCount` when `type == .afterCount`.
/// Serialized to `Data?` via `JSONEncoder` / `JSONDecoder` (no stored enum — rule 5).
struct ReminderEndRule: Codable, Equatable {
    var type: EndRuleType = .never
    /// UTC date on which recurrence stops (inclusive) — meaningful only when `type == .onDate`.
    var endDate: Date? = nil
    /// Number of occurrences after which recurrence stops — meaningful only when `type == .afterCount`.
    var occurrenceCount: Int? = nil
}
