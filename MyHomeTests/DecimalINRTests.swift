import Testing
import Foundation
@testable import MyHome

// Requirements: formattedINRCompact() threshold coverage (< 1000, ≥ 1000, ≥ 100000)
// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/DecimalINRTests

/// DecimalINRTests — pure formatting tests for `Decimal.formattedINRCompact()`.
///
/// `formattedINRCompact()` is the chart-axis / bar-annotation formatter added in Plan 04-02.
/// Thresholds (from 04-PATTERNS.md lines 461-490 and 04-RESEARCH.md):
///   < 1000   → "₹N"   (e.g. "₹500", "₹999")
///   ≥ 1000   → "₹Nk"  (e.g. "₹5k", "₹1k")
///   ≥ 100000 → "₹NL"  (e.g. "₹1L", "₹2L")
///
/// `formattedINRCompact()` does NOT yet exist on `Decimal` (RED).
/// Do NOT add the production method here — that is Plan 04-02.
struct DecimalINRTests {

    // MARK: - < 1000 bucket: plain "₹N"

    @Test("below1000: Decimal(500).formattedINRCompact() == \"₹500\"")
    func below1000_midValue() {
        #expect(Decimal(500).formattedINRCompact() == "₹500",
                "500 is below the 1000 threshold; expected \"₹500\"")
    }

    @Test("below1000_singleDigit: Decimal(1).formattedINRCompact() == \"₹1\"")
    func below1000_singleDigit() {
        #expect(Decimal(1).formattedINRCompact() == "₹1",
                "1 is well below 1000; expected \"₹1\"")
    }

    @Test("below1000_boundaryMinus1: Decimal(999).formattedINRCompact() == \"₹999\"")
    func below1000_boundaryMinus1() {
        #expect(Decimal(999).formattedINRCompact() == "₹999",
                "999 is just below the 1000 boundary; expected \"₹999\" (not \"₹1k\")")
    }

    // MARK: - ≥ 1000 bucket: "₹Nk" (boundary inclusive)

    @Test("atBoundary1000: Decimal(1000).formattedINRCompact() == \"₹1k\"")
    func atBoundary1000() {
        #expect(Decimal(1000).formattedINRCompact() == "₹1k",
                "Exactly 1000 should produce \"₹1k\" (boundary is inclusive)")
    }

    @Test("inThousands: Decimal(5000).formattedINRCompact() == \"₹5k\"")
    func inThousands() {
        #expect(Decimal(5000).formattedINRCompact() == "₹5k",
                "5000 should produce \"₹5k\"")
    }

    @Test("inThousandsMid: Decimal(50000).formattedINRCompact() == \"₹50k\"")
    func inThousandsMid() {
        #expect(Decimal(50000).formattedINRCompact() == "₹50k",
                "50000 is ≥ 1000 and < 100000; expected \"₹50k\"")
    }

    @Test("justBelow100000: Decimal(99000).formattedINRCompact() == \"₹99k\"")
    func justBelow100000() {
        #expect(Decimal(99000).formattedINRCompact() == "₹99k",
                "99000 is just below the 100000 boundary; expected \"₹99k\" (not \"₹1L\")")
    }

    // MARK: - ≥ 100000 bucket: "₹NL" (lakh, boundary inclusive)

    @Test("atBoundary100000: Decimal(100000).formattedINRCompact() == \"₹1L\"")
    func atBoundary100000() {
        #expect(Decimal(100000).formattedINRCompact() == "₹1L",
                "Exactly 100000 should produce \"₹1L\" (boundary is inclusive; not \"₹100k\")")
    }

    @Test("inLakhs: Decimal(150000).formattedINRCompact() == \"₹1L\"")
    func inLakhs() {
        #expect(Decimal(150000).formattedINRCompact() == "₹1L",
                "150000 = 1.5 L; Int(1.5) = 1 → expected \"₹1L\"")
    }

    @Test("inLakhsLarge: Decimal(500000).formattedINRCompact() == \"₹5L\"")
    func inLakhsLarge() {
        #expect(Decimal(500000).formattedINRCompact() == "₹5L",
                "500000 = 5 L; expected \"₹5L\"")
    }
}
