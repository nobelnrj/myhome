import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: OVF-01 (empty selection = all accounts default; subset filters),
//               OVF-02 (account × custom-date-range totals with self-transfer exclusion preserved)
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' \
//             -only-testing:MyHomeTests/OverviewFilterTests

// Disambiguation: the Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

/// OverviewFilterTests — pure-logic tests for `OverviewFilterEngine` (Plan 21-01).
///
/// Task 1 lands this file as an empty-but-compiling scaffold; Task 2 (TDD) fills the
/// behaviors: account-subset filtering, includeUnassigned, transfer-exclusion
/// preservation through BudgetCalculator.grossSpend/grossIncome, account × date-range
/// totals, and IST-injected inclusive boundary edges.
@MainActor
struct OverviewFilterTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Account.self,
                                  configurations: config)
    }
}
