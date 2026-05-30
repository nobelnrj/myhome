import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-01 (Note with title + blocks persists), NOT-02 (block order preserved)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteModelTests
// Implemented in plan 03-02 — NoteModelTests turns GREEN here.

/// NoteModelTests — persistence and CloudKit-readiness tests for Note + NoteBlock.
///
/// NOT-01: A note with title + blocks persists and refetches with title intact.
/// NOT-02: Interleaved text + checkbox blocks persist, preserving the `order` field.
@MainActor
struct NoteModelTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Note.self, NoteBlock.self,
            configurations: config
        )
    }

    // MARK: - NOT-01: Note with title persists

    @Test("noteWithTitlePersists: create note with title, fetch, title intact — NOT-01")
    func noteWithTitlePersists() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let note = Note(title: "X")
        context.insert(note)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1, "One note must be stored")
        #expect(fetched.first?.title == "X", "Title must round-trip through persistence")
    }

    // MARK: - NOT-02: Block list preserves order

    @Test("blockListPreservesOrder: interleaved text + checkbox blocks preserve order field — NOT-02")
    func blockListPreservesOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert a note with two interleaved blocks: text (order 0) + checkbox (order 1).
        let note = Note(title: "List")
        context.insert(note)

        let blockText = NoteBlock(kindRaw: "text", text: "paragraph", order: 0)
        let blockCheck = NoteBlock(kindRaw: "checkbox", text: "task", order: 1)
        context.insert(blockText)
        context.insert(blockCheck)
        blockText.note = note
        blockCheck.note = note

        try context.save()

        // Refetch blocks sorted by order.
        // Note: #Predicate on optional-chained UUID comparison (?.id) can fail to type-check
        // in SwiftData — fetch all and filter in-memory (valid since this is an in-memory test
        // container with only our two blocks).
        let descriptor = FetchDescriptor<NoteBlock>(sortBy: [SortDescriptor(\.order)])
        let blocks = try context.fetch(descriptor)

        #expect(blocks.count == 2, "Both blocks must persist")
        #expect(blocks[0].kindRaw == "text", "First block must be text (order 0)")
        #expect(blocks[1].kindRaw == "checkbox", "Second block must be checkbox (order 1)")
    }

    // MARK: - CloudKit-readiness: Note @Model metadata

    @Test("Note @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func notePropertiesAreCloudKitReady() throws {
        let container = try ModelContainer(
            for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let entity = try #require(
            container.schema.entities.first { $0.name == "Note" },
            "Note entity must be present in the schema"
        )

        #expect(!entity.attributes.isEmpty, "Note must declare stored attributes")
        for attribute in entity.attributes {
            let isOptional = attribute.isOptional
            let hasDefault = attribute.defaultValue != nil
            #expect(
                isOptional || hasDefault,
                "Attribute '\(attribute.name)' must be optional or have a default value for CloudKit readiness"
            )
        }

        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints.
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "Note must have no @Attribute(.unique) — CloudKit does not support it"
        )
    }

    // MARK: - CloudKit-readiness: NoteBlock @Model metadata

    @Test("NoteBlock @Model: all properties are optional or have defaults (CloudKit-readiness)")
    func noteBlockPropertiesAreCloudKitReady() throws {
        let container = try ModelContainer(
            for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let entity = try #require(
            container.schema.entities.first { $0.name == "NoteBlock" },
            "NoteBlock entity must be present in the schema"
        )

        #expect(!entity.attributes.isEmpty, "NoteBlock must declare stored attributes")
        for attribute in entity.attributes {
            let isOptional = attribute.isOptional
            let hasDefault = attribute.defaultValue != nil
            #expect(
                isOptional || hasDefault,
                "Attribute '\(attribute.name)' must be optional or have a default value for CloudKit readiness"
            )
        }

        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints.
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "NoteBlock must have no @Attribute(.unique) — CloudKit does not support it"
        )
    }
}
