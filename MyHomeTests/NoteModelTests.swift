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

    // MARK: - STAB-08: Note typealias must match the production versionedSchema

    /// STAB-08 regression — the app's `Note`/`NoteBlock` typealiases MUST resolve to the same
    /// schema version the production container is built from (`Schema(versionedSchema: SchemaV6.self)`).
    ///
    /// Pre-fix: `typealias Note = SchemaV4.Note` while the container registered `SchemaV5.Note`,
    /// so saving a note inserted an entity absent from the store's schema → SwiftData `save()`
    /// crashed with an internal assertion (and the notes `@Query` crashed once any note existed).
    /// The other Note tests use `ModelContainer(for: Note.self, ...)`, which registers whatever
    /// `Note` aliases, so they could not catch the mismatch. This test pins the production schema.
    @Test("noteSavesUnderProductionVersionedSchema — STAB-08")
    func noteSavesUnderProductionVersionedSchema() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("MyHome.store")

        // Build the container the same way appContainer() does: from the versioned schema.
        // Updated in Phase 9 (plan 09-01): SchemaV5 → SchemaV6 (STAB-08: container schema must
        // match the active typealias; Note is now SchemaV6.Note, so the container must be V6).
        let schema = Schema(versionedSchema: SchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Save a note with a block — this is what AddNoteView.createNote / EditNoteView do.
        let note = Note(title: "STAB-08")
        context.insert(note)
        let block = NoteBlock(kindRaw: "checkbox", text: "task", order: 0)
        context.insert(block)
        block.note = note
        try context.save()  // pre-fix: SwiftData assertion crash here

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1, "STAB-08: note must persist under the production versionedSchema")
        #expect(fetched.first?.title == "STAB-08", "STAB-08: title must round-trip")
    }
}
