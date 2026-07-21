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
/// Flipped from SchemaV10.RoutineCompletion → SchemaV11.RoutineCompletion in Phase 20 (plan 20-01): the production
/// container is built with `Schema(versionedSchema: SchemaV11.self)`. SchemaV11.RoutineCompletion is
/// copied verbatim from SchemaV10.RoutineCompletion — V11 adds only the two new kitchen @Models
/// (PantryItem, ShoppingListItem).
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias RoutineCompletion = SchemaV11.RoutineCompletion      // was SchemaV10.RoutineCompletion
