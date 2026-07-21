---
phase: 22-pantry-icon-intelligence
plan: 01
subsystem: kitchen
tags: [kitchen, pantry, icons, icon-02, refactor, behaviour-preserving, swift-testing]

# Dependency graph
requires:
  - phase: 20-kitchen-inventory-shopping-list
    plan: 03
    provides: KitchenLogic.icon(forName:) keyword table + the three pinned icon tests
  - phase: 13-design-system-foundation
    provides: DesignTokens category colour tokens (adaptive light/dark)
provides:
  - "PantryCategory — closed 17-case enum (String raw values, CaseIterable, Sendable), no @available gate and no FoundationModels import, so it works with the on-device model absent (P22-D2)"
  - "PantryCategory.presentation(for:) / .presentation — the ONLY place an SF Symbol string for a pantry tile is written; exhaustive switch with no default:, so a new case is a compile error rather than a blank tile (ICON-02)"
  - "KitchenLogic.keywordCategory(forName:) -> PantryCategory? — internal seam for 22-03's model resolver; nil means 'no opinion', distinct from a confident .other"
  - "KitchenLogic.normalizedIconKey(forName:) -> String? — the single normalisation rule (trim + lowercase, nil when blank) that 22-02's device-local cache keys on"
  - "PantryCategoryTests — totality, closed-set, raw-value rejection and legacy-parity coverage"
