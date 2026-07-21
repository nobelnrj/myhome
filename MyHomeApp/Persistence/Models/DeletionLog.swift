import SwiftData

/// Convenience typealias so views, services, and tests use bare `DeletionLog` without the
/// version prefix.
///
/// New in Phase 18 (plan 18-01, SchemaV10). The production container is built with
/// `Schema(versionedSchema: SchemaV10.self)`, so the app MUST use SchemaV10.DeletionLog.
///
/// DeletionLog is the tombstone @Model introduced by SYNC-01: one row per deleted syncable
/// entity so the merge engine (Plan 03) can propagate deletions across devices instead of a
/// missing row being resurrected from a peer.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV10.self and flips the container to SchemaV10.
/// Mismatched typealiases (one file pointing at V9 while the container runs V10) cause
/// save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let tombstone = DeletionLog(entitySyncID: expense.syncID, entityKindRaw: "expense")
///   @Query var tombstones: [DeletionLog]
/// Flipped from SchemaV10.DeletionLog → SchemaV11.DeletionLog in Phase 20 (plan 20-01): the production
/// container is built with `Schema(versionedSchema: SchemaV11.self)`. SchemaV11.DeletionLog is
/// copied verbatim from SchemaV10.DeletionLog — V11 adds only the two new kitchen @Models
/// (PantryItem, ShoppingListItem).
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias DeletionLog = SchemaV11.DeletionLog
