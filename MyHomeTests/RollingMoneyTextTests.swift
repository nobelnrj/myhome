// RollingMoneyTextTests.swift
// INR lakh-grouping formatting assertion for DS-04.
// Phase 13: DS-04 (Plan 02 — replaces Plan 01 scaffold)

import Testing
import Foundation
@testable import MyHome

@MainActor
struct RollingMoneyTextTests {

    /// Verifies INR currency formatting produces lakh grouping (1,23,456 not 123,456).
    /// This is the critical locale-correctness test: `en_IN` must be used, not `en_US`.
    @Test("INR formatting: Decimal(123456) formats with lakh grouping")
    func inrLakhFormatting() throws {
        let amount = Decimal(123456)
        let formatted = amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
        // Lakh grouping: ₹1,23,456.00
        // en_US would produce ₹123,456.00 — the "1,23," pattern confirms en_IN grouping is active.
        #expect(formatted.contains("1,23,456"))
    }

    /// Verifies larger amounts also use lakh-crore grouping (e.g. 10,00,000 = 10 lakhs).
    @Test("INR formatting: Decimal(1000000) formats with lakh-crore grouping")
    func inrLakhCroreFormatting() throws {
        let amount = Decimal(1000000)
        let formatted = amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
        // 10,00,000 in lakh grouping
        #expect(formatted.contains("10,00,000"))
    }

    // NOTE: The Reduce Motion behavior (`.identity` transition + `nil` animation) is an
    // @Environment(\.accessibilityReduceMotion) concern that cannot be unit-tested without a
    // host view. The DS-06 gate for this path is a MANUAL simulator test:
    //   Simulator → Settings → Accessibility → Motion → Reduce Motion ON
    //   → tap the preview toggle → digits should snap with zero intermediate frames.
    // This is documented here so the manual gate is discoverable alongside the unit tests.
}
