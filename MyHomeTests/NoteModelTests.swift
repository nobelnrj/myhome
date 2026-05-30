import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-01 (Note with title + blocks persists), NOT-02 (block order preserved)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteModelTests
// Wave 0 stub — tests FAIL via Issue.record until plan 03-02 ships Note + NoteBlock models.

/// NoteModelTests — persistence and CloudKit-readiness tests for Note + NoteBlock.
///
/// NOT-01: A note with title + blocks persists and refetches with title intact.
/// NOT-02: Interleaved text + checkbox blocks persist, preserving the `order` field.
@MainActor
struct NoteModelTests {

    // MARK: - NOT-01: Note with title persists

    @Test("noteWithTitlePersists: create note with title, fetch, title intact — NOT-01")
    func noteWithTitlePersists() throws {
        // Note type does not exist until plan 03-02.
        Issue.record("not yet implemented — Note model pending plan 03-02")
    }

    // MARK: - NOT-02: Block list preserves order

    @Test("blockListPreservesOrder: interleaved text + checkbox blocks preserve order field — NOT-02")
    func blockListPreservesOrder() throws {
        // NoteBlock type does not exist until plan 03-02.
        Issue.record("not yet implemented — NoteBlock model pending plan 03-02")
    }

    // MARK: - CloudKit-readiness: Note @Model metadata

    @Test("Note @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func notePropertiesAreCloudKitReady() throws {
        // Note type does not exist until plan 03-02.
        Issue.record("not yet implemented — Note model pending plan 03-02")
    }

    // MARK: - CloudKit-readiness: NoteBlock @Model metadata

    @Test("NoteBlock @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func noteBlockPropertiesAreCloudKitReady() throws {
        // NoteBlock type does not exist until plan 03-02.
        Issue.record("not yet implemented — NoteBlock model pending plan 03-02")
    }
}
