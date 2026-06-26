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

/// Serialises `SpendSummary` facts into a token-budgeted prompt string (AI-03 / AI-04).
///
/// All rupee amounts are formatted from `Decimal` via `NSDecimalNumber` and an en_IN
/// `NumberFormatter` — never via `Double` (floating-point drift prevention, WR-03).
/// Category names are truncated to ≤30 chars (T-16-03 prompt-injection guard).
/// Total prompt budget: target ≤ ~400 tokens (leaves ample room in the 4,096-token limit).
///
/// `buildPrompt` injects ONLY pre-computed facts from `SpendSummary`; it contains
/// NO instruction to calculate, round, or derive any figure — those are app-computed
/// and injected as literal strings (AI-04 prevention-at-source, D-05/D-06).
@available(iOS 26, *)
enum InsightPromptBuilder {

    /// System instructions injected into every `LanguageModelSession`.
    ///
    /// Tone: warm, non-judgmental (D-05). Explicit prohibition on inventing numbers (AI-04/D-06).
    static let systemInstructions: String = """
        You are a friendly spending assistant for a two-person Indian household. \
        Write one or two sentences of observation, then an optional soft suggestion. \
        Use ONLY the rupee amounts and percentages explicitly given in the context below — \
        never calculate, round, or invent any figure. \
        Be warm and non-judgmental. Avoid mentioning budgets, limits, or financial advice.
        """

    /// Builds the user-facing prompt from pre-computed `SpendSummary` facts.
    ///
    /// Injection contract (AI-04 / Pitfall 6):
    /// - `totalSpend` and `priorTotalSpend` — headline rupee figures
    /// - `abs(Int(deltaFraction * 100))%` — whole-number period-over-period delta (same formula
    ///   as `InsightVerifier.buildCanonicalSet` and `InsightFallbackBuilder.build` — self-consistent)
    /// - top-5 `categoryBreakdown` entries with `spentDecimal` and prior spend via
    ///   `summary.priorCategorySpend[cat.id]` (O(1) PersistentIdentifier lookup — Pitfall 6)
    ///
    /// Security (T-16-03): each category name is truncated to ≤30 chars before injection.
    static func buildPrompt(for summary: SpendSummary) -> String {
        // Decimal → en_IN currency string (no Double boundary — WR-03/AI-04)
        let currencyFmt = NumberFormatter()
        currencyFmt.numberStyle = .currency
        currencyFmt.currencyCode = "INR"
        currencyFmt.locale = Locale(identifier: "en_IN")
        currencyFmt.maximumFractionDigits = 0
        currencyFmt.minimumFractionDigits = 0

        func rupee(_ d: Decimal) -> String {
            currencyFmt.string(from: d as NSDecimalNumber) ?? "₹\(d)"
        }

        // Range label
        let rangeLabel: String
        switch summary.range {
        case .week:  rangeLabel = "this week"
        case .month: rangeLabel = "this month"
        case .year:  rangeLabel = "this year"
        }

        // Period-over-period direction and whole-number percentage
        // Formula mirrors InsightVerifier.buildCanonicalSet and InsightFallbackBuilder.build
        // so the injected figure is guaranteed to be in the canonical fact set (AI-04).
        let direction = summary.delta > 0 ? "up" : "down"
        let pct = abs(Int(summary.deltaFraction * 100))

        var lines: [String] = [
            "Spending summary for \(rangeLabel):",
            "  Total spend: \(rupee(summary.totalSpend))",
            "  Prior period: \(rupee(summary.priorTotalSpend)) (\(direction) \(pct)% vs prior)"
        ]

        // Top-5 categories — inject spentDecimal + prior spend (Pitfall 6)
        let topCats = summary.categoryBreakdown.prefix(5)
        if !topCats.isEmpty {
            lines.append("  Top categories:")
            for cat in topCats {
                // T-16-03: truncate user-defined category name to ≤30 chars
                let safeName = String(cat.name.prefix(30))
                let currentAmt = rupee(cat.spentDecimal)
                // O(1) PersistentIdentifier lookup (Pitfall 6)
                if let priorAmt = summary.priorCategorySpend[cat.id] {
                    lines.append("    \(safeName): \(currentAmt) (prior \(rupee(priorAmt)))")
                } else {
                    lines.append("    \(safeName): \(currentAmt)")
                }
            }
        }

        lines.append("")
        lines.append("Write a spending insight for this household using ONLY the figures above.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - InsightService

/// Production implementation of `InsightGenerating`.
///
/// Creates a FRESH `LanguageModelSession` per `generate(for:)` call (Pitfall 3 / T-16-04):
/// no transcript carryover across range changes — each call starts with a clean context.
///
/// Does NOT catch `LanguageModelSession.GenerationError` here — errors propagate to the
/// caller (Plan 04 `AIInsightCard`) which owns the streaming path, error→fallback mapping,
/// and the task cancellation lifecycle (D-08). The view-layer catch block handles:
///   `.guardrailViolation`        → `InsightFallbackBuilder.build(for:)` (AI-03)
///   `.exceededContextWindowSize` → same fallback (AI-03)
///   `CancellationError`         → clear state silently (D-08)
///
/// Security note (T-16-01): `LanguageModelSession` is entirely on-device. No `URLSession`
/// or network entitlement is used. Insight text is ephemeral — never persisted (AI-05).
@available(iOS 26, *)
final class InsightService: InsightGenerating {

    func generate(for summary: SpendSummary) async throws -> SpendInsight {
        // Fresh session per generation (Pitfall 3 / T-16-04): no transcript contamination
        // from prior range context.
        let session = LanguageModelSession(
            instructions: InsightPromptBuilder.systemInstructions
        )
        let prompt = InsightPromptBuilder.buildPrompt(for: summary)
        // respond() returns a complete SpendInsight (non-streaming path).
        // The View layer (Plan 04) drives streaming separately via streamResponse().
        let response = try await session.respond(
            to: prompt,
            generating: SpendInsight.self
        )
        return response.content
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
