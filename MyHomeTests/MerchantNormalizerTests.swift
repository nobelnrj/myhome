import Testing
import Foundation
@testable import MyHome

// Requirements: ING-15, D7-09, D7-12
// Threat ref: none (pure logic, no network/storage)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/MerchantNormalizerTests
// Plan 07-01 — RED phase: MerchantNormalizer is unimplemented (plan 03).
// Tests FAIL RED via Issue.record until plan 03 provides MerchantNormalizer.

/// MerchantNormalizerTests — unit tests for MerchantNormalizer via table-driven fixture.
///
/// ING-15: Normalized merchant name + category hint derived from raw merchant string.
/// D7-09:  Longest-key-wins rule for ambiguous prefix matches.
/// D7-12:  Unknown merchant raw string passes through unchanged; categoryHint = nil.
@MainActor
struct MerchantNormalizerTests {

    // MARK: - ING-15: Known merchant normalization

    @Test("normalize: AMAZON IN BLR → Amazon, categoryHint Shopping — ING-15")
    func normalizeAmazon() {
        Issue.record("MerchantNormalizer unimplemented — plan 03")
        // When MerchantNormalizer exists, replace body with:
        // let result = MerchantNormalizer.normalize("AMAZON IN BLR")
        // #expect(result.normalized == "Amazon")
        // #expect(result.categoryHint == "Shopping")
    }

    @Test("normalize: ZOMATO ONL BANGAL → Zomato, categoryHint Dining — ING-15")
    func normalizeZomato() {
        Issue.record("MerchantNormalizer unimplemented — plan 03")
        // let result = MerchantNormalizer.normalize("ZOMATO ONL BANGAL")
        // #expect(result.normalized == "Zomato")
        // #expect(result.categoryHint == "Dining")
    }

    // MARK: - D7-09: Longest-key-wins rule

    @Test("normalize: AMAZON IN wins over AMAZON (longest prefix match) — D7-09")
    func longestKeyWins() {
        Issue.record("MerchantNormalizer unimplemented — plan 03")
        // Verifies that "AMAZON IN" (longer key) takes precedence over "AMAZON" (shorter)
        // let result = MerchantNormalizer.normalize("AMAZON IN 12345")
        // #expect(result.normalized == "Amazon")  // same result but validated via longest key path
    }

    // MARK: - D7-12: Unknown merchant passthrough

    @Test("normalize: unknown merchant passes through raw string, categoryHint nil — D7-12")
    func unknownMerchantPassthrough() {
        Issue.record("MerchantNormalizer unimplemented — plan 03")
        // let rawMerchant = "XYZUNKNOWNBANK 99999"
        // let result = MerchantNormalizer.normalize(rawMerchant)
        // #expect(result.normalized == rawMerchant)
        // #expect(result.categoryHint == nil)
    }
}
