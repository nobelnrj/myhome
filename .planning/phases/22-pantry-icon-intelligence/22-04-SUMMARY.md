---
phase: 22-pantry-icon-intelligence
plan: 04
subsystem: kitchen
tags: [kitchen, pantry, icons, icon-01, icon-02, icon-03, eval, screenshot-evidence, swift-testing, debug-hook]

# Dependency graph
requires:
  - phase: 22-pantry-icon-intelligence
    plan: 01
    provides: PantryCategory + total presentation table, KitchenLogic.keywordCategory
  - phase: 22-pantry-icon-intelligence
    plan: 02
    provides: PantryIconCache, PantryIconClassifying, FoundationModelsPantryIconClassifier, FakePantryIconClassifier
  - phase: 22-pantry-icon-intelligence
    plan: 03
    provides: PantryIconResolver (synchronous presentation + async classifyIfNeeded)
provides:
  - "PantryIconFixture — 32-entry committed reference dataset in three groups (motivating / nonRegression / ambiguous), weighted to this household's Indian staples"
  - "PantryIconStructuralTests — 11 always-on deterministic gates: symbol totality, degradation with nil and throwing classifiers, non-regression parity, no icon state on PantryItem/PantryItemDTO/canonical snapshot bytes"
  - "PantryIconEvalTests — opt-in model accuracy suite, gated on TEST_RUNNER_PANTRY_ICON_EVAL=1, so a flaky classification can never redden a routine run"
  - "PantryIconGalleryView — DEBUG -iconGallery screen rendering all 17 tiles beside their literal symbol strings"
  - "Light + dark gallery screenshots as durable phase evidence"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Eval split by determinism, not by importance: deterministic gates block, model accuracy is explicitly invoked (AI-SPEC 5.2)"
    - "Literal symbol string printed beside each tile — a blank square becomes diagnostic instead of merely alarming"
    - "Launch-argument root swap for screenshot verification, since simctl cannot navigate the app"
    - "No-leakage asserted three ways: Mirror over the @Model, Mirror over the exported DTO, and substring scan of the canonical snapshot bytes"

key-files:
  created:
    - MyHomeTests/PantryIconFixture.swift
    - MyHomeTests/PantryIconStructuralTests.swift
    - MyHomeTests/PantryIconEvalTests.swift
    - MyHomeApp/Features/Kitchen/PantryIconGalleryView.swift
    - .planning/phases/22-pantry-icon-intelligence/22-04-light-icon-gallery.png
    - .planning/phases/22-pantry-icon-intelligence/22-04-dark-icon-gallery.png
  modified:
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "bournvita -> beverage, not brew: brew is reserved for tea leaves and coffee grounds; documented in the fixture as a taxonomy preference to revisit, not a defect"
  - "baby wipes -> personalCare, not paperDisposable: intended use wins over material; paperDisposable stays for kitchen roll, foil and napkins"
  - "Zero symbol substitutions — all six unverified Phase 22 candidates render in both themes"
  - "The eval suite needs the TEST_RUNNER_ prefix; a bare PANTRY_ICON_EVAL=1 leaves it silently skipped, which looks exactly like a pass"

metrics:
  duration: ~40 min
  completed: 2026-07-22
---

# Phase 22 Plan 04: Eval Fixture, Structural Gates and the Icon Gallery Summary

All 17 pantry tiles are now confirmed to render on a real simulator in both themes, the deterministic guarantees are always-on tests, and the model's accuracy is measurable on demand — which is how we discovered the on-device model classifies this household's vocabulary far worse than the 90% threshold.

## What Was Built

**`MyHomeTests/PantryIconFixture.swift`** — `enum PantryIconFixture` with 32 entries in three MARKed groups. `motivating` (6) are the names that caused the phase; `nonRegression` (10) are exposed separately because they carry the stricter 100% threshold; `ambiguous` (16) records the accepted answer for the close calls plus this household's staples (rava, poha, jaggery, curry leaves, coconut, tamarind, mustard seeds, idli batter). The two genuinely close tie-breaks — bournvita and baby wipes — carry their rationale in comments, so a future disagreement is a decision to revisit rather than a bug to chase.

