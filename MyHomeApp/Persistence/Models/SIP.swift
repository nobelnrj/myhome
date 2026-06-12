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
typealias SIP = SchemaV8.SIP
