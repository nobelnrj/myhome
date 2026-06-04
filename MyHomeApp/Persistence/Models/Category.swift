import SwiftData

/// Convenience typealias so views and tests use bare `Category` without the version prefix.
///
/// Flipped from SchemaV3.Category → SchemaV4.Category in Phase 7 (plan 07-02).
/// Flipped from SchemaV4.Category → SchemaV5.Category in multi-account plan (260603-lvt).
/// If a future schema renames or extends Category, flip this typealias in one line.
///
/// Usage:
///   let category = Category(name: "Groceries", symbolName: "cart")
///   @Query(sort: \Category.sortOrder) var categories: [Category]
typealias Category = SchemaV5.Category
