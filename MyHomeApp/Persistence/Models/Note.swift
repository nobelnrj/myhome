import SwiftData

/// Convenience typealias so views and tests use bare `Note` without the version prefix.
///
/// Flipped from SchemaV3.Note in Phase 3.
/// All views and tests that use `Note` continue to compile unchanged if the schema version
/// is bumped later — only this file needs updating.
///
/// Usage:
///   let note = Note(title: "Grocery List")
///   @Query var notes: [Note]
typealias Note = SchemaV3.Note
