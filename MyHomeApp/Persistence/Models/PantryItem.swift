import SwiftData

/// Convenience typealias so views, services, and tests use bare `PantryItem` without the
/// version prefix.
///
/// New in Phase 20 (plan 20-01, SchemaV11). The production container is built with
/// `Schema(versionedSchema: SchemaV11.self)`, so the app MUST use SchemaV11.PantryItem.
///
/// PantryItem is the kitchen inventory spine (KTCH-01): name, quantity, unit,
/// lowStockThreshold, restockQuantity. Stock state is DERIVED, never stored —
/// `quantity <= 0` is out of stock, `quantity <= lowStockThreshold` is low (KTCH-02).
/// It carries syncID/updatedAt from birth and is `SyncStamped`, so kitchen rows flow
/// through the Phase 18 sync engine with no backfill migration (KTCH-04).
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV11.self and flips the container to SchemaV11.
/// Mismatched typealiases (one file pointing at V10 while the container runs V11) cause
/// save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let rice = PantryItem(name: "Rice", quantity: 2, unit: "kg", lowStockThreshold: 1)
///   @Query(sort: \PantryItem.name) var pantry: [PantryItem]
typealias PantryItem = SchemaV11.PantryItem
