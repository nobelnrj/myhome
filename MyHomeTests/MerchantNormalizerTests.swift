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

    // MARK: - Real-corpus seed additions (07-07)

    @Test("normalize: real-corpus merchants resolve to expected category — 07-07")
    func realCorpusSeedAdditions() {
        // (rawMerchant, expectedNormalizedName, expectedCategory) drawn from the live
        // HDFC/ICICI email corpus that previously fell through to Uncategorized.
        let cases: [(String, String, String)] = [
            ("INNOVATIVE RETAIL CONCEPTS PRIVATE LIMITED", "BigBasket", "Groceries"),
            ("BLINK COMMERCE PVT LTD",                     "Blinkit",   "Groceries"),
            ("Delightful Gourmet Pvt",                     "Licious",   "Meat"),
            ("SRI SAI VEG BASKET",                         "Sri Sai Veg Basket", "Groceries"),
            ("FRESHALICIOUS SUPER BAZAAR",                 "Freshalicious", "Groceries"),
            ("CORNER HOUSE ICE CREAMS KAMMANAHALLI",       "Corner House Ice Creams", "Dining"),
            ("OHHH MOMO STATION",                          "Ohhh Momo Station", "Dining"),
            ("Aditya Birla Fashion And Retail Limited",    "Aditya Birla Fashion", "Shopping"),
            ("Amazon Pay Groceries",                       "Amazon Pay", "Groceries"),
            ("ATRIA CONVERGENCE TECH",                     "ACT Fibernet", "Utilities"),
            ("ANTHROPIC* CLAUDE SUB",                      "Anthropic", "Misc"),
            ("VERCEL DOMAINS",                             "Vercel",    "Misc"),
            ("TO ONL NACH_DR/CIUB7020202261000973/GROWW INVEST TECH::00520", "Groww", "Investments"),
            ("TO ONL BSE LIMITED:PAYMENT::00520",          "BSE",       "Investments"),
        ]
        for (raw, expectedName, expectedCategory) in cases {
            let result = MerchantNormalizer.normalize(raw)
            #expect(result.normalizedName == expectedName,
                    "\(raw): expected name \(expectedName), got \(result.normalizedName)")
            #expect(result.categoryHint == expectedCategory,
                    "\(raw): expected \(expectedCategory), got \(result.categoryHint ?? "nil")")
        }
    }

    @Test("normalize: AMAZON PAY IN GROCERY → Groceries (more specific than AMAZON) — 07-07")
    func amazonGroceryBeatsGenericAmazon() {
        let result = MerchantNormalizer.normalize("AMAZON PAY IN GROCERY")
        #expect(result.categoryHint == "Groceries",
                "Longer 'AMAZON PAY IN GROCERY' key should win over 'AMAZON'→Shopping")
    }

    // MARK: - Keyword-based category fallback (07-07)

    @Test("normalize: unknown merchant with category keyword → hint set, raw name kept — 07-07")
    func keywordFallbackInfersCategory() {
        // Not in the explicit seed, but the keyword makes the type obvious.
        let cases: [(String, String)] = [
            ("SHREE VENKATESHWARA RESTAURANT", "Dining"),
            ("NANDINI DAIRY PARLOUR",          "Groceries"),
            ("APOLLO 24|7 PHARMACY",           "Health/Pharmacy"), // APOLLO seed → Health/Pharmacy anyway
            ("KUMAR PROVISION STORE",          "Groceries"),
            ("XYZ FILLING STATION",            "Fuel"),
            ("TO ATM WDL:RR NO:021200008232:PBGN3220-UBI KANNUR BANGALORE", "ATM"),  // CUB ATM withdrawal
            ("TO ONL NACH_DR/CIUB7020202261000973/INDIAN CLEARING C::00520", "Investments"),  // NACH SIP
        ]
        for (raw, expectedCategory) in cases {
            let result = MerchantNormalizer.normalize(raw)
            #expect(result.categoryHint == expectedCategory,
                    "\(raw): expected \(expectedCategory), got \(result.categoryHint ?? "nil")")
            // Keyword fallback must NOT rename the merchant — raw string is preserved.
            #expect(result.normalizedName == raw || MerchantNormalizer.seed.keys.contains(where: { raw.uppercased().contains($0) }),
                    "\(raw): keyword fallback should keep the raw display name")
        }
    }

    @Test("normalize: keyword fallback does not fire for a truly unknown merchant — 07-07")
    func keywordFallbackRespectsUnknown() {
        let result = MerchantNormalizer.normalize("MILLION MARKET C4")
        // No seed key, no keyword — must remain uncategorized (nil hint), raw name preserved.
        #expect(result.normalizedName == "MILLION MARKET C4")
        #expect(result.categoryHint == nil)
    }
}
