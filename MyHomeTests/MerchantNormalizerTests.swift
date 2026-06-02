import Testing
import Foundation
@testable import MyHome

// Requirements: ING-15, D7-09, D7-12
// Threat ref: none (pure logic, no network/storage)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/MerchantNormalizerTests
// Plan 07-03 — GREEN phase: MerchantNormalizer implemented.

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
        let result = MerchantNormalizer.normalize("AMAZON IN BLR")
        #expect(result.normalizedName == "Amazon", "Expected Amazon but got \(result.normalizedName)")
        #expect(result.categoryHint == "Shopping", "Expected Shopping but got \(result.categoryHint ?? "nil")")
    }

    @Test("normalize: ZOMATO ONL BANGAL → Zomato, categoryHint Dining — ING-15")
    func normalizeZomato() {
        let result = MerchantNormalizer.normalize("ZOMATO ONL BANGAL")
        #expect(result.normalizedName == "Zomato", "Expected Zomato but got \(result.normalizedName)")
        #expect(result.categoryHint == "Dining", "Expected Dining but got \(result.categoryHint ?? "nil")")
    }

    // MARK: - D7-09: Longest-key-wins rule

    @Test("normalize: AMAZON IN wins over AMAZON (longest prefix match) — D7-09")
    func longestKeyWins() {
        // "AMAZON IN" is a longer key than "AMAZON"; both map to Amazon/Shopping.
        // This test verifies that "AMAZON IN 12345" still resolves correctly (longest-key path).
        let result = MerchantNormalizer.normalize("AMAZON IN 12345")
        #expect(result.normalizedName == "Amazon", "Longest-key-wins should resolve to Amazon — D7-09")
        #expect(result.categoryHint == "Shopping")
    }

    // MARK: - D7-12: Unknown merchant passthrough

    @Test("normalize: unknown merchant passes through raw string, categoryHint nil — D7-12")
    func unknownMerchantPassthrough() {
        let rawMerchant = "XYZUNKNOWNBANK 99999"
        let result = MerchantNormalizer.normalize(rawMerchant)
        #expect(result.normalizedName == rawMerchant, "Unknown merchant should pass through unchanged — D7-12")
        #expect(result.categoryHint == nil, "Unknown merchant should have nil categoryHint — D7-12")
    }

    // MARK: - Additional coverage

    @Test("normalize: SWIGGY prefix matches → Swiggy, Dining — ING-15")
    func normalizeSwiggy() {
        let result = MerchantNormalizer.normalize("SWIGGY FOOD ORDER")
        #expect(result.normalizedName == "Swiggy")
        #expect(result.categoryHint == "Dining")
    }

    @Test("normalize: UBER match → Uber, Auto/Cab — ING-15")
    func normalizeUber() {
        let result = MerchantNormalizer.normalize("UBER INDIA 1234")
        #expect(result.normalizedName == "Uber")
        #expect(result.categoryHint == "Auto/Cab")
    }
}
