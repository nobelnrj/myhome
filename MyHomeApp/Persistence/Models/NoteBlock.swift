import SwiftData

/// Convenience typealias so views and tests use bare `NoteBlock` without the version prefix.
///
/// Flipped from SchemaV3.NoteBlock in Phase 3.
/// All views and tests that use `NoteBlock` continue to compile unchanged if the schema version
/// is bumped later — only this file needs updating.
///
/// Usage:
///   let block = NoteBlock(kindRaw: "checkbox", text: "Buy milk", order: 0)
///   @Query var blocks: [NoteBlock]
typealias NoteBlock = SchemaV3.NoteBlock
