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
typealias RoutineCompletion = SchemaV9.RoutineCompletion
