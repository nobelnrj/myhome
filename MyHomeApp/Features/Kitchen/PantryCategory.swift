import SwiftUI

/// The closed set of household-item kinds a pantry entry can be, and the ONE place in the app where
/// an SF Symbol name for a pantry tile is written down (ICON-02).
///
/// **Why a category enum instead of a symbol string.** From 22-02 onward an on-device model
/// classifies item names. A model asked for a symbol name will happily emit a plausible-but-fake one
/// — and SwiftUI draws *nothing* for an unknown symbol, raising no error. That exact bug shipped in
/// 20-03 (`takeoutbag.fill.and.rectangle.portrait`) and survived a passing unit test, because the
/// test asserted the string the function returned, not that the string named a real symbol. So the
/// model returns a `PantryCategory` case; Swift owns symbol selection. An invalid symbol is
/// therefore *unrepresentable* by any caller, rather than something we test for after the fact.
///
/// **The switch in `presentation(for:)` has no `default:` clause, deliberately.** Adding a case
/// later is a compile error instead of a silently blank tile.
///
/// **Still: any symbol string added to that table must be eyeballed on the simulator before it
/// ships.** No test can prove a symbol renders. 22-04 screenshots every tile.
///
/// **No `@available` gate and no `import FoundationModels` here (P22-D2).** The keyword fallback
/// path must work when the on-device model is unavailable and on every OS the app supports. The
/// `@Generable` twin (`GeneratedPantryCategory`, iOS 26 only) lands in 22-02 and maps onto this
/// type; a parity test there pins the two case sets together.
///
/// Raw values are explicit so the 22-02 device-local cache format survives refactors.
enum PantryCategory: String, CaseIterable, Sendable {
    case dairy = "dairy"
    case eggs = "eggs"
    case grainStaple = "grainStaple"
    case spice = "spice"
    case produce = "produce"
    case fruit = "fruit"
    case brew = "brew"
    case oilFat = "oilFat"
    case snackBakery = "snackBakery"
    case beverage = "beverage"
    case cleaning = "cleaning"
    case paperDisposable = "paperDisposable"
    case personalCare = "personalCare"
    case condiment = "condiment"
    case frozen = "frozen"
    case petSupplies = "petSupplies"
    // Added 2026-07-22 — user asked why the set was so small. Appended (never reordered) so the
    // 22-02 device-local cache, which stores the raw value, keeps resolving old entries.
    case meatSeafood = "meatSeafood"
    case healthMedicine = "healthMedicine"
    case babyCare = "babyCare"
    case household = "household"
    case nutsDryFruit = "nutsDryFruit"
    case other = "other"

    /// The tile appearance for a category. TOTAL by construction — exhaustive `switch`, no
    /// `default:` (see the type doc comment: that missing `default:` IS the ICON-02 guarantee).
    ///
    /// Colours are EXISTING `DesignTokens` category tokens only — no new tokens, no literal hex, no
    /// system colours, so pantry tiles stay inside the app's adaptive light/dark palette.
    ///
    /// Two pairs deliberately SHARE a colour token — `frozen`/`cleaning` (both `catUtilities`) and
    /// `petSupplies`/`other` (both `catOther`). That is not an oversight to "fix": the palette has
    /// no further category tokens, and the symbol carries the distinction.
    static func presentation(for category: PantryCategory) -> (symbol: String, color: Color) {
        switch category {
        // --- Legacy set: these eleven must match what KitchenLogic.iconRules rendered before
        // 22-01, because that refactor was behaviour-preserving. Do not "improve" them here
        // without a screenshot pass; KitchenLogicTests pins the visible outcome.
        case .dairy:           return ("drop.fill", DesignTokens.catGroceries)
        case .eggs:            return ("oval.fill", DesignTokens.catGroceries)
        case .grainStaple:     return ("shippingbox.fill", DesignTokens.catPantryGrain)
        // NOTE (22-04 gallery observation): spice and grainStaple render an IDENTICAL tile — same
        // symbol AND same colour — so the model's distinction between them is invisible on screen.
        // Elsewhere in this table categories that share a colour are separated by their symbol
        // (frozen/cleaning, petSupplies/other); this pair is the one place that rule is broken.
        // Left as-is deliberately: `spice` is a LEGACY keyword category, so today's Sugar/Salt/
        // Masala rows already draw this tile, and changing it is a visible change to shipped rows
        // rather than a bug fix. Raised for the user at the 22-04 checkpoint.
        case .spice:           return ("shippingbox.fill", DesignTokens.catPantryGrain)
        case .produce:         return ("leaf.fill", DesignTokens.catSubscriptions)
        case .fruit:           return ("basket.fill", DesignTokens.catFuel)
        case .brew:            return ("cup.and.saucer.fill", DesignTokens.catPantryBrew)
        case .oilFat:          return ("drop.circle.fill", DesignTokens.catRent)
        case .snackBakery:     return ("birthday.cake.fill", DesignTokens.catEntertainment)
        case .beverage:        return ("waterbottle.fill", DesignTokens.catAuto)
        case .cleaning:        return ("bubbles.and.sparkles.fill", DesignTokens.catUtilities)

        // --- New in Phase 22. These six symbols are CANDIDATES: 22-04 verifies each by screenshot
        // and substitutes any that renders empty. Do not swap them silently before that pass.
        case .paperDisposable: return ("scroll.fill", DesignTokens.catShopping)
        case .personalCare:    return ("hands.sparkles.fill", DesignTokens.catHealth)
        case .condiment:       return ("fork.knife", DesignTokens.catDining)
        case .frozen:          return ("snowflake", DesignTokens.catUtilities)
        case .petSupplies:     return ("pawprint.fill", DesignTokens.catOther)

        // --- Added 2026-07-22 (user request: "why is it this limited"). Symbols are CANDIDATES
        // until the gallery screenshot pass confirms each renders — a non-existent SF Symbol draws
        // nothing and raises no error (the 20-03 bug), so an unverified name here is a blank tile.
        case .meatSeafood:     return ("fish.fill", DesignTokens.catFuel)
        case .healthMedicine:  return ("pills.fill", DesignTokens.catGroceries)
        case .babyCare:        return ("teddybear.fill", DesignTokens.catSubscriptions)
        case .household:       return ("wrench.and.screwdriver.fill", DesignTokens.catRent)
        case .nutsDryFruit:    return ("laurel.leading", DesignTokens.catEntertainment)

        // --- Terminal fallback: the neutral bag tile an unmatched name has always produced.
        case .other:           return ("bag.fill", DesignTokens.catOther)
        }
    }

    /// Instance convenience for `PantryCategory.presentation(for:)`.
    var presentation: (symbol: String, color: Color) {
        PantryCategory.presentation(for: self)
    }
}
