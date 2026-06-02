import Testing
import Foundation
@testable import MyHome

// Requirements: ING-12
// Threat ref: none (pure logic)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/ConfidenceScorerTests
// Plan 07-01 — RED phase: ConfidenceScorer is unimplemented (plan 03).
// Tests FAIL RED via Issue.record until plan 03 provides ConfidenceScorer.

/// ConfidenceScorerTests — unit tests for ConfidenceScorer boundary behaviour.
///
/// ING-12: Confidence ≥0.85 → ingestionStateRaw = "autoSaved";
///         confidence <0.85 → ingestionStateRaw = "needsReview".
@MainActor
struct ConfidenceScorerTests {

    // MARK: - ING-12: Full-field parse scores ≥ 0.85 (autoSaved side)

    @Test("score: full fingerprint + all fields present → score ≥ 0.85 (autoSaved) — ING-12")
    func highConfidenceScore() {
        Issue.record("ConfidenceScorer unimplemented — plan 03")
        // When ConfidenceScorer exists, replace body with:
        // let fullResult = ParsedExpense(
        //     amount: Decimal(1250),
        //     rawMerchant: "AMAZON IN BLR",
        //     normalizedMerchant: "Amazon",
        //     categoryHint: "Shopping",
        //     date: Date(),
        //     rawSourceLabel: "HDFC CC ••4321",
        //     isReversal: false,
        //     fingerprintScore: 1.0,
        //     extractionScore: 1.0
        // )
        // let score = ConfidenceScorer.score(fullResult)
        // #expect(score >= 0.85, "Full-field parse should score ≥ 0.85 — ING-12")
    }

    // MARK: - ING-12: Missing amount → score < 0.85 (needsReview side)

    @Test("score: missing amount (amount=0, extractionScore low) → score < 0.85 (needsReview) — ING-12")
    func lowConfidenceScore() {
        Issue.record("ConfidenceScorer unimplemented — plan 03")
        // let partialResult = ParsedExpense(
        //     amount: Decimal(0),          // amount extraction failed
        //     rawMerchant: "UNKNOWN",
        //     normalizedMerchant: "UNKNOWN",
        //     categoryHint: nil,
        //     date: Date(),
        //     rawSourceLabel: "HDFC CC ••4321",
        //     isReversal: false,
        //     fingerprintScore: 0.5,        // partial fingerprint match
        //     extractionScore: 0.3          // poor extraction quality
        // )
        // let score = ConfidenceScorer.score(partialResult)
        // #expect(score < 0.85, "Partial parse should score < 0.85 — ING-12")
    }
}
