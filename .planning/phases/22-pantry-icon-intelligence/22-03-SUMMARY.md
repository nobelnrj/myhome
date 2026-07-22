---
phase: 22-pantry-icon-intelligence
plan: 03
subsystem: kitchen
tags: [kitchen, pantry, icons, icon-01, icon-03, foundation-models, observable, swiftui, non-blocking, swift-testing]

# Dependency graph
requires:
  - phase: 22-pantry-icon-intelligence
    plan: 01
    provides: PantryCategory + presentation table, KitchenLogic.keywordCategory, KitchenLogic.normalizedIconKey
  - phase: 22-pantry-icon-intelligence
    plan: 02
    provides: PantryIconCache, PantryIconClassifying seam, FoundationModelsPantryIconClassifier, isPantryIconClassificationAvailable, FakePantryIconClassifier
  - phase: 16-ai-insight-card
    provides: the shipped #available(iOS 26, *) + runtime-availability gating pattern
provides:
  - "PantryIconResolver — @MainActor @Observable bridge: synchronous presentation(forName:)/presentation(for:) plus non-throwing async classifyIfNeeded(name:)"
  - "PantryIconResolver.shared — availability decided ONCE at construction; one instance across both lists, so a shared name is classified exactly once (P22-D6)"
  - "PantryIconResolverTests — 12 tests incl. the structural non-blocking proof (callCount == 0 after a presentation lookup)"
  - "PantryItemRow and ShoppingRow drawing tiles through the resolver with .task(id: name) lazy classification (P22-D4)"
