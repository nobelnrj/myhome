// InsightService.swift
// Phase 16: AI Insight Card — service-layer contracts (Plan 01 stubs).
//
// All FoundationModels-touching declarations are gated @available(iOS 26, *).
// Plans 02 and 03 implement the real generation logic against these fixed signatures.

import Foundation
import FoundationModels

// MARK: - SpendInsight

/// Guided-generation output struct: a terse spending observation + optional soft suggestion.
///
/// - `observation`: one or two sentences grounded in the injected `SpendSummary` facts.
///   ONLY rupee figures and percentages from the prompt context may appear — never invented.
/// - `suggestion`: optional, data-grounded nudge; nil when nothing meaningful to add.
///
/// Tone constraints (D-05): warm, non-judgmental; no budgets, limits, or policing language.
@available(iOS 26, *)
@Generable(description: "A brief spending insight for a two-person Indian household finance app")
struct SpendInsight {

    @Guide(description: """
        One or two sentences observing the most notable spending pattern for the period. \
        Terse, concrete, no preamble. Use ONLY the rupee figures and percentages \
        explicitly listed in the context above — never invent, calculate, or round numbers.
        """)
    var observation: String

    @Guide(description: """
        Optional soft, data-grounded suggestion. Include only when a clear, fact-supported \
        nudge exists for this household. Never mention budgets, limits, or financial policing. \
        Omit entirely if nothing meaningful to add.
        """)
    var suggestion: String?
}

// MARK: - Open Question 1 Build-Check

/// Compile-only proof that `@Generable` preserves the memberwise init on `SpendInsight`.
///
/// If this function does NOT compile after `@Generable` is applied, `InsightFallbackBuilder`
/// must switch to a plain `FallbackInsight { let observation: String; let suggestion: String? }`
/// struct (non-Generable). Record the outcome in 16-01-SUMMARY.md so Plans 02 and 04 can
/// adapt their fallback paths accordingly.
///
/// Never called at runtime — compile-only verification.
@available(iOS 26, *)
private func _spendInsightMemberwiseInitBuildCheck() {
    // Open Question 1 (16-RESEARCH.md): does @Generable preserve memberwise init?
    _ = SpendInsight(observation: "open-question-1-build-check", suggestion: nil)
}

// MARK: - InsightGenerating Protocol

/// The single testability seam for all unit tests (AI-02, AI-03).
///
/// `LanguageModelSession` is `final` — it cannot be subclassed or mocked directly.
/// All business logic routes through this protocol so `MockInsightService` can drive tests
/// without a physical Apple Intelligence device or live session.
///
/// - Throws: `LanguageModelSession.GenerationError` on guardrail/context-window failure.
/// - Throws: `CancellationError` when the enclosing Swift task is cancelled (D-08).
@available(iOS 26, *)
protocol InsightGenerating: Sendable {
    func generate(for summary: SpendSummary) async throws -> SpendInsight
}

// MARK: - InsightPromptBuilder

/// Serialises `SpendSummary` facts into a token-budgeted prompt string (AI-03).
///
/// Stub: both members return placeholder values.
/// Plan 03 Task 2 implements the full rupee-formatted, category-enumerated prompt
/// that stays under the ~400-token target (leaving room for output in the 4,096 limit).
@available(iOS 26, *)
enum InsightPromptBuilder {

    /// System instructions injected into every `LanguageModelSession`.
    static let systemInstructions: String = """
        You are a friendly spending assistant for a two-person Indian household.
        Write one or two sentences of observation followed by an optional soft suggestion.
        Use ONLY the rupee amounts and percentages explicitly given in the context below —
        never calculate, round, or invent figures.
        Be warm and non-judgmental. Avoid mentioning budgets, limits, or financial advice.
        """

    /// Builds the user-facing prompt from pre-computed `SpendSummary` facts.
    ///
    /// Returns `""` in Plan 01. Plan 03 injects total spend, prior spend, delta %,
    /// top-5 categories with rupee amounts, and instructs the model to write an insight.
    static func buildPrompt(for summary: SpendSummary) -> String {
        return ""  // stub — Plan 03 Task 2 implements full token-budgeted prompt
    }
}

// MARK: - Availability Helper

/// Returns `true` only when `SystemLanguageModel` is `.available` on this device.
///
/// Covers all four availability branches (AI-02 / D-01/D-02):
///   - `.available`                                  → `true`  (card shown)
///   - `.unavailable(.deviceNotEligible)`            → `false` (card omitted entirely)
///   - `.unavailable(.appleIntelligenceNotEnabled)`  → `false` (card omitted entirely)
///   - `.unavailable(.modelNotReady)`                → `false` (card omitted entirely)
///
/// This file-scope function is the unit-testable seam: tests inject known
/// `SystemLanguageModel.Availability` values and assert the return value.
///
/// Returns `true` only when the system model is `.available`; `false` for every
/// unavailability reason (D-01). The switch is exhaustive over all three
/// `UnavailableReason` cases so a future SDK reason surfaces as a compile error
/// rather than silently falling through a `default:`.
@available(iOS 26, *)
func isInsightAvailable(_ availability: SystemLanguageModel.Availability) -> Bool {
    switch availability {
    case .available:
        return true
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return false
        case .appleIntelligenceNotEnabled:
            return false
        case .modelNotReady:
            return false
        @unknown default:
            return false
        }
    }
}
