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
/// Flipped from SchemaV8.SIPAmountChange → SchemaV9.SIPAmountChange in Phase 12 (plan 12-01).
/// SchemaV9.SIPAmountChange is copied verbatim from SchemaV8.SIPAmountChange — no V9 changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.SIPAmountChange → SchemaV10.SIPAmountChange in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.SIPAmountChange adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias SIPAmountChange = SchemaV10.SIPAmountChange      // was SchemaV9.SIPAmountChange
