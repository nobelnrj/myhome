import SwiftData

/// Convenience typealias so views and tests use bare `NetWorthSnapshot` without the version prefix.
///
/// New in Phase 11 (plan 11-01, V7 schema). Flipped V7 → V8 in Phase 11.1 (plan 11.1-01).
/// The production container is built with `Schema(versionedSchema: SchemaV8.self)`.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV8.self and flips Expense/Note/NoteBlock/Category/Account/Asset.
/// Mismatched typealiases (one file pointing at an older schema while the container runs SchemaV8)
/// cause save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let snapshot = NetWorthSnapshot()
///   @Query(sort: \NetWorthSnapshot.date, order: .reverse) var snapshots: [NetWorthSnapshot]
typealias NetWorthSnapshot = SchemaV8.NetWorthSnapshot
