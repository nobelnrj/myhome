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
typealias Contribution = SchemaV8.Contribution
