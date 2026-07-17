import SwiftData

/// Convenience typealias so views and tests use bare `Account` without the version prefix.
///
/// New in Phase 9 (plan 09-01, SchemaV6). The production container is built with
/// `Schema(versionedSchema: SchemaV6.self)`, so the app MUST use SchemaV6.Account.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV6.self and flips Expense/Note/NoteBlock/Category.
/// Mismatched typealiases (one file pointing at V5 while the container runs V6) cause
/// save/query crashes ("entity not found" SwiftDataError; @Query returns empty array).
///
/// Usage:
///   let account = Account(name: "HDFC CC", typeRaw: "credit_card")
///   @Query(sort: \Account.sortOrder) var accounts: [Account]
/// Flipped from SchemaV8.Account → SchemaV9.Account in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Account is
/// copied verbatim from SchemaV8.Account — no V9 changes to Account.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.Account → SchemaV10.Account in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.Account adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Account = SchemaV10.Account      // was SchemaV9.Account
