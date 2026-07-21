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
/// Flipped from SchemaV9.Asset → SchemaV10.Asset in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.Asset adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV10.Asset → SchemaV11.Asset in Phase 20 (plan 20-01): the production
/// container is built with `Schema(versionedSchema: SchemaV11.self)`. SchemaV11.Asset is
/// copied verbatim from SchemaV10.Asset — V11 adds only the two new kitchen @Models
/// (PantryItem, ShoppingListItem).
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Asset = SchemaV11.Asset      // was SchemaV10.Asset
