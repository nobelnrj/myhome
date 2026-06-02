import Testing
import Foundation
@testable import MyHome

// Requirements: ING-12
// Threat ref: none (pure logic)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/ConfidenceScorerTests
// Plan 07-03 — GREEN phase: ConfidenceScorer implemented.

/// ConfidenceScorerTests — unit tests for ConfidenceScorer boundary behaviour.
///
/// ING-12: Confidence ≥0.85 → ingestionStateRaw = "autoSaved";
///         confidence <0.85 → ingestionStateRaw = "needsReview".
///
/// Scoring formula: fingerprintScore * 0.5 + extractionScore * 0.5
///   extractionScore = amount(0.40) + date(0.25, always) + merchant(0.20) + card(0.15)
@MainActor
struct ConfidenceScorerTests {

    // MARK: - ING-12: Full-field parse scores ≥ 0.85 (autoSaved side)

    @Test("score: full fingerprint + all fields present → score ≥ 0.85 (autoSaved) — ING-12")
    func highConfidenceScore() {
        let fullResult = ParsedExpense(
            amount: Decimal(1250),
            rawMerchant: "AMAZON IN BLR",
            normalizedMerchant: "Amazon",
            categoryHint: "Shopping",
            date: Date(),
            rawSourceLabel: "HDFC CC ••4321",
            isReversal: false,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
        // extractionScore recomputed: 0.40 + 0.25 + 0.20 + 0.15 = 1.0
        // score = 1.0 * 0.5 + 1.0 * 0.5 = 1.0
        let score = ConfidenceScorer.score(fullResult)
        #expect(score >= 0.85, "Full-field parse should score ≥ 0.85 — ING-12; got \(score)")
    }

    // MARK: - ING-12: Missing card only → still ≥ 0.85

    @Test("score: full fingerprint + missing card only → score ≥ 0.85 — ING-12")
    func missingCardOnlyStillHighConfidence() {
        let result = ParsedExpense(
            amount: Decimal(500),
            rawMerchant: "ZOMATO",
            normalizedMerchant: "Zomato",
            categoryHint: "Dining",
            date: Date(),
            rawSourceLabel: "",          // card/account missing (weight 0.15)
            isReversal: false,
            fingerprintScore: 1.0,
            extractionScore: 0.85
        )
        // extractionScore = 0.40 + 0.25 + 0.20 + 0.0 = 0.85
        // score = 1.0 * 0.5 + 0.85 * 0.5 = 0.925
        let score = ConfidenceScorer.score(result)
        #expect(score >= 0.85, "Missing card only should still score ≥ 0.85 — ING-12; got \(score)")
    }

    // MARK: - ING-12: Missing amount → score < 0.85 (needsReview side)

    @Test("score: missing amount → score < 0.85 (needsReview) — ING-12")
    func lowConfidenceScoreMissingAmount() {
        let partialResult = ParsedExpense(
            amount: Decimal(0),          // amount extraction failed
            rawMerchant: "UNKNOWN",
            normalizedMerchant: "UNKNOWN",
            categoryHint: nil,
            date: Date(),
            rawSourceLabel: "HDFC CC ••4321",
            isReversal: false,
            fingerprintScore: 1.0,       // full fingerprint but amount missing
            extractionScore: 0.60
        )
        // extractionScore = 0.0 (amount=0) + 0.25 + 0.20 + 0.15 = 0.60
        // score = 1.0 * 0.5 + 0.60 * 0.5 = 0.80
        let score = ConfidenceScorer.score(partialResult)
        #expect(score < 0.85, "Missing amount should score < 0.85 — ING-12; got \(score)")
    }

    // MARK: - ING-12: Partial fingerprint + partial fields → score < 0.85

    @Test("score: partial fingerprint + partial extraction → score < 0.85 — ING-12")
    func partialFingerprintLowConfidence() {
        let partialResult = ParsedExpense(
            amount: Decimal(0),
            rawMerchant: "UNKNOWN",
            normalizedMerchant: "UNKNOWN",
            categoryHint: nil,
            date: Date(),
            rawSourceLabel: "HDFC CC ••4321",
            isReversal: false,
            fingerprintScore: 0.5,       // partial fingerprint match
            extractionScore: 0.3         // poor extraction quality
        )
        // extractionScore = 0.0 + 0.25 + 0.20 + 0.15 = 0.60
        // score = 0.5 * 0.5 + 0.60 * 0.5 = 0.25 + 0.30 = 0.55
        let score = ConfidenceScorer.score(partialResult)
        #expect(score < 0.85, "Partial parse should score < 0.85 — ING-12; got \(score)")
    }
}
