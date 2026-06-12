import SwiftData

/// Convenience typealias for the Phase 11.1 SIPAmountChange model.
///
/// New in Phase 11.1 (plan 11.1-01, SchemaV8). Records point-in-time SIP amount changes (D-07).
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV8.self.
///
/// Usage:
///   let change = SIPAmountChange()
///   @Query var changes: [SIPAmountChange]
typealias SIPAmountChange = SchemaV8.SIPAmountChange
