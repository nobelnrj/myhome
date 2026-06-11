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
typealias Account = SchemaV7.Account
