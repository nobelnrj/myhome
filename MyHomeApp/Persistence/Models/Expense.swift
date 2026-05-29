import SwiftData

/// Convenience typealias so views and tests use bare `Expense` without the version prefix.
///
/// When Phase 2 introduces SchemaV2 with an updated Expense shape,
/// this typealias flips to `SchemaV2.Expense` in one line — no view changes needed.
///
/// Usage:
///   let expense = Expense(amount: Decimal(500), note: "Lunch")
///   @Query var expenses: [Expense]
typealias Expense = SchemaV1.Expense
