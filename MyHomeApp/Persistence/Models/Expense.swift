import SwiftData

/// Convenience typealias so views and tests use bare `Expense` without the version prefix.
///
/// Flipped from SchemaV1.Expense → SchemaV2.Expense in Phase 2.
/// Flipped from SchemaV2.Expense → SchemaV3.Expense in Phase 3.
/// Flipped from SchemaV3.Expense → SchemaV4.Expense in Phase 7 (plan 07-02).
/// Flipped from SchemaV4.Expense → SchemaV5.Expense in multi-account plan (260603-lvt).
/// Flipped from SchemaV5.Expense → SchemaV6.Expense in Phase 9 (plan 09-01): the production
/// container is built with `Schema(versionedSchema: SchemaV6.self)`, so the app MUST use
/// SchemaV6.Expense. SchemaV6.Expense is an additive superset of SchemaV5.Expense — new
/// fields only (accountID, isTransfer, transferPairID), no removals or reorders.
/// All views and tests that use `Expense` continue to compile unchanged.
///
/// STAB-08 lesson: this typealias was flipped atomically with Note/NoteBlock/Category/Account/Asset
/// and MigrationPlan.swift (schemas + stages) in one commit — see Account.swift for full rationale.
///
/// Usage:
///   let expense = Expense(amount: Decimal(500), note: "Lunch")
///   @Query var expenses: [Expense]
/// Flipped from SchemaV8.Expense → SchemaV9.Expense in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Expense is
/// copied verbatim from SchemaV8.Expense — no V9 changes to Expense.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.Expense → SchemaV10.Expense in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.Expense adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV10.Expense → SchemaV11.Expense in Phase 20 (plan 20-01): the production
/// container is built with `Schema(versionedSchema: SchemaV11.self)`. SchemaV11.Expense is
/// copied verbatim from SchemaV10.Expense — V11 adds only the two new kitchen @Models
/// (PantryItem, ShoppingListItem).
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Expense = SchemaV11.Expense      // was SchemaV10.Expense
