// RollingMoneyTextTests.swift
// Scaffold for Plan 02 RollingMoneyText assertions.
// Phase 13 Plan 01 — placeholder; Plan 02 fills in real assertions.

import Testing
import Foundation
@testable import MyHome

@MainActor
struct RollingMoneyTextTests {

    @Test("INR formatting: Decimal(123456) formats with lakh grouping")
    func inrLakhFormatting() throws {
        let amount = Decimal(123456)
        let formatted = amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
        // Lakh grouping: ₹1,23,456.00
        #expect(formatted.contains("1,23,456"))
    }

    // Note: reduceMotion behavior is an @Environment concern — cannot be unit-tested
    // without a hosting view. The DS-06 gate is: manual preview test in Xcode Simulator
    // with Accessibility > Reduce Motion ON. Document this as a manual gate.
}
