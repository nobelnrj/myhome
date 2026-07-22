---
phase: 22-pantry-icon-intelligence
plan: 02
subsystem: kitchen
tags: [kitchen, pantry, icons, icon-01, icon-03, foundation-models, on-device-ai, userdefaults, swift-testing]

# Dependency graph
requires:
  - phase: 22-pantry-icon-intelligence
    plan: 01
    provides: PantryCategory (17 cases, ungated), PantryCategory.presentation, KitchenLogic.normalizedIconKey, KitchenLogic.keywordCategory
  - phase: 16-ai-insight-card
    provides: InsightService.swift — the in-repo FoundationModels reference (availability switch, @Generable, fresh-session-per-call, protocol seam around a final type)
provides:
  - "PantryIconCache — device-local, App-Group-UserDefaults, normalised, 300-entry LRU-capped name→PantryCategory memory; injectable defaults; nothing added to PantryItem, SchemaV11 or any sync DTO (ICON-03)"
  - "protocol PantryIconClassifying: Sendable { func classify(name: String) async throws -> PantryCategory } — availability-FREE seam, the only type 22-03's resolver depends on"
  - "GeneratedPantryCategory — @available(iOS 26,*) @Generable twin of PantryCategory with .asPantryCategory, pinned to the plain enum by a parity test (P22-D2)"
  - "PantryIconPromptBuilder — systemInstructions + buildPrompt(for:), injects only the trimmed 80-char-capped item name (T-22-03/T-22-04)"
  - "FoundationModelsPantryIconClassifier — fresh LanguageModelSession per call, GenerationError left uncaught for 22-03"
  - "isPantryIconClassificationAvailable(_:) — exhaustive availability helper mirroring isInsightAvailable"
  - "FakePantryIconClassifier — internal test fixture in MyHomeTests/PantryIconClassifierTests.swift, reused by 22-03"
