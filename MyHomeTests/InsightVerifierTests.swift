// InsightVerifierTests.swift
// Phase 16: AI Insight Card — numeric-integrity verifier test scaffolds (Plan 01 RED).
//
// Requirements: AI-04 (InsightVerifier rejects model-invented numbers; passes fact-only numbers)
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
//             -only-testing:MyHomeTests/InsightVerifierTests
//
// Wave 1 RED/GREEN status (stubs — Plan 02 turns all GREEN):
//   RED:   testVerifierRejectsInventedNumber  (stub always returns passed=true → #expect fails)
//   GREEN: testVerifierPassesFactOnlyNumbers  (stub returns passed=true, which is correct)
//
// Pitfall 9 (16-RESEARCH.md): @available(iOS 26, *) on each @Test function, NOT at struct level.
// Pitfall 5 (16-RESEARCH.md): verifier skips small integers < 100 (not ₹-prefixed or %-suffixed);
//   use rupee amounts ≥ ₹100 and percentage figures in fixtures.

import Testing
import Foundation
import SwiftData
@testable import MyHome

// MARK: - Fixture Helpers

/// Builds a minimal `SpendSummary` with known fact values for verifier tests.
///
/// Canonical facts:
///   totalSpend = ₹12,000  priorTotalSpend = ₹10,000
///   delta = ₹2,000        deltaFraction ≈ 20%
///   No category breakdown (avoids PersistentIdentifier complexity in Wave 1).
@available(iOS 26, *)
private func makeVerifierTestSummary() -> SpendSummary {
    SpendSummary(
        range: .month,
        totalSpend: 12_000,
        priorTotalSpend: 10_000,
        trendBuckets: [],
        categoryBreakdown: [],
        priorCategorySpend: [:]
    )
}

/// Builds a `SpendInsight` with an observation that uses ONLY facts from `makeVerifierTestSummary`.
///
/// Uses rupee amounts that appear verbatim in the summary's fact set:
///   ₹12,000 (totalSpend) and 20% (deltaFraction as whole-number percentage).
@available(iOS 26, *)
private func makeFactOnlyInsight() -> SpendInsight {
    SpendInsight(
        observation: "You spent ₹12,000 this month, up 20% vs last period.",
        suggestion: nil
    )
}

/// Builds a `SpendInsight` with an observation that contains a number NOT in the fact set.
///
/// ₹15,000 is invented — it does not appear in `makeVerifierTestSummary`.
/// The verifier should reject this and return `passed: false`.
@available(iOS 26, *)
private func makeInventedNumberInsight() -> SpendInsight {
    SpendInsight(
        observation: "You spent ₹15,000 this month, which is higher than expected.",
        suggestion: nil
    )
}

// MARK: - InsightVerifierTests

/// Tests for InsightVerifier numeric-integrity check (AI-04).
///
/// Each @Test is gated @available(iOS 26, *) per Pitfall 9.
struct InsightVerifierTests {

    // MARK: AI-04: Number Integrity

    /// AI-04 — RED in Plan 01: verifier should reject ₹15,000 (not in fact set)
    /// and return `passed: false` with fallback text.
    ///
    /// Plan 01 stub returns `passed: true` unconditionally → #expect(result.passed == false) FAILS.
    /// Plan 02 Task 1 implements real number-extraction: detects ₹15,000 ∉ fact set → passed = false.
    @Test("InsightVerifier rejects observation with model-invented rupee amount")
    @available(iOS 26, *)
    func testVerifierRejectsInventedNumber() {
        let summary = makeVerifierTestSummary()
        let insight = makeInventedNumberInsight()

        let result = InsightVerifier.verify(insight, against: summary)

        // RED: stub returns passed=true → this #expect fails until Plan 02 implements real check.
        #expect(result.passed == false)

        // When rejected, verifier must substitute fallback text (never empty, never an error msg).
        // This #expect is also RED in Plan 01 (same stub issue).
        #expect(result.observation != insight.observation,
                "Rejected insight must be replaced with fallback text, not the original")
        #expect(result.observation.isEmpty == false,
                "Fallback observation must not be empty")
    }

    /// AI-04 — GREEN in Plan 01 (accidentally): stub returns passed=true,
    /// which happens to be correct for fact-only numbers.
    ///
    /// Plan 02 implements real check; this test should remain GREEN.
    @Test("InsightVerifier passes observation that uses only fact values")
    @available(iOS 26, *)
    func testVerifierPassesFactOnlyNumbers() {
        let summary = makeVerifierTestSummary()
        let insight = makeFactOnlyInsight()

        let result = InsightVerifier.verify(insight, against: summary)

        // GREEN: stub returns passed=true. Plan 02 real implementation also returns passed=true
        // for numbers ₹12,000 (totalSpend) and 20% (deltaFraction) which are in the fact set.
        #expect(result.passed == true)
        #expect(result.observation == insight.observation,
                "Passed insight observation must be returned unchanged")
    }
}
