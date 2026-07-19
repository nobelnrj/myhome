import SwiftData

/// Convenience typealias so views and tests use bare `NoteBlock` without the version prefix.
///
/// Flipped from SchemaV3.NoteBlock in Phase 3.
/// Flipped from SchemaV3.NoteBlock → SchemaV4.NoteBlock in Phase 7 (plan 07-02).
/// Flipped from SchemaV4.NoteBlock → SchemaV5.NoteBlock in Phase 8 (STAB-08): must match
/// the production `Schema(versionedSchema: SchemaV5.self)` container, alongside Note. See
/// Note.swift for the full rationale (V4 typealias crashed note save/query under the V5 store).
/// SchemaV5.NoteBlock is copied verbatim from SchemaV4.NoteBlock — no-op migration.
/// Flipped from SchemaV5.NoteBlock → SchemaV6.NoteBlock in Phase 9 (plan 09-01): the production
/// container is built with `Schema(versionedSchema: SchemaV6.self)`. SchemaV6.NoteBlock is
/// copied verbatim from SchemaV5.NoteBlock — no V6 changes to NoteBlock.
/// All views and tests that use `NoteBlock` continue to compile unchanged if the schema version
/// is bumped later — only this file needs updating.
///
/// STAB-08 lesson: this typealias was flipped atomically with Expense/Note/Category/Account/Asset
/// and MigrationPlan.swift (schemas + stages) in one commit — see Account.swift for full rationale.
///
/// Usage:
///   let block = NoteBlock(kindRaw: "checkbox", text: "Buy milk", order: 0)
///   @Query var blocks: [NoteBlock]
/// Flipped from SchemaV8.NoteBlock → SchemaV9.NoteBlock in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.NoteBlock is
/// copied verbatim from SchemaV8.NoteBlock — no V9 changes to NoteBlock.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.NoteBlock → SchemaV10.NoteBlock in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.NoteBlock adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias NoteBlock = SchemaV10.NoteBlock      // was SchemaV9.NoteBlock
