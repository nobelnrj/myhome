import SwiftData

/// Convenience typealias so views and tests use bare `NetWorthSnapshot` without the version prefix.
///
/// New in Phase 11 (plan 11-01, SchemaV7). The production container is built with
/// `Schema(versionedSchema: SchemaV7.self)`, so the app MUST use SchemaV7.NetWorthSnapshot.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV7.self and flips Expense/Note/NoteBlock/Category/Account/Asset.
/// Mismatched typealiases (one file pointing at an older schema while the container runs SchemaV7)
/// cause save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let snapshot = NetWorthSnapshot()
///   @Query(sort: \NetWorthSnapshot.date, order: .reverse) var snapshots: [NetWorthSnapshot]
typealias NetWorthSnapshot = SchemaV7.NetWorthSnapshot
