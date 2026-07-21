import SwiftData

/// Convenience typealias so views and tests use bare `Category` without the version prefix.
///
/// Flipped from SchemaV3.Category → SchemaV4.Category in Phase 7 (plan 07-02).
/// Flipped from SchemaV4.Category → SchemaV5.Category in multi-account plan (260603-lvt).
/// Flipped from SchemaV5.Category → SchemaV6.Category in Phase 9 (plan 09-01): the production
/// container is built with `Schema(versionedSchema: SchemaV6.self)`. SchemaV6.Category is
/// copied verbatim from SchemaV5.Category — no V6 changes to Category.
/// If a future schema renames or extends Category, flip this typealias in one line.
///
/// STAB-08 lesson: this typealias was flipped atomically with Expense/Note/NoteBlock/Account/Asset
/// and MigrationPlan.swift (schemas + stages) in one commit — see Account.swift for full rationale.
///
/// Usage:
///   let category = Category(name: "Groceries", symbolName: "cart")
///   @Query(sort: \Category.sortOrder) var categories: [Category]
/// Flipped from SchemaV8.Category → SchemaV9.Category in Phase 12 (plan 12-01): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Category is
/// copied verbatim from SchemaV8.Category — no V9 changes to Category.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV9.Category → SchemaV10.Category in Phase 18 (plan 18-01): the production
/// container is built with `Schema(versionedSchema: SchemaV10.self)`. SchemaV10.Category adds
/// syncID + updatedAt (SYNC-01); no other changes.
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
/// Flipped from SchemaV10.Category → SchemaV11.Category in Phase 20 (plan 20-01): the production
/// container is built with `Schema(versionedSchema: SchemaV11.self)`. SchemaV11.Category is
/// copied verbatim from SchemaV10.Category — V11 adds only the two new kitchen @Models
/// (PantryItem, ShoppingListItem).
///
/// STAB-08 lesson: flipped atomically with all other model typealiases in one commit.
typealias Category = SchemaV11.Category      // was SchemaV10.Category
