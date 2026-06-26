// InsightVerifierTests.swift
// Phase 16: AI Insight Card — numeric-integrity verifier tests (Plan 02 GREEN).
//
// Requirements: AI-04 (InsightVerifier rejects model-invented numbers; passes fact-only numbers)
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
//             -only-testing:MyHomeTests/InsightVerifierTests
//
// Plan 02 turns all tests GREEN:
//   GREEN: testVerifierRejectsInventedNumber    (real number extraction detects ₹15,000 ∉ fact set)
//   GREEN: testVerifierPassesFactOnlyNumbers    (real check confirms ₹12,000 + 20% ∈ fact set)
//   GREEN: testVerifierIgnoresSmallProseIntegers (Pitfall 5: bare integers < 100 are not guarded)
//   GREEN: testFallbackIsVerifierConsistent     (fallback numbers are always in the fact set)
//   GREEN: testFallbackSuggestionIsNil          (fallback never invents a suggestion)
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

    /// AI-04: verifier rejects ₹15,000 (not in fact set) → passed == false, fallback substituted.
    ///
    /// Plan 01 stub returned passed=true unconditionally.
    /// Plan 02 real implementation extracts ₹15,000 → Decimal(15000) ∉ {12000,10000,2000,20}
    /// → passed=false, fallback text substituted.
    @Test("InsightVerifier rejects observation with model-invented rupee amount")
    @available(iOS 26, *)
    func testVerifierRejectsInventedNumber() {
        let summary = makeVerifierTestSummary()
        let insight = makeInventedNumberInsight()

        let result = InsightVerifier.verify(insight, against: summary)

        #expect(result.passed == false)

        // When rejected, verifier must substitute fallback text (never empty, never an error msg).
        #expect(result.observation != insight.observation,
                "Rejected insight must be replaced with fallback text, not the original")
        #expect(result.observation.isEmpty == false,
                "Fallback observation must not be empty")
    }

    /// AI-04: verifier passes ₹12,000 + 20% (both in fact set) → passed == true, original returned.
    @Test("InsightVerifier passes observation that uses only fact values")
    @available(iOS 26, *)
    func testVerifierPassesFactOnlyNumbers() {
        let summary = makeVerifierTestSummary()
        let insight = makeFactOnlyInsight()

        let result = InsightVerifier.verify(insight, against: summary)

        // Real check: ₹12,000 → 12000 ∈ facts, 20% → 20 ∈ facts → passed=true.
        #expect(result.passed == true)
        #expect(result.observation == insight.observation,
                "Passed insight observation must be returned unchanged")
    }

    /// AI-04 + Pitfall 5: bare integers < 100 with no ₹ prefix or % suffix are NOT guarded.
    ///
    /// "You skipped 3 orders and saved 2 days worth of spending." contains bare integers
    /// 3 and 2 (both < 100, no ₹, no %) — they must NOT be treated as guarded numbers.
    /// The verifier must return passed=true since no guarded numbers are present.
    @Test("InsightVerifier ignores small prose integers (no ₹ or % marker, magnitude < 100)")
    @available(iOS 26, *)
    func testVerifierIgnoresSmallProseIntegers() {
        let summary = makeVerifierTestSummary()
        // Observation with small bare integers (2, 3) — none are ₹-prefixed or %-suffixed.
        let insight = SpendInsight(
            observation: "You skipped 3 orders and saved 2 days worth of spending.",
            suggestion: nil
        )

        let result = InsightVerifier.verify(insight, against: summary)

        #expect(result.passed == true,
                "Small prose integers (< 100, no ₹ or %) must not be treated as guarded numbers")
        #expect(result.observation == insight.observation,
                "Insight with only small integers must be returned unchanged")
    }

    // MARK: AI-04: Fallback Builder

    /// AI-04 self-consistency: the fallback output must itself pass verification.
    ///
    /// InsightFallbackBuilder.build(for:) uses ONLY facts from the summary. Verifying the
    /// fallback text against the same summary must return passed=true.
    @Test("InsightFallbackBuilder produces self-consistent insight that passes its own verifier")
    @available(iOS 26, *)
    func testFallbackIsVerifierConsistent() {
        let summary = makeVerifierTestSummary()
        let fallback = InsightFallbackBuilder.build(for: summary)

        let result = InsightVerifier.verify(fallback, against: summary)

        #expect(result.passed == true,
                "Fallback must use only fact-derived numbers so it always passes verification")
        #expect(fallback.observation.isEmpty == false,
                "Fallback observation must not be empty")
    }

    /// AI-04: fallback never invents a suggestion (suggestion is always nil).
    @Test("InsightFallbackBuilder returns nil suggestion (never invents a nudge)")
    @available(iOS 26, *)
    func testFallbackSuggestionIsNil() {
        let summary = makeVerifierTestSummary()
        let fallback = InsightFallbackBuilder.build(for: summary)

        #expect(fallback.suggestion == nil,
                "Fallback must never include a suggestion — it cannot be grounded in facts")
    }
}
