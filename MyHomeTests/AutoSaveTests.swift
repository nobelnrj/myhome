import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-05 (debounced auto-save commits ~500ms after last edit; no save button)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/AutoSaveTests

/// AutoSaveTests — debounce unit test for auto-save behavior on the note editor.
///
/// NOT-05: Debounced auto-save commits ~500ms after last edit; no save button;
///         reopen shows edits persisted.
///
/// Tests the isolated `Debouncer` helper directly (not the view) so this test is
/// headless and fast. `Debouncer` lives in `EditNoteView.swift` and is accessible
/// via `@testable import MyHome`.
@MainActor
struct AutoSaveTests {

    // MARK: - NOT-05: Debounce commits after quiet period

    @Test("debounceCommitsAfterQuiet: save fires ~500ms after last keystroke, not before — NOT-05")
    func debounceCommitsAfterQuiet() async throws {
        // Arrange — short delay so test runs fast; still exercises the real debounce logic
        let delay: TimeInterval = 0.1
        let debouncer = Debouncer(delay: delay)

        var saveCount = 0

        // Act — schedule multiple rapid edits; only the last one's trailing callback should fire
        debouncer.schedule { saveCount += 1 }
        debouncer.schedule { saveCount += 1 }  // cancels the first
        debouncer.schedule { saveCount += 1 }  // cancels the second

        // Wait for less than the debounce delay — save must NOT have fired yet
        try await Task.sleep(nanoseconds: UInt64(delay * 0.4 * 1_000_000_000))
        #expect(saveCount == 0, "save must not fire before quiet period elapses")

        // Wait past the debounce delay — exactly one save must fire
        try await Task.sleep(nanoseconds: UInt64(delay * 1.5 * 1_000_000_000))
        #expect(saveCount == 1, "exactly one save fires after quiet period — rapid edits coalesced")
    }

    // MARK: - Debounce cancel

    @Test("debounceCancel: cancelled debouncer never fires — NOT-05")
    func debounceCancel() async throws {
        let delay: TimeInterval = 0.1
        let debouncer = Debouncer(delay: delay)

        var saveCount = 0
        debouncer.schedule { saveCount += 1 }

        // Cancel immediately before the delay elapses
        debouncer.cancel()

        // Wait past the delay — save must NOT fire after cancel
        try await Task.sleep(nanoseconds: UInt64(delay * 2 * 1_000_000_000))
        #expect(saveCount == 0, "cancelled debouncer must never fire")
    }
}
