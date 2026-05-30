import SwiftData

/// Convenience typealias so views and tests use bare `Category` without the version prefix.
///
/// If a SchemaV3 renames or extends Category, flip this typealias in one line.
///
/// Usage:
///   let category = Category(name: "Groceries", symbolName: "cart")
///   @Query(sort: \Category.sortOrder) var categories: [Category]
typealias Category = SchemaV3.Category
