import SwiftData

/// Convenience typealias for the Phase 11.1 SIP model.
///
/// New in Phase 11.1 (plan 11.1-01, SchemaV8). The production container is built with
/// `Schema(versionedSchema: SchemaV8.self)`, so the app MUST use SchemaV8.SIP.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV8.self and flips all other model typealiases.
/// Mismatched typealiases (one file pointing at an older schema while the container runs SchemaV8)
/// cause save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let sip = SIP()
///   @Query var sips: [SIP]
/// Flipped from SchemaV8.SIP → SchemaV9.SIP in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.SIP is
/// copied verbatim from SchemaV8.SIP — no V9 changes to SIP.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.SIP → SchemaV10.SIP in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.SIP adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias SIP = SchemaV10.SIP      // was SchemaV9.SIP
