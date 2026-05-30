import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-06 (search predicate matches title + block text)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteSearchTests
// Wave 0 stub — tests FAIL via Issue.record until plans 03-02 (model) + 03-04 (filter logic) ship.

/// NoteSearchTests — search predicate coverage for Note title + NoteBlock text.
///
/// NOT-06: The search predicate matches note title and all block text; non-matches are excluded.
@MainActor
struct NoteSearchTests {

    // MARK: - NOT-06: Search predicate

    @Test("matchesTitleAndBlockText: predicate matches title and block text; non-matches excluded — NOT-06")
    func matchesTitleAndBlockText() throws {
        // Note + NoteBlock + search filter logic does not exist until plans 03-02/03-04.
        Issue.record("not yet implemented — Note model + search filter pending plans 03-02/03-04")
    }
}
