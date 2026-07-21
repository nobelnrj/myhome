import SwiftData

/// Convenience typealias so views, services, and tests use bare `ShoppingListItem` without
/// the version prefix.
///
/// New in Phase 20 (plan 20-01, SchemaV11). The production container is built with
/// `Schema(versionedSchema: SchemaV11.self)`, so the app MUST use SchemaV11.ShoppingListItem.
///
/// These rows are MANUAL additions only (KTCH-03). The shopping list is DERIVED + MANUAL:
/// low/out-of-stock entries are computed from `PantryItem` state at render time and are never
/// materialised here, so two phones can never mint duplicate "auto" rows for the merge engine
/// to reconcile. Syncable from birth via syncID/updatedAt + `SyncStamped` (KTCH-04).
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV11.self and flips the container to SchemaV11.
/// Mismatched typealiases (one file pointing at V10 while the container runs V11) cause
/// save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let item = ShoppingListItem(name: "Paper towels", quantity: 2, unit: "pcs")
///   @Query(sort: \ShoppingListItem.createdAt) var list: [ShoppingListItem]
typealias ShoppingListItem = SchemaV11.ShoppingListItem
