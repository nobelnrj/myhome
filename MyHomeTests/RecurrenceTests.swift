import Testing
import Foundation
@testable import MyHome

// Requirements: SC-R2 ("after N" stops, end-on-date stops, weekly weekdays)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/RecurrenceTests
// Wave 0 stub — tests FAIL via Issue.record until plan 03-03 (recurrence logic) ships.

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
        // After-N occurrence tracking does not exist until plan 03-03.
        Issue.record("not yet implemented — after-N recurrence tracking pending plan 03-03")
    }

    // MARK: - SC-R2: End-on-date end rule

    @Test("endOnDateStops: end-on-date end rule stops rescheduling after the cutoff date — SC-R2")
    func endOnDateStops() throws {
        // End-on-date logic does not exist until plan 03-03.
        Issue.record("not yet implemented — end-on-date recurrence logic pending plan 03-03")
    }
}
