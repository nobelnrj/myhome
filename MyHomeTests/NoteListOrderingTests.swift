import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-03 (section ordering), NOT-04 (pin moves to Pinned section), SC-R5 (Daily Routine)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteListOrderingTests
// Wave 0 stub — tests FAIL via Issue.record until plans 03-02 (model) + 03-04 (ordering logic) ship.

/// NoteListOrderingTests — section ordering and pin logic for the Notes list.
///
/// NOT-03: List ordering = Daily Routine → Pinned → Other (most-recent-first).
/// NOT-04: Toggling isPinned moves a note into/out of the Pinned section.
/// SC-R5:  Daily-recurring notes appear in the Daily Routine section (D3-08).
@MainActor
struct NoteListOrderingTests {

    // MARK: - NOT-03: Section ordering

    @Test("sectionOrdering: Daily Routine → Pinned → Other ordering correct — NOT-03")
    func sectionOrdering() throws {
        // Note + ordering logic does not exist until plans 03-02 / 03-04.
        Issue.record("not yet implemented — Note model + ordering logic pending plans 03-02/03-04")
    }

    // MARK: - NOT-04: Pin moves to Pinned section

    @Test("pinMovesToPinnedSection: toggling isPinned moves note into Pinned section — NOT-04")
    func pinMovesToPinnedSection() throws {
        // Note.isPinned does not exist until plan 03-02.
        Issue.record("not yet implemented — Note model pending plan 03-02")
    }

    // MARK: - SC-R5: Daily Routine auto-section

    @Test("dailyRoutineFilter: daily-recurring notes appear in Daily Routine section — SC-R5")
    func dailyRoutineFilter() throws {
        // Daily Routine filter logic does not exist until plan 03-04.
        Issue.record("not yet implemented — Daily Routine filter pending plan 03-04")
    }
}
