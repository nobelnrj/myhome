import SwiftData

/// Convenience typealias so views and tests use bare `Note` without the version prefix.
///
/// Flipped from SchemaV3.Note in Phase 3.
/// Flipped from SchemaV3.Note → SchemaV4.Note in Phase 7 (plan 07-02).
/// Flipped from SchemaV4.Note → SchemaV5.Note in Phase 8 (STAB-08): the production
/// container is built with `Schema(versionedSchema: SchemaV5.self)`, so the app MUST
/// use SchemaV5.Note. While this typealias still pointed at SchemaV4.Note, every note
/// created/queried was an entity absent from the V5 store schema, crashing `save()` and
/// the notes `@Query` with a SwiftData assertion. SchemaV5.Note is copied verbatim from
/// SchemaV4.Note, so the migration is a no-op.
/// Flipped from SchemaV5.Note → SchemaV6.Note in Phase 9 (plan 09-01): the production
/// container is built with `Schema(versionedSchema: SchemaV6.self)`. SchemaV6.Note is an
/// additive superset of SchemaV5.Note — adds isDailyRoutine and routineLastResetDate fields
/// (D-11, D-12), no removals.
/// Flipped from SchemaV8.Note → SchemaV9.Note in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Note is an
/// additive superset of SchemaV8.Note — adds routineDailyReminderTime field (D-04), no removals.
/// All views and tests that use `Note` continue to compile unchanged.
///
/// STAB-08 lesson: this typealias was flipped atomically with all other model typealiases
/// and MigrationPlan.swift in one commit.
///
/// Usage:
///   let note = Note(title: "Grocery List")
///   @Query var notes: [Note]
typealias Note = SchemaV9.Note      // was SchemaV8.Note