affects: [22-03, 22-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Protocol seam around a final SDK type (LanguageModelSession) — the Phase 16 InsightGenerating pattern, repeated"
    - "Availability-free protocol over an iOS-26-only implementation, so downstream view-model code and its tests need no @available gate"
    - "Two-enum mirror pinned by a parity test: @Generable cannot be conditional, so the gated twin is separate and a forgotten case is a test failure rather than an unreachable category"
    - "Closed output enum as a structural prompt-injection defence — the worst an injected name can do is change which of 17 icons is drawn"
    - "Reads never write: cache lookups do not touch recency, so pantry row rendering never hits UserDefaults with a write"

key-files:
  created:
    - MyHomeApp/Features/Kitchen/PantryIconCache.swift
    - MyHomeApp/Features/Kitchen/PantryIconClassifier.swift
    - MyHomeTests/PantryIconCacheTests.swift
    - MyHomeTests/PantryIconClassifierTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "P22-D2 honoured: GeneratedPantryCategory is a separate iOS-26-only @Generable twin; parity test pins its raw-value set to PantryCategory"
  - "P22-D3 honoured: App-Group UserDefaults (group.com.reojacob.myhome), two plist-safe keys, 300-entry LRU cap — not a SwiftData model"
  - "PantryIconCache is @unchecked Sendable, not Sendable — UserDefaults is not formally Sendable; the struct holds only an immutable reference to one and no mutable state of its own"
  - "PantryIconPromptBuilder.buildPrompt emits no digits at all, pinned by a test — nothing numeric belongs in a single-name classification prompt"

metrics:
  duration: ~30 min
  completed: 2026-07-22
---

# Phase 22 Plan 02: PantryIconCache + PantryIconClassifying Seam Summary

The two device-local pieces 22-03 needs now exist: a normalised, capped, App-Group-backed name→category memory, and a mockable classification seam over Apple's on-device model — no UI, no schema change, no network.

## What Was Built

**`MyHomeApp/Features/Kitchen/PantryIconCache.swift`** — `struct PantryIconCache: @unchecked Sendable` with an injectable `let defaults: UserDefaults` defaulting to the app group, exactly as `DismissedMessageStore` does. Two plain plist values: `pantry_icon_categories` (`[String: String]`, normalised name → `PantryCategory.rawValue`) and `pantry_icon_recency` (`[String]`, oldest-first). API is `category(forName:)`, `store(_:forName:)`, `removeAll()`, `count`, plus `static let maxEntries = 300`. Every entry point normalises through `KitchenLogic.normalizedIconKey`, so a cache hit and a keyword match can never disagree, and a blank/nil name is a no-op that can never occupy a slot. Reads go through `PantryCategory(rawValue:)` — a renamed category or a hand-edited plist yields `nil` and falls back, never crashes (T-22-05). Reads do not touch recency, deliberately: row rendering must not write to `UserDefaults`.

**`MyHomeApp/Features/Kitchen/PantryIconClassifier.swift`** — four declarations:

- `protocol PantryIconClassifying: Sendable` with `func classify(name: String) async throws -> PantryCategory`. **No `@available`** — it traffics only in the ungated `PantryCategory`, which is what keeps 22-03's resolver and its tests free of iOS-26 gating.
- `@available(iOS 26, *) @Generable enum GeneratedPantryCategory: String, CaseIterable` — the 17-case twin with `var asPantryCategory: PantryCategory?`.
- `@available(iOS 26, *) enum PantryIconPromptBuilder` — `systemInstructions` (classify one household item name, pick the single best fit, anything unrecognisable is `other`) and `buildPrompt(for:)` which trims, truncates to 80 chars, and wraps the name in one line. The name is the only datum.
- `@available(iOS 26, *) final class FoundationModelsPantryIconClassifier` — fresh `LanguageModelSession` per `classify` call, `respond(to:generating: GeneratedPantryCategory.self)`, `?? .other`. `GenerationError` is **not** caught here.
- `@available(iOS 26, *) func isPantryIconClassificationAvailable(_:)` — exhaustive over all three `UnavailableReason` cases plus `@unknown default`.

## For 22-03: the exact `FakePantryIconClassifier` signature

Declared at file scope in `MyHomeTests/PantryIconClassifierTests.swift` (`internal`, under its own MARK) — do not redeclare it:

```swift
final class FakePantryIconClassifier: PantryIconClassifying, @unchecked Sendable {
    var result: Result<PantryCategory, Error> = .success(.other)   // settable
    private(set) var callCount = 0
    private(set) var lastName: String?
    func classify(name: String) async throws -> PantryCategory     // contains `await Task.yield()`
}

enum FakeClassificationError: Error { case guardrailViolation }    // same file, for the throw path
```

`Task.yield()` inside `classify` is what lets 22-03 assert cancellation propagation. Because `PantryIconClassifying` is availability-free, neither the fake nor its tests need `@available`.

## Verification

- `PantryIconCacheTests` — 11 tests: normalisation (incl. agreement with `KitchenLogic.normalizedIconKey`), miss on unknown name, blank/nil no-op, tampered raw value → nil, 305-store eviction leaving exactly 300 with `item-0…4` gone and `item-5`/`item-304` present, re-store refreshing recency without growth, reads not mutating, `removeAll`, cross-instance persistence, and all 17 categories round-tripping.
- `PantryIconClassifierTests` — 12 tests: enum parity (raw-value sets equal, count 17), every twin case mapping across, all four availability branches, prompt contains the name, prompt contains no digits and none of `quantity/litre/unit/₹/rupee/spend/budget/account`, 400-char name truncated to exactly 80, padded name trimmed, instructions mention `other`, fake returns/throws, and a protocol-typed value used without an availability gate.
- **Full suite serially: 689 tests in 93 suites passed** (`-parallel-testing-enabled NO`), up from 666 at the end of 22-01.
- `git diff --name-only 98ef353..HEAD` matches nothing under `Persistence/`, `Sync/`, or any `Schema` file — ICON-03 structurally held. The only touched files are the four new ones plus `project.pbxproj`.
- `grep -rn "URLSession" MyHomeApp/Features/Kitchen/` matches only the comment in `PantryIconClassifier.swift` documenting its absence — no call site.

## TDD Gate Compliance

Both tasks ran RED → GREEN with compile-failure REDs (the 22-01 convention: the pbxproj entry lands with the test, so the missing implementation file is the RED). Task 1: `2083fb8` (test) → `d69dbfe` (feat). Task 2: `0b656ce` (test) → `ef36ded` (feat). No REFACTOR commit was needed.

## Deviations from Plan

**1. [Rule 3 - Blocking] `PantryIconCache` is `@unchecked Sendable`, not `Sendable`**
- **Found during:** Task 1 GREEN
- **Issue:** The plan specifies `struct PantryIconCache: Sendable`, but `UserDefaults` is not `Sendable`, so a stored `let defaults: UserDefaults` is a hard compile error: *"stored property 'defaults' of 'Sendable'-conforming struct has non-Sendable type 'UserDefaults'"*.
- **Fix:** Declared `@unchecked Sendable` with an in-file justification — `UserDefaults` is documented thread-safe, the only stored property is an immutable reference to one, and the struct holds no mutable state. The alternative (static accessors, as `DismissedMessageStore` uses) was rejected because it would forfeit the injectability the plan's test isolation requires.
- **Files modified:** `MyHomeApp/Features/Kitchen/PantryIconCache.swift`
- **Commit:** `d69dbfe`

Note for the record, not a behaviour change: `PantryIconCache.categoriesKey` and `recencyKey` are `internal` rather than `private` so the T-22-05 test can seed a deliberately-corrupted persisted value; the plan did not specify their access level.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: MyHomeApp/Features/Kitchen/PantryIconCache.swift
- FOUND: MyHomeApp/Features/Kitchen/PantryIconClassifier.swift
- FOUND: MyHomeTests/PantryIconCacheTests.swift
- FOUND: MyHomeTests/PantryIconClassifierTests.swift
- FOUND: 2083fb8, d69dbfe, 0b656ce, ef36ded
