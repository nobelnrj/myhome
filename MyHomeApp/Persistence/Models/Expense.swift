import SwiftData

/// Convenience typealias so views and tests use bare `Expense` without the version prefix.
///
/// Flipped from SchemaV1.Expense → SchemaV2.Expense in Phase 2.
/// Flipped from SchemaV2.Expense → SchemaV3.Expense in Phase 3.
/// Flipped from SchemaV3.Expense → SchemaV4.Expense in Phase 7 (plan 07-02).
/// All views and tests that use `Expense` continue to compile unchanged.
///
/// Usage:
///   let expense = Expense(amount: Decimal(500), note: "Lunch")
///   @Query var expenses: [Expense]
typealias Expense = SchemaV4.Expense