**`MyHomeTests/PantryIconStructuralTests.swift`** — 11 always-on deterministic tests: every `PantryCategory` yields a non-empty, whitespace-free, non-path symbol; static and instance accessors agree; the fixture only names real categories; a `nil`-classifier resolver answers every fixture name with a real tile and writes nothing to the cache; that answer is exactly the keyword-or-neutral answer; a throwing classifier changes no tile and caches nothing; every non-regression name keeps its pre-Phase-22 symbol through both `keywordCategory` and the shipped `KitchenLogic.icon(forName:)`; `PantryItem` exposes no property containing symbol/icon/colour; the exported `PantryItemDTO` exposes none either, the canonical snapshot bytes contain no such key, and none of the 17 symbol strings appears anywhere in the payload; and classifying an item leaves `updatedAt` untouched and the model context clean, so an icon can never sync (ICON-03).

**`MyHomeTests/PantryIconEvalTests.swift`** — the accuracy suite, `@Suite(..., .enabled(if: ProcessInfo.processInfo.environment["PANTRY_ICON_EVAL"] == "1"))`. Three tests: overall ≥ 90%, non-regression 100%, and motivating names leaving the neutral bag. Each prints the full name → expected → actual miss table, which matters more than usual here because a rerun produces different misses. It classifies the **normalised** key, mirroring what the resolver actually sends.

**`MyHomeApp/Features/Kitchen/PantryIconGalleryView.swift`** — entirely inside `#if DEBUG`. A `LazyVGrid` over `PantryCategory.allCases` drawing the same `IconTile(size: 38, cornerRadius: 11)` the rows use, with the category name and the **raw symbol string** beneath it, on `DesignTokens.bgCanvas`. `RootView.body` was split: with `-iconGallery` present it returns the gallery, otherwise the new `mainContent` (the untouched `TabView`). Both the view and the call site are DEBUG-only (T-22-10).

## Screenshot Evidence — zero substitutions

- `.planning/phases/22-pantry-icon-intelligence/22-04-light-icon-gallery.png`
- `.planning/phases/22-pantry-icon-intelligence/22-04-dark-icon-gallery.png`

Both captured on the booted iPhone 17 (iOS 26.5) and **inspected before being handed over**. All 17 tiles show a glyph in both appearances. The six candidates 22-01 flagged as unverified — `scroll.fill` (paperDisposable), `hands.sparkles.fill` (personalCare), `fork.knife` (condiment), `snowflake` (frozen), `pawprint.fill` (petSupplies) and the already-shipping `bag.fill` (other) — all render. **No symbol was substituted, so there is no rejected name to record.** The eleven legacy symbols are unchanged and still render.

## Measured Eval Accuracy — BELOW THRESHOLD

Run: `TEST_RUNNER_PANTRY_ICON_EVAL=1 xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:MyHomeTests/PantryIconEvalTests`, on the **simulator**, 2026-07-22.

| Dimension | Threshold | Measured | Verdict |
|---|---|---|---|
| Overall fixture accuracy | ≥ 90% | **37.5%** (12/32) | FAIL |
| Non-regression accuracy | 100% | **60%** (6/10) | FAIL |
| Motivating names off the neutral bag | all 6 | 5/6 (`aluminium foil` → other) | FAIL |

Representative misses: `milk` → other, `sugar` → paperDisposable, `filter coffee` → cleaning, `cooking oil` → cleaning, `toor dal` → other, `atta` → other. These are not near-misses or defensible alternatives — they are close to arbitrary, which is itself the diagnostic signal. The most likely explanation is that the simulator's on-device model is a reduced stand-in rather than the model shipping on the two target phones; the second possibility is that the guided-generation prompt (22-02) needs per-case `@Guide` descriptions, because bare camelCase case names like `grainStaple` and `oilFat` carry little semantic signal.

