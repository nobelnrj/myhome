import Foundation

// MARK: - ConfidenceScorer

/// Pure static helpers that compute an ingestion confidence score for a parsed expense.
///
/// **Formula** (ING-12, D7-03):
///   `score = fingerprintScore * 0.5 + extractionScore * 0.5`
///
/// **Threshold:** score ≥ 0.85 → auto-save ("autoSaved"); score < 0.85 → Review Inbox ("needsReview").
///
/// **Extraction weights (field completeness):**
///   amount   0.40   — most critical; missing amount is a strong signal of a mis-parse
///   date     0.25   — always credited (parsers fall back to message date if body date is absent)
///   merchant 0.20   — rawMerchant.isEmpty means extraction failed
///   card     0.15   — rawSourceLabel.isEmpty means card/account not extracted
///
/// **Calibration note:** The 0.5/0.5 split and per-field weights above are initial estimates
/// pending real-corpus calibration after the first week of production use (D7-03).
///
/// Mirrors the `BudgetCalculator` pattern: pure `struct` with `static func`, no I/O.
public struct ConfidenceScorer {

    /// Returns a confidence score in [0.0, 1.0] for the given parsed expense.
    ///
    /// - Parameter result: The `ParsedExpense` produced by a bank email parser.
    /// - Returns: A confidence score where ≥ 0.85 qualifies for auto-save (ING-12).
    public static func score(_ result: ParsedExpense) -> Double {
        let extraction = computeExtractionScore(result)
        return result.fingerprintScore * 0.5 + extraction * 0.5
    }

    /// Computes the extraction sub-score: the weighted sum of successfully extracted fields.
    ///
    /// Called internally by `score(_:)`. `internal` (not private) so tests can verify
    /// individual components independently.
    static func computeExtractionScore(_ result: ParsedExpense) -> Double {
        var score: Double = 0.0
        // Amount (0.40): Decimal(0) signals extraction failure (ING-12).
        if result.amount != 0 { score += 0.40 }
        // Date (0.25): always credited — parser falls back to message internalDate (D7-03).
        score += 0.25
        // Merchant (0.20): empty rawMerchant means extraction did not succeed.
        if !result.rawMerchant.isEmpty { score += 0.20 }
        // Card/account label (0.15): empty rawSourceLabel means label was not found (D7-15).
        if !result.rawSourceLabel.isEmpty { score += 0.15 }
        return score
    }

    /// The minimum score that qualifies an expense for automatic saving without review (ING-12).
    ///
    /// Exposed as a public constant so callers (GmailSyncController, tests) can reference the
    /// threshold without hardcoding the literal 0.85.
    public static let autoSaveThreshold: Double = 0.85
}
