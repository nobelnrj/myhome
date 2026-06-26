// InsightVerifier.swift
// Phase 16: AI Insight Card — numeric-integrity verifier + fallback builder (Plan 02 implementation).
//
// InsightVerifier guards against model-invented numbers (AI-04): every rupee/%/delta
// in the model output must match a Swift-precomputed Decimal fact from SpendSummary.
// InsightFallbackBuilder produces a template-based insight (never an error message) when
// the verifier rejects the model output.
//
// Pitfall 5 (16-RESEARCH.md): bare integers < 100 without ₹ prefix or % suffix are
// NOT treated as guarded numbers — avoids false positives on prose like "3 items".
// Open Question 2 (16-RESEARCH.md): Indian lakh grouping (₹1,23,456) is handled by
// stripping ALL commas before Decimal conversion, so standard and lakh formats both resolve.

import Foundation

// MARK: - InsightVerifier

/// Numeric-integrity gatekeeper for model output (AI-04).
///
/// Strategy: extract "guarded" numeric tokens from the generated text, normalise each to
/// `Decimal` (strip ₹ prefix, all commas; % suffix marks a percentage), and check membership
/// in the canonical fact set derived from `SpendSummary`. Any guarded number not present in
/// the fact set causes the verifier to reject the insight and substitute the
/// `InsightFallbackBuilder` output (which always reads like a normal terse insight).
///
/// Guarded numbers are:
///   - Those with a ₹ prefix (rupee amounts)
///   - Those with a % suffix (percentages)
///   - Bare integers or decimals with magnitude ≥ 100 (large standalone numbers — safety net)
///
/// Bare integers < 100 with no ₹ prefix and no % suffix are skipped (Pitfall 5).
@available(iOS 26, *)
enum InsightVerifier {

    // MARK: - Result

    /// Result returned by `verify(_:against:)`.
    struct Result {
        /// The observation text to display (either original or fallback).
        let observation: String
        /// The suggestion text to display, or `nil`.
        let suggestion: String?
        /// `true` if every guarded numeric token matched an injected fact; `false` if fallback was used.
        let passed: Bool
    }

    // MARK: - Canonical Fact Set

    /// Builds the complete `Set<Decimal>` of pre-computed facts from a `SpendSummary`.
    ///
    /// Includes: `totalSpend`, `priorTotalSpend`, `abs(delta)`, the whole-number percentage
    /// `Decimal(abs(Int(deltaFraction * 100)))`, every `categoryBreakdown[].spentDecimal`,
    /// and every `priorCategorySpend.values`.
    static func buildCanonicalSet(from summary: SpendSummary) -> Set<Decimal> {
        var facts = Set<Decimal>()

        // Headline totals
        facts.insert(summary.totalSpend)
        facts.insert(summary.priorTotalSpend)

        // Absolute delta (direction-agnostic: e.g. ₹2,000 whether up or down)
        facts.insert(abs(summary.delta))

        // Whole-number percentage (e.g. Decimal(20) for "20%" when deltaFraction ≈ 0.2)
        let pct = Decimal(abs(Int(summary.deltaFraction * 100)))
        facts.insert(pct)

        // Per-category current-period spend
        for item in summary.categoryBreakdown {
            facts.insert(item.spentDecimal)
        }

        // Per-category prior-period spend
        for value in summary.priorCategorySpend.values {
            facts.insert(value)
        }

        return facts
    }

    // MARK: - Number Extraction

