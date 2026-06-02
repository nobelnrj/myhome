import SwiftData

/// Convenience typealias so views and tests use bare `Note` without the version prefix.
///
/// Flipped from SchemaV3.Note in Phase 3.
/// Flipped from SchemaV3.Note → SchemaV4.Note in Phase 7 (plan 07-02).
/// All views and tests that use `Note` continue to compile unchanged if the schema version
/// is bumped later — only this file needs updating.
///
/// Usage:
///   let note = Note(title: "Grocery List")
///   @Query var notes: [Note]
typealias Note = SchemaV4.Note
