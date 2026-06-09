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
typealias Category = SchemaV6.Category
