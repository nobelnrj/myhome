// InsightVerifier.swift
// Phase 16: AI Insight Card — numeric-integrity verifier + fallback builder (Plan 01 stubs).
//
// InsightVerifier guards against model-invented numbers (AI-04): every rupee/%/delta
// in the model output must match a Swift-precomputed Decimal fact from SpendSummary.
// InsightFallbackBuilder produces a template-based insight (never an error message) when
// the verifier rejects the model output.
//
// Both types are @available(iOS 26, *) because they consume SpendInsight (same gating).
// Plan 02 implements the real number-extraction and matching logic.

import Foundation

// MARK: - InsightVerifier

/// Numeric-integrity gatekeeper for model output (AI-04).
///
/// Strategy (Plan 02): extract numeric tokens from the final generated text, normalise
/// each to `Decimal` (strip ₹ prefix, commas, % suffix), and check membership in the
/// canonical fact set derived from `SpendSummary`. Any number ≥ 100 or %-suffixed that
/// does not appear in the fact set causes the verifier to reject the insight and substitute
/// the `InsightFallbackBuilder` output (which always reads like a normal terse insight).
///
/// Stub: always returns `passed: true` with the insight unchanged.
/// Plan 02 Task 1 implements the real regex-based extraction and Decimal matching.
@available(iOS 26, *)
enum InsightVerifier {

    /// Result returned by `verify(_:against:)`.
    struct Result {
        /// The observation text to display (either original or fallback).
        let observation: String
        /// The suggestion text to display, or `nil`.
        let suggestion: String?
        /// `true` if every numeric token matched an injected fact; `false` if fallback was used.
        let passed: Bool
    }

    /// Verifies that every number in `insight` is a pre-computed fact from `summary`.
    ///
    /// - Parameters:
    ///   - insight: The final, complete `SpendInsight` produced by the model (not a partial).
    ///   - summary: The `SpendSummary` whose fact set the insight is checked against.
    /// - Returns: `Result` with the verified (or fallback) text and a `passed` flag.
    ///
    /// Stub: returns `passed: true` with the original insight unchanged.
    static func verify(_ insight: SpendInsight, against summary: SpendSummary) -> Result {
        // stub — Plan 02 Task 1 implements real number-integrity check
        return Result(
            observation: insight.observation,
            suggestion: insight.suggestion,
            passed: true
        )
    }
}

// MARK: - InsightFallbackBuilder

/// Builds a template-based `SpendInsight` from pre-computed `SpendSummary` facts.
///
/// Used when:
///   (a) `InsightVerifier` rejects the model output (AI-04), or
///   (b) `LanguageModelSession` throws a `GenerationError` (AI-03).
///
/// The fallback reads like a normal terse insight — never like an error message (D-05/AI-04).
/// All numbers it contains come directly from `SpendSummary` so it always passes verification.
///
/// Stub placeholder: Plan 02 Task 2 implements the full rupee-formatted template.
@available(iOS 26, *)
enum InsightFallbackBuilder {

    /// Returns a template-generated `SpendInsight` using only pre-computed fact values.
    ///
    /// Stub: returns a fixed placeholder observation. Plan 02 Task 2 implements
    /// the rupee-formatted template with top-category and delta-direction prose.
    static func build(for summary: SpendSummary) -> SpendInsight {
        // stub — Plan 02 Task 2 implements rupee-formatted fallback template
        return SpendInsight(observation: "Spending summary is available for this period.", suggestion: nil)
    }
}
