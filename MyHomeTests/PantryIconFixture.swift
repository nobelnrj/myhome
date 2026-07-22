import Foundation
@testable import MyHome

/// The committed reference dataset for Phase 22 — household item name → expected `PantryCategory`
/// (AI-SPEC §5.1).
///
/// It is weighted toward **this household's vocabulary** (Indian staples) rather than generic US
/// grocery terms, because that is the distribution the on-device model actually meets. It is split
/// into three MARKed groups so a failure is legible at a glance:
///
/// - `motivating` — the names that caused this phase to exist. Before Phase 22 every one of them
///   fell through the keyword table to the neutral `bag.fill`.
/// - `nonRegression` — names the pre-Phase-22 keyword table already got right. These carry a
///   **stricter** threshold (100%, vs 90% overall), which is why they are exposed separately.
/// - `ambiguous` — cases with a defensible second answer. The accepted answer is recorded here,
///   with a rationale in a comment wherever the call was genuinely close, so a future disagreement
///   is a decision to revisit rather than a bug to chase.
///
/// Consumed by `PantryIconStructuralTests` (deterministic, always-on) and `PantryIconEvalTests`
/// (model accuracy, opt-in behind `PANTRY_ICON_EVAL=1`).
enum PantryIconFixture {

    typealias Entry = (name: String, expected: PantryCategory)

    // MARK: - Motivating (AI-SPEC §5.1)
    //
    // Every one of these landed on the neutral bag before Phase 22 — no keyword rule matches them.
    // They are the phase's own acceptance criteria.

    static let motivating: [Entry] = [
        ("kitchen tissue",  .paperDisposable),
        ("fabric softener", .cleaning),
        ("dish scrubber",   .cleaning),
        ("toilet cleaner",  .cleaning),
        ("aluminium foil",  .paperDisposable),
        ("paper napkins",   .paperDisposable)
    ]

    // MARK: - Non-regression (stricter threshold: 100%)
    //
    // The keyword table in `KitchenLogic.iconRules` already answers all of these, and each answer
    // is what shipped in 20-03. The model must not make any of them worse — a staple the user has
    // looked at for months must not change tile because inference arrived.

    static let nonRegression: [Entry] = [
        ("milk",              .dairy),
        ("eggs",              .eggs),
        ("filter coffee",     .brew),
        ("cooking oil",       .oilFat),
        ("sona masoori rice", .grainStaple),
        ("atta",              .grainStaple),
        ("toor dal",          .grainStaple),
        ("onions",            .produce),
        ("sugar",             .spice),
        ("dishwash liquid",   .cleaning)
    ]

    // MARK: - Ambiguous / adversarial
    //
    // Two calls here were genuinely close and are DOCUMENTED CHOICES, not accidents:
    //
    // 1. **bournvita → .beverage, not .brew.** A malt drink mix is prepared and consumed as a
    //    beverage. `.brew` is reserved for tea leaves and coffee grounds — the things you steep or
    //    extract. If the household later decides the shelf reads better with all hot drinks
    //    together, change this line and the tile follows; it is a taxonomy preference, not a defect.
    //
    // 2. **baby wipes → .personalCare, not .paperDisposable.** They are physically a paper
    //    disposable, but intended use is personal care, and that is what someone scanning the
    //    pantry is looking for. `.paperDisposable` stays the answer for kitchen roll, foil and
    //    napkins — items whose whole identity is "single-use kitchen paper".
    //
    // The rest are recorded because the obvious reading is wrong: ghee and coconut oil read as
    // dairy and produce respectively, and are fats.

    static let ambiguous: [Entry] = [
        ("ghee",         .oilFat),      // NOT dairy — it is clarified butterfat, used as a cooking fat
        ("curd",         .dairy),
        ("coconut oil",  .oilFat),      // reads as produce; it is a fat
        ("green tea",    .brew),
        ("bournvita",    .beverage),    // documented above
        ("baby wipes",   .personalCare),// documented above
        ("",             .other),       // blank name — the neutral tile, never a crash
        ("zqx",          .other),       // nonsense — the model must say "other", not guess

        // --- This household's staples. The fixture is deliberately heavier here than on generic
        // US grocery nouns: these are the words actually typed into the pantry.
        ("rava",          .grainStaple),
        ("poha",          .grainStaple),
        ("jaggery",       .spice),       // matches the sweetener rule the keyword table already uses
        ("curry leaves",  .produce),
        ("coconut",       .produce),
        ("tamarind",      .condiment),   // a souring agent used by the spoonful, not eaten as fruit
        ("mustard seeds", .spice),
        ("idli batter",   .grainStaple)
    ]

    /// Every fixture row, in group order.
    static let cases: [Entry] = motivating + nonRegression + ambiguous
}
