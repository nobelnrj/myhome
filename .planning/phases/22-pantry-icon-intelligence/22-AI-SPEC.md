# AI-SPEC — Phase 22: Pantry Icon Intelligence

**Requirements:** ICON-01, ICON-02, ICON-03
**Created:** 2026-07-21
**Status:** contract — locked before planning

> **Scope note on how this spec was produced.** The full `/gsd-ai-integration-phase`
> orchestration (framework-selector → ai-researcher → domain-researcher → eval-planner)
> was deliberately not run. The framework decision is foreclosed by the platform and by
> in-repo precedent (§2), and the "domain" is grocery nouns, which needs a labelled fixture
> rather than web research. What that orchestration exists to prevent — picking the wrong
> framework, and treating evaluation as an afterthought — is addressed directly in §2 and §5.

---

## 1. System Classification

**Type:** single-shot classifier. Not an agent, not RAG, not a chat surface.

- **Input:** one pantry item name (short, user-typed, e.g. `"kitchen tissue"`, `"Sona Masoori rice"`).
- **Output:** one case from a closed category enum. NOT free text, NOT a symbol name.
- **Tools:** none. **Memory/transcript:** none — fresh session per call.
- **Network:** none. Fully on-device.
- **Volume:** once per distinct item name, then cached. A household pantry is tens of items, so
  lifetime inference count is small.
- **Latency tolerance:** high. The row renders immediately with a fallback and upgrades in place;
  nothing blocks on the model.

---

## 2. Framework Decision

**Selected: Apple `FoundationModels` (on-device), iOS 26+.**

This is not a genuine multi-way choice, for three converging reasons:

1. **Precedent in-repo.** Phase 16 already ships `FoundationModels` for the AI insight card
   (`MyHomeApp/Support/InsightService.swift`). The availability gating, `@Generable` guided
   generation, fresh-session-per-call discipline, and fallback-builder patterns are written,
   tested and in production. Introducing a second AI stack for icon-picking would be strictly worse.
2. **Project charter.** v1.3 is explicitly free/no-cloud (no CloudKit, no paid services). A hosted
   LLM would add per-call cost, a network dependency, and a privacy surface for what is household
   inventory data.
3. **Device support.** Both target phones (iPhone 17 Pro Max, iPhone 15 Pro Max) are
   Apple-Intelligence capable.

**Alternatives considered:**

| Option | Verdict |
|---|---|
| Keep keyword table only, expand the list | Rejected — this is the status quo that failed. The table cannot enumerate every household noun; "kitchen tissue"/"fabric softener" is an unbounded tail. |
| Hosted LLM (Claude/OpenAI) | Rejected — cost per call, network dependency, privacy surface, violates the free/no-cloud charter. |
| Bundled embedding model + nearest-neighbour | Rejected — heavier to ship and tune than a guided-generation call, for a 15-way classification the on-device model already does well. |

**Model provider:** Apple on-device system model. No API key, no cost, no rate limit.

---

## 3. Framework Quick Reference

Follow `InsightService.swift` exactly; it is the working reference. Key points:

```swift
import FoundationModels

// Availability — cover ALL branches, do not assume .available
switch SystemLanguageModel.default.availability {
case .available:                     // use the model
case .unavailable(let reason):       // fall back to the keyword table
}

// Guided generation over a CLOSED set
@Generable(description: "The kind of household item a pantry entry refers to")
enum PantryCategory: String, CaseIterable {
    case dairy, eggs, grainStaple, spice, produce, fruit, brew, oilFat
    case snackBakery, beverage, cleaning, paperDisposable, personalCare
    case condiment, frozen, petSupplies, other
}

let session = LanguageModelSession(instructions: ...)   // FRESH per call
let out = try await session.respond(to: prompt, generating: PantryCategory.self)
```

**Pitfalls carried from Phase 16:**

- **Fresh `LanguageModelSession` per call** (Phase 16 Pitfall 3) — no transcript contamination.
- `LanguageModelSession` is `final` — it cannot be mocked. Hide it behind a protocol
  (`PantryIconClassifying`) exactly as Phase 16 hid generation behind `InsightGenerating`,
  so tests inject a fake.
- Handle `GenerationError.guardrailViolation` and `.exceededContextWindowSize` → fall back.
  A grocery noun should never trip a guardrail, but an adversarial item name is user input.
- Everything is `@available(iOS 26, *)`.

---

## 4. Implementation Guidance

### 4.1 The model must never name a symbol — ICON-02

This is the single most important constraint in this phase.