affects: [22-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Non-blocking guarantee proved structurally, not by timing: the render path asserts the classifier's callCount stays 0, so inference is unreachable from a draw rather than merely fast"
    - "Split observation — hot-path memoisation lives in @ObservationIgnored storage; a single observed `revision` counter is the redraw signal, so a cache memo written mid-body is not a state write during view update"
    - "Catch-and-fall-back owned by the resolver, not the classifier: classifyIfNeeded is non-throwing so no view has an error to handle"
    - "In-flight Set coalescing needs no lock because the class is @MainActor"
    - ".task(id: item.name) as the lazy trigger — rename reclassifies, SwiftUI cancels the superseded task, cache hit makes recycling free"

key-files:
  created:
    - MyHomeApp/Features/Kitchen/PantryIconResolver.swift
    - MyHomeTests/PantryIconResolverTests.swift
  modified:
    - MyHomeApp/Features/Kitchen/PantryItemRow.swift
    - MyHomeApp/Features/Kitchen/ShoppingRow.swift
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "P22-D4 honoured: classification triggers lazily on first render via .task(id:), never on item creation"
  - "P22-D6 honoured: PantryIconResolver.shared read directly in body, no @Environment plumbing; tests always construct their own instance"
  - "resolved/inFlight/classifier/cache are @ObservationIgnored and a private `revision: Int` is the only observed property — avoids a 'modifying state during view update' write-back from the mid-body cache memo (deviation 1)"
  - "The NORMALISED key is what goes to the model and to the cache, so a cache hit and a classification can never disagree about which name was asked about"
  - "ShoppingRow's .task is attached to the outer HStack over a `derivedItemName` computed property (nil for manual extras) — derivedBody is a multi-view @ViewBuilder with no single view to attach to (deviation 2)"

metrics:
  duration: ~30 min
  completed: 2026-07-22
---

# Phase 22 Plan 03: PantryIconResolver + Row Rewiring Summary

Pantry and shopping rows now draw their tile synchronously from cache-or-keywords and upgrade in place when the on-device model lands — with the non-blocking guarantee pinned as a structural test rather than a timing one.

## What Was Built

**`MyHomeApp/Features/Kitchen/PantryIconResolver.swift`** — `@MainActor @Observable final class PantryIconResolver`, dependencies injected (`classifier: PantryIconClassifying?`, `cache: PantryIconCache`) and defaulted for production.

- `presentation(forName:)` / `presentation(for item:)` are **not `async`, contain no `await`, and never touch `classifier`**. Resolution order is AI-SPEC §4.2 exactly: in-memory `resolved` → `cache.category(forName:)` (memoised) → `KitchenLogic.keywordCategory` → `.other`. The tile is therefore never empty on any device, with Apple Intelligence on, off, ineligible or downloading.
- `classifyIfNeeded(name:)` is **non-throwing by design** — no call site needs a `try` and no view has an error to render. It returns immediately on a blank name, a nil classifier, an already-resolved/cached key, or an in-flight key; otherwise it inserts into `inFlight` (`defer`-removed), awaits the classifier inside a `do/catch` that swallows every error, checks `Task.isCancelled` before writing, then writes cache + `resolved` and bumps `revision`.
- `static let shared` decides availability **once** at construction via `#available(iOS 26, *)` + `isPantryIconClassificationAvailable(SystemLanguageModel.default.availability)` — the shipped `AnalyticsView`/`InsightService` pattern. `nil` classifier = model unavailable, which is also how the tests exercise the degraded path with no device.

**`PantryItemRow`** — `KitchenLogic.icon(for: item)` replaced by `PantryIconResolver.shared.presentation(for: item)`, fed into the same `IconTile(size: 38, cornerRadius: 11)` with unchanged geometry and neumorphic treatment. `.task(id: item.name)` on the outer `HStack` triggers classification. No `ProgressView`, no redaction, no placeholder, no transition added.

**`ShoppingRow`** — the same two changes at the derived-row call site. Manual extras still carry no icon tile (20-04 mockup) and pass a `nil` name, which the resolver no-ops on. `KitchenLogic.icon(forName:)` is left in place and unchanged as the pure keyword entry point `KitchenLogicTests` pins.

## Verification

- **`PantryIconResolverTests` — 12 tests**, all green: the headline `synchronousPresentationNeverReachesTheModel` (`callCount == 0` after a presentation lookup, T-22-08), neutral tile on a cold cache, upgrade-and-persist, cache short-circuit, already-resolved short-circuit, ten-concurrent-tasks coalescing to `callCount == 1` (T-22-07), throwing classifier keeping the keyword/neutral tile with `cache.count == 0` and no propagation, nil-classifier degradation, four blank/whitespace/nil name cases, cancellation writing nothing, and case/padding normalisation parity.
- **Full suite serially: 701 tests in 94 suites passed** (`-parallel-testing-enabled NO`), up from 689 at the end of 22-02.
- `git diff --name-only 294ad1f..HEAD` matches nothing under `Persistence/`, `Sync`, `Schema`, or `Models/` — ICON-03 structurally held; only the two new files, the two rows and `project.pbxproj` changed.
- `grep -c 'KitchenLogic.icon(for:'` returns **0** for both row files.
- `grep -rn "ProgressView\|redacted" MyHomeApp/Features/Kitchen/` returns **0 matches**.
- The three pinned `KitchenLogicTests` icon tests (`iconRulesMatchMockupItems`, `iconMatchingIsCaseInsensitive`, `iconFallback`) pass **unedited**.

## TDD Gate Compliance

Task 1 ran RED → GREEN: `da11ef8` (test, compile-failure RED — "cannot find type 'PantryIconResolver' in scope") → `7bb663e` (feat). Task 2 is a call-site rewire covered by the untouched pinned tests plus the new resolver suite, so it carries no separate RED. No REFACTOR commit was needed.

## Deviations from Plan

**1. [Rule 1 - Bug] `resolved` is `@ObservationIgnored`; a separate observed `revision` counter drives the redraw**
- **Found during:** Task 1 GREEN
- **Issue:** The plan specifies `resolved` as "the observed property that drives the in-place upgrade", while also specifying that `presentation` memoises cache hits into it. But `presentation` is called *during view body evaluation*, so an observed mutation there is a "modifying state during view update" write-back — SwiftUI would invalidate the row from inside its own draw.
- **Fix:** `resolved` (and `inFlight`, `classifier`, `cache`) are `@ObservationIgnored`; a `private var revision: Int` is the sole observed property, read by `presentation` (so every drawing row subscribes) and bumped only when a classification actually lands. The cache memo therefore writes nothing observed mid-body, and the in-place upgrade still happens. The observable behaviour the plan asked for is unchanged.
- **Files modified:** `MyHomeApp/Features/Kitchen/PantryIconResolver.swift`
- **Commit:** `7bb663e`

**2. [Rule 3 - Blocking] `ShoppingRow`'s `.task` attaches to the outer `HStack` via a `derivedItemName` computed property**
- **Found during:** Task 2
- **Issue:** The plan says to apply "the identical two changes" at ShoppingRow's icon call site, but that site is inside `derivedBody`, a multi-view `@ViewBuilder` — there is no single view there to hang a `.task` on, and `item` is not in scope in `body`.
- **Fix:** Added `private var derivedItemName: String?` (the pantry name for `.derived`, `nil` for `.manual`) and attached `.task(id: derivedItemName)` to the outer `HStack` in `body`, matching `PantryItemRow`. Manual extras pass `nil`, which `classifyIfNeeded` already no-ops on.
- **Files modified:** `MyHomeApp/Features/Kitchen/ShoppingRow.swift`
- **Commit:** `c4c118c`

Note for the record, not a behaviour change: the resolver sends the **normalised** key to `classifier.classify(name:)` rather than the raw name; the plan did not specify which. This keeps the model prompt, the cache key and the keyword lookup referring to the same string.

## For 22-04

The six new-category symbols listed in the 22-01 summary are still unverified on screen. They are now reachable at runtime — a model classification of e.g. "kitchen tissue" will draw `scroll.fill`. 22-04's screenshot pass is what proves none of them renders empty.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: MyHomeApp/Features/Kitchen/PantryIconResolver.swift
- FOUND: MyHomeTests/PantryIconResolverTests.swift
- FOUND: da11ef8, 7bb663e, c4c118c
