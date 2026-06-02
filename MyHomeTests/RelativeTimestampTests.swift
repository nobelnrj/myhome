import Testing
import Foundation
@testable import MyHome

// Requirements: ING-05 (always-visible last-synced timestamp), SET-05 (relative display format)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/RelativeTimestampTests
// Plan 06-01 — RED phase: tests compile but FAIL RED because Date.relativeToNow
// does not exist until plan 02 adds the extension.

/// RelativeTimestampTests — unit tests for the `Date.relativeToNow` helper.
///
/// ING-05: "Last synced at …" timestamp always visible in Settings.
/// SET-05: Display format = "Last synced 2 hours ago" (relative).
///
/// D6-16: RelativeDateTimeFormatter with unitsStyle = .full produces "X hours ago" natively.
///
/// These tests FAIL RED until plan 02 adds `extension Date { var relativeToNow: String }`.
struct RelativeTimestampTests {

    // MARK: - ING-05 / SET-05: Date 2 hours in the past contains "hour"

    @Test("twoHoursAgoContainsHour: a date 2 hours in the past produces a string containing 'hour' — ING-05, SET-05")
    func twoHoursAgoContainsHour() {
        let twoHoursAgo = Date(timeIntervalSinceNow: -7200) // -7200 seconds = -2 hours
        let relative = twoHoursAgo.relativeToNow
        #expect(relative.lowercased().contains("hour"),
                "relativeToNow for a date 2 hours ago must contain 'hour' — ING-05, SET-05 (D6-16)")
    }

    // MARK: - SET-05: Date 1 minute ago contains "minute"

    @Test("oneMinuteAgoContainsMinute: a date 1 minute in the past produces a string containing 'minute' — SET-05")
    func oneMinuteAgoContainsMinute() {
        let oneMinuteAgo = Date(timeIntervalSinceNow: -60)
        let relative = oneMinuteAgo.relativeToNow
        #expect(relative.lowercased().contains("minute") || relative.lowercased().contains("ago") || relative.lowercased().contains("just now"),
                "relativeToNow for a date 1 minute ago must produce a human-readable relative string — SET-05")
    }

    // MARK: - SET-05: Result is non-empty

    @Test("relativeToNowIsNonEmpty: relativeToNow is non-empty for any date — SET-05")
    func relativeToNowIsNonEmpty() {
        let someDate = Date(timeIntervalSinceNow: -3600)
        #expect(!someDate.relativeToNow.isEmpty, "relativeToNow must always return a non-empty string — SET-05")
    }
}
