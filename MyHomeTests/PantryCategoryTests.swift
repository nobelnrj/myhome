import Testing
import SwiftUI
@testable import MyHome

// Requirements: ICON-02 (the model names a CATEGORY, never a symbol).
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:MyHomeTests/PantryCategoryTests

/// PantryCategoryTests — pins the closed category set and the totality of the
/// `category → (SF Symbol, colour)` table.
///
/// What these tests can and cannot prove: they prove the mapping is TOTAL (every case yields a
/// non-empty, whitespace-free symbol) and that no shipped tile changed. They CANNOT prove a symbol
/// actually renders — SwiftUI draws nothing and raises no error for an unknown symbol name (the
/// 20-03 `takeoutbag.fill.and.rectangle.portrait` bug passed its unit test). Rendering is verified
/// by screenshot in 22-04.
struct PantryCategoryTests {

    // MARK: - Closed set

    @Test("The category set is exactly the 17 cases the AI-SPEC names")
    func categorySetIsClosedAndComplete() {
        #expect(PantryCategory.allCases.count == 17)

        let expected: Set<String> = [
            "dairy", "eggs", "grainStaple", "spice", "produce", "fruit", "brew", "oilFat",
            "snackBakery", "beverage", "cleaning", "paperDisposable", "personalCare",
            "condiment", "frozen", "petSupplies", "other"
        ]
        #expect(Set(PantryCategory.allCases.map(\.rawValue)) == expected)
    }

    @Test("An unrecognised raw value yields nil so a stale cache entry is rejected")
    func unknownRawValueIsRejected() {
        #expect(PantryCategory(rawValue: "takeoutbag") == nil)
        #expect(PantryCategory(rawValue: "") == nil)
        #expect(PantryCategory(rawValue: "Dairy") == nil)   // raw values are case-sensitive
        #expect(PantryCategory(rawValue: "dairy") == .dairy)
    }

    // MARK: - Totality of the presentation table

    @Test("Every category maps to a non-empty, whitespace-free symbol")
    func presentationIsTotal() {
        for category in PantryCategory.allCases {
            let symbol = category.presentation.symbol
            #expect(!symbol.isEmpty, "\(category.rawValue) has an empty symbol")
            #expect(
                symbol.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                "\(category.rawValue) symbol contains whitespace: '\(symbol)'"
            )
        }
    }

    @Test("The static and instance entry points agree")
    func staticAndInstancePresentationAgree() {
        for category in PantryCategory.allCases {
            #expect(PantryCategory.presentation(for: category).symbol == category.presentation.symbol)
        }
    }

    @Test("Distinct symbols keep the six new categories visually distinguishable")
    func newCategoriesHaveDistinctSymbols() {
        // frozen/cleaning and petSupplies/other deliberately SHARE a colour token; the symbol is
        // what carries the distinction, so the symbols must differ.
        #expect(PantryCategory.frozen.presentation.symbol != PantryCategory.cleaning.presentation.symbol)
        #expect(PantryCategory.petSupplies.presentation.symbol != PantryCategory.other.presentation.symbol)
    }

    // MARK: - Non-regression: no shipped tile changes appearance

    @Test(".other stays the neutral terminal fallback")
    func otherIsTheNeutralBag() {
        #expect(PantryCategory.other.presentation.symbol == "bag.fill")
    }

    @Test("The eleven legacy keyword categories keep today's exact symbols")
    func legacySymbolsAreUnchanged() {
        let legacy: [(PantryCategory, String)] = [
            (.dairy, "drop.fill"),
            (.eggs, "oval.fill"),
            (.grainStaple, "shippingbox.fill"),
            (.spice, "shippingbox.fill"),
            (.produce, "leaf.fill"),
            (.fruit, "basket.fill"),
            (.brew, "cup.and.saucer.fill"),
            (.oilFat, "drop.circle.fill"),
            (.snackBakery, "birthday.cake.fill"),
            (.beverage, "waterbottle.fill"),
            (.cleaning, "bubbles.and.sparkles.fill")
        ]
        for (category, symbol) in legacy {
            #expect(category.presentation.symbol == symbol, "\(category.rawValue) symbol drifted")
        }
    }

    @Test("Legacy colours are unchanged DesignTokens category tokens")
    func legacyColoursAreUnchanged() {
        let legacy: [(PantryCategory, Color)] = [
            (.dairy, DesignTokens.catGroceries),
            (.eggs, DesignTokens.catGroceries),
            (.grainStaple, DesignTokens.catPantryGrain),
            (.spice, DesignTokens.catPantryGrain),
            (.produce, DesignTokens.catSubscriptions),
            (.fruit, DesignTokens.catFuel),
            (.brew, DesignTokens.catPantryBrew),
            (.oilFat, DesignTokens.catRent),
            (.snackBakery, DesignTokens.catEntertainment),
            (.beverage, DesignTokens.catAuto),
            (.cleaning, DesignTokens.catUtilities)
        ]
        for (category, color) in legacy {
            #expect(category.presentation.color == color, "\(category.rawValue) colour drifted")
        }
    }

    @Test("The six new categories use only existing DesignTokens category tokens")
    func newCategoriesUseExistingTokens() {
        #expect(PantryCategory.paperDisposable.presentation.color == DesignTokens.catShopping)
        #expect(PantryCategory.personalCare.presentation.color == DesignTokens.catHealth)
        #expect(PantryCategory.condiment.presentation.color == DesignTokens.catDining)
        #expect(PantryCategory.frozen.presentation.color == DesignTokens.catUtilities)
        #expect(PantryCategory.petSupplies.presentation.color == DesignTokens.catOther)
        #expect(PantryCategory.other.presentation.color == DesignTokens.catOther)
    }
}
