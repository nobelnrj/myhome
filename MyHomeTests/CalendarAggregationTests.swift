import Testing
import Foundation
@testable import MyHome

// Requirements: SC-R4(a) (per-day reminder counts correct), SC-R4(b) (completion math correct)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/CalendarAggregationTests
// Wave 0 stub — tests FAIL via Issue.record until plan 03-04 (calendar aggregation helper) ships.

/// CalendarAggregationTests — pure-logic tests for per-day reminder aggregation
/// and completion progress math in the Calendar view.
///
/// SC-R4(a): Per-day reminder counts are computed correctly from reminder records.
/// SC-R4(b): Tapped-day agenda completion progress (e.g. 2/5) is computed correctly.
@MainActor
struct CalendarAggregationTests {

    // MARK: - SC-R4(a,b): Per-day counts and completion progress

    @Test("perDayCountsAndProgress: per-day counts and x/y completion math correct — SC-R4(a,b)")
    func perDayCountsAndProgress() throws {
        // Calendar aggregation helper does not exist until plan 03-04.
        Issue.record("not yet implemented — calendar aggregation helper pending plan 03-04")
    }
}
