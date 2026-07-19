import SwiftData

/// Convenience typealias for the Phase 12 RoutineCompletion model.
///
/// New in Phase 12 (plan 12-01, SchemaV9). Records one completion per routine note per IST day
/// (D-06, NOTE-05). Written at check-time, before RoutineResetService can wipe isChecked overnight.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV9.self.
///
/// Usage:
///   let completion = RoutineCompletion(noteID: note.id, dayKey: dayKey)
///   @Query var completions: [RoutineCompletion]
/// Flipped from SchemaV9.RoutineCompletion → SchemaV10.RoutineCompletion in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.RoutineCompletion adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias RoutineCompletion = SchemaV10.RoutineCompletion      // was SchemaV9.RoutineCompletion