affects: [22-02, 22-03, 22-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Invalid states designed out, not tested for: the model names a CATEGORY; Swift owns symbol selection, so a fake SF Symbol is unrepresentable by any caller"
    - "Exhaustive switch with NO default: as a compile-time totality guarantee for a presentation table"
    - "nil vs .other — the keyword layer reports 'no opinion' separately from 'genuinely miscellaneous', leaving fallback policy to the caller"
    - "One normalisation function shared by matcher and cache, so a cache hit and a keyword match can never disagree"

key-files:
  created:
    - MyHomeApp/Features/Kitchen/PantryCategory.swift
    - MyHomeTests/PantryCategoryTests.swift
  modified:
    - MyHomeApp/Features/Kitchen/KitchenLogic.swift
    - MyHomeTests/KitchenLogicTests.swift
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "P22-D1 honoured: all 17 AI-SPEC 3 cases ship, named exactly as specified"
  - "P22-D2 honoured: PantryCategory is a plain enum — no @available, no FoundationModels import; the @Generable twin lands in 22-02"
  - "frozen/cleaning share catUtilities and petSupplies/other share catOther; the palette has no further category tokens and the symbol carries the distinction — documented in-file so a later reader does not 'fix' it"
  - "The salt/sugar/masala rule now yields .spice rather than .grainStaple; both map to shippingbox.fill + catPantryGrain, so the tile is byte-identical while the model path can tell a spice from a staple"

metrics:
  duration: ~35 min
  completed: 2026-07-22
---

# Phase 22 Plan 01: PantryCategory + Total Presentation Table Summary

A closed 17-case `PantryCategory` enum now owns every SF Symbol string in the Kitchen feature, and the existing keyword table routes through it — no shipped tile changed appearance.

## What Was Built

**`MyHomeApp/Features/Kitchen/PantryCategory.swift`** — `enum PantryCategory: String, CaseIterable, Sendable` with the 17 AI-SPEC cases and explicit raw values (stable cache format for 22-02). `static func presentation(for:) -> (symbol: String, color: Color)` is an exhaustive `switch` with **no `default:` clause** — that omission is the ICON-02 guarantee: adding an eighteenth case later is a build failure, not a silently blank tile. An instance-property convenience `var presentation` forwards to it. The file has no `@available` attribute and does not import `FoundationModels`, per P22-D2, so the fallback path compiles and works wherever the app runs.

**`KitchenLogic` icon section, refactored** — `IconRule` now holds `keywords: [String]` and `category: PantryCategory`; its `symbol` and `color` fields are gone, so `PantryCategory.presentation` is the only place a symbol string is written. Keyword arrays and rule order are verbatim from 20-03. `icon(forName:)` keeps its exact signature and outputs and is now one line: `keywordCategory(forName:)?.presentation ?? PantryCategory.other.presentation`. The private `fallbackIcon` constant is deleted. Two new internal seams: `keywordCategory(forName:)` (nil = "no opinion", for 22-03's resolver) and `normalizedIconKey(forName:)` (the one normalisation rule, for 22-02's cache).

## Candidate Symbols for 22-04's Screenshot Pass

These six are the NEW categories and have **not** been rendered yet. A non-existent SF Symbol draws nothing and raises no error (the 20-03 `takeoutbag.fill.and.rectangle.portrait` bug), so 22-04 must eyeball each of these in the icon gallery and substitute any that comes up empty:

| Category | Candidate symbol | Colour token |
|---|---|---|
| paperDisposable | `scroll.fill` | catShopping |
| personalCare | `hands.sparkles.fill` | catHealth |
| condiment | `fork.knife` | catDining |
| frozen | `snowflake` | catUtilities |
| petSupplies | `pawprint.fill` | catOther |
| other | `bag.fill` | catOther (already shipping — verified) |

The other eleven (`drop.fill`, `oval.fill`, `shippingbox.fill` ×2, `leaf.fill`, `basket.fill`, `cup.and.saucer.fill`, `drop.circle.fill`, `birthday.cake.fill`, `waterbottle.fill`, `bubbles.and.sparkles.fill`) are already shipping and verified — 22-04 need only confirm they did not drift.

## Verification

- `PantryCategoryTests` — 9 tests: closed 17-case set and exact raw values, unknown-raw-value rejection (incl. case sensitivity), totality (non-empty, whitespace-free symbol for every `allCases` element), static/instance agreement, distinct symbols for the colour-sharing pairs, `.other` → `bag.fill`, and the eleven legacy symbol AND colour pairings.
- `KitchenLogicTests` — the three pre-existing icon tests (`iconRulesMatchMockupItems`, `iconMatchingIsCaseInsensitive`, `iconFallback`) pass **unedited**; that is the non-regression proof. Five tests added for `keywordCategory` and `normalizedIconKey`.
- Full suite, serially: **666 tests in 91 suites passed** (`-parallel-testing-enabled NO`).
- `git diff` against the branch point touches only `PantryCategory.swift`, `KitchenLogic.swift`, the two test files and `project.pbxproj`. No `DesignTokens.swift` change, no `Persistence/`, no `Sync/`, no `SchemaV11` — icons stay derived and unsynced (ICON-03).
- `grep -n 'symbol:' KitchenLogic.swift` returns only the two `icon(...)` return-type annotations; no `IconRule` symbol literals remain.

## TDD Gate Compliance

Both tasks ran RED → GREEN. Task 1: `ed8c468` (test, compile-failure RED) → `64a3f7e` (feat). Task 2: `5a384dc` (test, compile-failure RED) → `5ac5992` (feat). No REFACTOR commit was needed — task 2 *is* the refactor and is covered by the untouched pinned tests.

## Deviations from Plan

None — plan executed as written. Two notes for the record, neither a behaviour change:

- The plan's action text says "the twelve existing rules"; there are **eleven** in `iconRules` (20-03 shipped eleven). All eleven were mapped, matching the plan's own eleven-entry category list and its eleven-entry legacy symbol table.
- pbxproj object IDs follow the repo's existing short symbolic convention (`A2201PC`/`F2201PC`, `A2201PCT`/`F2201PCT`) rather than fresh 24-hex IDs, mirroring `A2003KL`/`F2003KL` exactly as instructed. Both files are in the correct group and Sources phase — verified by the fact that the RED runs failed on *missing symbols* rather than *missing files*, and the GREEN runs compiled.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: MyHomeApp/Features/Kitchen/PantryCategory.swift
- FOUND: MyHomeTests/PantryCategoryTests.swift
- FOUND: ed8c468, 64a3f7e, 5a384dc, 5ac5992
