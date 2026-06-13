import SwiftData

/// Convenience typealias for the Phase 11 Asset model (scaffold only in Phase 9).
///
/// New in Phase 9 (plan 09-01, SchemaV6). The production container is built with
/// `Schema(versionedSchema: SchemaV6.self)`, so the app MUST use SchemaV6.Asset.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV6.self. See Account.swift for full rationale.
///
/// Flipped SchemaV5 → SchemaV6 in Phase 9 (plan 09-01).
/// SchemaV6.Asset is an additive scaffold — no UI this phase; Phase 11 adds Asset Tracker UI.
///
/// Usage:
///   let asset = Asset()
///   @Query var assets: [Asset]
/// Flipped from SchemaV8.Asset → SchemaV9.Asset in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Asset is
/// copied verbatim from SchemaV8.Asset — no V9 changes to Asset.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Asset = SchemaV9.Asset      // was SchemaV8.Asset
