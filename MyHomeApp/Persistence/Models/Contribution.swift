import SwiftData

/// Convenience typealias for the Phase 11.1 Contribution model.
///
/// New in Phase 11.1 (plan 11.1-01, SchemaV8). Records one estimated or reconciled
/// unit-purchase entry per SIP installment date (D-03, D-05).
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV8.self.
///
/// Usage:
///   let contribution = Contribution()
///   @Query var contributions: [Contribution]
/// Flipped from SchemaV8.Contribution → SchemaV9.Contribution in Phase 12 (plan 12-01).
/// SchemaV9.Contribution is copied verbatim from SchemaV8.Contribution — no V9 changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.Contribution → SchemaV10.Contribution in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.Contribution adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Contribution = SchemaV10.Contribution      // was SchemaV9.Contribution