    /// Returns `true` if every "guarded" number in `text` is a member of `facts`.
    ///
    /// Uses a Regex literal to locate all number tokens (with optional ₹ prefix and optional %
    /// suffix). Each match is normalised by stripping the ₹ prefix and all commas before
    /// `Decimal(string:)` conversion, making standard and lakh grouping equivalent.
    ///
    /// Guard rule (Pitfall 5): a bare number with no ₹ prefix and no % suffix is only flagged
    /// if its magnitude is ≥ 100; smaller prose integers ("skipping 2 orders") are ignored.
    static func allNumbersVerified(in text: String, against facts: Set<Decimal>) -> Bool {
        // Regex captures:
        //   Group 1 (₹)?   — optional Indian rupee sign prefix
        //   Group 2 digits  — one or more digits, optionally with commas / lakh grouping
        //   Group 3 (%)?    — optional percent suffix
        let pattern = /(?:(₹)\s*)?([\d][\d,]*)(?:\.\d+)?(%)?/
        for match in text.matches(of: pattern) {
            let hasRupeePrefix   = match.output.1 != nil
            let hasPercentSuffix = match.output.3 != nil
            let raw = String(match.output.2).replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(string: raw) else { continue }

            // Apply guard rule: skip bare numbers < 100 with no ₹ or % marker
            guard hasRupeePrefix || hasPercentSuffix || value >= 100 else { continue }

            if !facts.contains(value) {
                return false
            }
        }
        return true
    }

    // MARK: - Verify

    /// Verifies that every guarded number in `insight` is a pre-computed fact from `summary`.
    ///
    /// - Parameters:
    ///   - insight: The final, complete `SpendInsight` produced by the model (not a partial).
    ///   - summary: The `SpendSummary` whose fact set the insight is checked against.
    /// - Returns: `Result` with the verified (or fallback) text and a `passed` flag.
    static func verify(_ insight: SpendInsight, against summary: SpendSummary) -> Result {
        let facts = buildCanonicalSet(from: summary)
        let combined = insight.observation + (insight.suggestion ?? "")

        if allNumbersVerified(in: combined, against: facts) {
            return Result(
                observation: insight.observation,
                suggestion: insight.suggestion,
                passed: true
            )
        } else {
            let fallback = InsightFallbackBuilder.build(for: summary)
            return Result(
                observation: fallback.observation,
                suggestion: fallback.suggestion,
                passed: false
            )
        }
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
/// `suggestion` is always `nil` (the fallback never invents a nudge).
///
/// Rupee amounts are formatted via the en_IN currency locale (Indian rupee, no decimal places)
/// matching the app's existing currency rendering convention.
@available(iOS 26, *)
enum InsightFallbackBuilder {

    // MARK: - Build

    /// Returns a template-generated `SpendInsight` using only pre-computed fact values.
    ///
    /// Sentence structure:
    ///   - With a top category: "You spent ₹X — [TopCat] was the top category at ₹Y, with total spend [up/down] N% vs last period."
    ///   - Without categories:  "You spent ₹X this period, [up/down] N% vs the previous period."
    ///
    /// Category name is truncated to ≤ 30 characters (matches prompt-side truncation in Plan 03).
    static func build(for summary: SpendSummary) -> SpendInsight {
        let totalStr = rupeeString(from: summary.totalSpend)
        let direction = summary.delta >= 0 ? "up" : "down"
        let pct = abs(Int(summary.deltaFraction * 100))

        let observation: String
        if let topCat = summary.categoryBreakdown.first {
            let catName = String(topCat.name.prefix(30))
            let catStr = rupeeString(from: topCat.spentDecimal)
            observation = "You spent \(totalStr) — \(catName) was the top category at \(catStr), with total spend \(direction) \(pct)% vs last period."
        } else {
            observation = "You spent \(totalStr) this period, \(direction) \(pct)% vs the previous period."
        }

        return SpendInsight(observation: observation, suggestion: nil)
    }

    // MARK: - Formatting

    /// Formats a `Decimal` amount as an Indian-locale rupee string (e.g. "₹12,000").
    ///
    /// Uses `NumberFormatter` with `currencyCode: "INR"` and `locale: en_IN` to produce the
    /// same grouping style used elsewhere in the app. Decimal is converted via `NSDecimalNumber`
    /// — never via `Double` — to avoid floating-point rounding (app convention).
    private static func rupeeString(from decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: decimal as NSDecimalNumber) ?? "₹\(decimal)"
    }
}