**This does not affect what the user sees today.** The resolver only ever *upgrades* a tile after the keyword table has already drawn one, and a wrong classification is a wrong icon, never a blank one or a crash — the structural gates prove that, and they are green. But it does mean **ICON-01's headline claim is currently unproven**, and the honest reading is that it fails on the simulator. Deciding what to do — rerun on a real iPhone 17 Pro Max before believing the number, add `@Guide` descriptions to `GeneratedPantryCategory`, or accept keyword-first ordering — is a phase-level call for the user, not an in-plan auto-fix. It is raised at the checkpoint rather than papered over.

## Verification

- **Full suite serially: 715 tests in 96 suites passed** (`-parallel-testing-enabled NO`), up from 701 at the end of 22-03. `** TEST SUCCEEDED **`.
- The eval suite reports as *skipped* on a routine run — confirmed by running it without the flag before running it with one.
- `git diff --stat` across the phase touches nothing under `MyHomeApp/Models/`, no `Schema*` file, no `Sync*` file and no `DesignTokens.swift`.
- The three pinned `KitchenLogicTests` icon tests remain unedited and green.

## TDD Gate Compliance

Task 1 ran RED → GREEN. RED `3aab019` (test): the two suites landed with their pbxproj entries and the build failed on the missing `PantryIconFixture.swift` — the 22-01/22-02 compile-failure convention. GREEN `4486871` (feat): the fixture, structural suite green. Task 2 is a DEBUG-only verification surface with no behaviour to test-drive; it is covered by the full-suite run and the screenshots (`9ae2f18`).

## Deviations from Plan

**1. [Rule 3 - Blocking] The eval opt-in variable needs a `TEST_RUNNER_` prefix**
- **Found during:** Task 1, first opt-in invocation
- **Issue:** The plan (and the file's original doc comment) assumed `PANTRY_ICON_EVAL=1 xcodebuild test …` would enable the suite. xcodebuild does not forward the host process environment into the simulator test runner, so the suite stayed skipped and the run reported a clean pass — a false green, and the most dangerous kind, since a skipped eval looks identical to a passing one.
- **Fix:** Invoke with `TEST_RUNNER_PANTRY_ICON_EVAL=1` (xcodebuild strips the prefix when forwarding). The suite's `.enabled(if:)` predicate is unchanged; the file header now documents the prefix and why a bare variable is a silent no-op.
- **Files modified:** `MyHomeTests/PantryIconEvalTests.swift`
- **Commit:** `4486871`

**2. [Rule 3 - Blocking] `RootView.body` split into `body` + `mainContent`**
- **Found during:** Task 2
- **Issue:** The plan says to wire the hook "mirroring the existing `-startTab` hook style exactly", but `-startTab` is a `@State` initialiser, not a view swap. There is no way to conditionally replace the root content from inside a `@State` default.
- **Fix:** `body` became a `#if DEBUG` if/else over `PantryIconGalleryView.isRequested`, delegating to a new `@ViewBuilder private var mainContent` holding the previous body verbatim. The `TabView` and every modifier on it are byte-identical; in a Release build `body` compiles to `mainContent` alone.
- **Files modified:** `MyHomeApp/RootView.swift`
- **Commit:** `9ae2f18`

Note for the record, not a behaviour change: the plan's fixture spec listed `""` among the eval cases. A blank name never reaches the model in production — the resolver short-circuits it — so the eval helper scores it as a hit by construction rather than sending an empty prompt.

## Known Stubs

None.

## Checkpoint Status

**Task 3 (human-verify, blocking) is PENDING.** Not self-approved. The two screenshots and the eval figures above are what the user is being asked to rule on, in particular whether the 37.5% simulator accuracy warrants a device rerun or a prompt change before the phase closes.

## Self-Check: PASSED

- FOUND: MyHomeTests/PantryIconFixture.swift
- FOUND: MyHomeTests/PantryIconStructuralTests.swift
- FOUND: MyHomeTests/PantryIconEvalTests.swift
- FOUND: MyHomeApp/Features/Kitchen/PantryIconGalleryView.swift
- FOUND: .planning/phases/22-pantry-icon-intelligence/22-04-light-icon-gallery.png
- FOUND: .planning/phases/22-pantry-icon-intelligence/22-04-dark-icon-gallery.png
- FOUND: 3aab019, 4486871, 9ae2f18