A non-existent SF Symbol **renders nothing and raises no error** — SwiftUI silently draws an empty
tile. This exact bug shipped in 20-03 (`takeoutbag.fill.and.rectangle.portrait`) and survived a
passing unit test, because the test asserted the *string* the function returned, not that the string
named a real symbol. An LLM emitting plausible-but-fake symbol names is that same failure at scale.

**Therefore:** the model returns a `PantryCategory` case. Swift owns the
`category → (SF Symbol, DesignTokens colour)` mapping as a static table. The model cannot express an
invalid symbol, so the failure mode is designed out rather than tested for.

**Every symbol in the mapping table must be eyeballed on the simulator before merge.** A test cannot
prove a symbol renders. Add a screenshot of all N tiles as phase evidence.

### 4.2 Resolution order — model-first, keyword fallback (user decision 2026-07-21)

```
name → local cache hit?           → use it (synchronous, instant)
     → model available?           → classify (async), cache, upgrade the row in place
     → model unavailable/errored  → keyword table → neutral bag.fill
```

The keyword table in `KitchenLogic.iconRules` is **retained**, demoted to the offline/unavailable
fallback. It stays unit-tested and must keep working with Apple Intelligence switched off.

### 4.3 Cache is device-local and never synced — ICON-03

Icons stay **derived**, per the locked 20-01 decision: no `symbolName`/`colorHex` field is added to
`PantryItem`. Adding one would create state that syncs, diverges between phones, and needs migrating —
and would mean a schema bump for a cosmetic feature.

Cache keyed by the normalised name (trimmed, lowercased) in `UserDefaults`/a small store. Consequences
worth accepting: the two phones may briefly disagree on an icon until each classifies locally, which is
harmless and self-correcting.

### 4.4 The async seam is the real work

`KitchenLogic.icon(forName:)` is currently a synchronous pure function called during row rendering.
Inference is async. The pantry list must render immediately with the fallback and upgrade in place —
no spinner in the tile, no layout shift, no blocking the list.

---

## 5. Evaluation Strategy

### 5.1 Reference dataset

A committed fixture of household item names → expected category. Must be weighted to this
household's actual vocabulary (Indian staples), not generic US grocery terms.

**Must include the names that motivated the phase:** `kitchen tissue`, `fabric softener`,
`dish scrubber`, `toilet cleaner`, `aluminium foil`, `paper napkins`.

**Must include the existing keyword-table items as a non-regression set:** `milk`, `eggs`,
`filter coffee`, `cooking oil`, `sona masoori rice`, `atta`, `toor dal`, `onions`, `sugar`,
`dishwash liquid`.

**Must include ambiguous/adversarial cases** with the accepted answer recorded:
`ghee` (oilFat, not dairy), `curd` (dairy), `coconut oil` (oilFat — could read as produce),
`green tea` (brew), `bournvita` (beverage vs brew — pick one and document),
`baby wipes` (personalCare vs paperDisposable), `""` and `"zqx"` (→ other).

### 5.2 Dimensions and thresholds

| Dimension | How measured | Threshold |
|---|---|---|
| Accuracy on the fixture | exact category match | ≥ 90%; **100% on the non-regression set** — a name the old table got right must not regress |
| Never-invalid-symbol | every enum case maps to a symbol that renders | 100%, structural + verified by screenshot |
| Graceful degradation | model unavailable → keyword table → bag.fill, no crash, no empty tile | 100% |
| Non-blocking render | list draws before classification completes | asserted in the view-model test |
| No leakage | no `URLSession`; nothing written to `PantryItem`; nothing added to the sync snapshot | 100% |

Because the model is non-deterministic, the accuracy suite should be runnable but **not** a blocking
CI gate on every run — pin it as an explicitly-invoked test so a flaky single classification cannot
redden the whole suite. The structural guarantees (symbol validity, fallback, no leakage) ARE
blocking and are deterministic.

### 5.3 Guardrails

- Item names are user free text — treat as untrusted input to the prompt. A name like
  "ignore previous instructions" must still return a category or fall back; it must never be able to
  change behaviour beyond icon choice. The closed output enum makes this largely structural.
- No pantry data other than the single item name goes into the prompt. No quantities, no other items,
  no financial context.

---

## 6. Open Questions for Planning

1. Exact category list — 17 proposed in §3. Fewer is more reliable; more is more expressive.
2. Where the cache lives (`UserDefaults` vs a small dedicated store) and whether it is size-capped.
3. Whether to classify eagerly on item creation, or lazily on first render.
4. Whether the edit sheet should let the user override a wrong icon — deferring to planning; note
   an override would need somewhere to live, which reopens the "derived, never stored" decision.
