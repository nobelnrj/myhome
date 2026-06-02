---
phase: 07-bank-parsers-ingestion-pipeline
plan: "03"
subsystem: ingestion-helpers
tags: [swift, tdd, green, merchant-normalization, confidence-scoring, dedup, dismissed-ids]
dependency_graph:
  requires: [07-01, 07-02]
  provides: [MerchantNormalizer, ConfidenceScorer, DedupChecker, DismissedMessageStore]
  affects: [07-05, 07-06]
tech_stack:
  added: []
  patterns: [pure-struct static-func (mirrors BudgetCalculator), caller-supplies-array, App Group UserDefaults Set<String> round-trip]
key_files:
  created:
    - MyHomeApp/Features/Ingestion/MerchantNormalizer.swift
    - MyHomeApp/Features/Ingestion/ConfidenceScorer.swift
    - MyHomeApp/Features/Ingestion/DedupChecker.swift
    - MyHomeApp/Features/Ingestion/DismissedMessageStore.swift
  modified:
    - MyHomeTests/MerchantNormalizerTests.swift
    - MyHomeTests/ConfidenceScorerTests.swift
    - MyHomeTests/DedupCheckerTests.swift
    - MyHome.xcodeproj/project.pbxproj
key_decisions:
  - "DedupChecker made internal (not public) because Expense @Model is internal — Swift 6 strict concurrency forbids a public method whose parameter uses an internal type"
  - "MerchantSeedEntry made Sendable so static let seed dictionary satisfies Swift 6 global mutable-state rule"
  - "Travel merchants (IRCTC/MakeMyTrip/Goibibo) mapped to Misc — no Travel category in v1 seed list"
  - "DismissedMessageStore left for controller-level integration tests in plan 06 per plan spec"
requirements-completed: [ING-12, ING-14, ING-15]
duration: 25
completed: "2026-06-02"
---

# Phase 7 Plan 03: MerchantNormalizer / ConfidenceScorer / DedupChecker / DismissedMessageStore (GREEN) Summary

Four pure-logic ingestion helpers GREENed via TDD: 29-entry merchant seed table with longest-key-wins, 0.85-threshold confidence scorer with field-weight formula, amount+merchant+date±1day dedup checker, and App Group UserDefaults dismissed-message-ID store.

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-06-02
- **Tasks:** 2 completed
- **Files created:** 4
- **Files modified:** 4

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | MerchantNormalizer + ConfidenceScorer (GREEN) | 0fa5b24 | MerchantNormalizer.swift, ConfidenceScorer.swift, MerchantNormalizerTests.swift, ConfidenceScorerTests.swift, pbxproj |
| 2 | DedupChecker + DismissedMessageStore (GREEN) | 4f2fe9c | DedupChecker.swift, DismissedMessageStore.swift, DedupCheckerTests.swift |

## What Was Built

**MerchantNormalizer** (`MyHomeApp/Features/Ingestion/MerchantNormalizer.swift`):
- `MerchantSeedEntry: Sendable` value type with `normalizedName` + `categoryHint?`
- `MerchantNormalizer.seed` — 29-entry static dictionary covering e-commerce (Amazon/Flipkart/Myntra/Nykaa), food delivery (Zomato/Swiggy), grocery/quick-commerce (BigBasket/Blinkit/Zepto/Instamart), rides (Uber/Ola/Rapido), fuel (HPCL/BPCL/Indian Oil), streaming (Netflix/Spotify/Hotstar/JioCinema), travel (IRCTC/MakeMyTrip/Goibibo → Misc), health (Apollo/MedPlus), UPI payments (PhonePe/GPay/Paytm)
- `normalize(_ rawMerchant:)` — UPPERCASE input, sort keys by length descending, first `contains` hit wins; raw passthrough + nil hint for unknowns
- All 6 tests GREEN: Amazon, Zomato, longest-key-wins, unknown passthrough, Swiggy, Uber

**ConfidenceScorer** (`MyHomeApp/Features/Ingestion/ConfidenceScorer.swift`):
- `ConfidenceScorer.score(_ result:)` = `fingerprintScore * 0.5 + extractionScore * 0.5`
- `computeExtractionScore`: amount(0.40) + date(0.25, always) + merchant(0.20) + card(0.15)
- `autoSaveThreshold = 0.85` public constant
- 4 tests GREEN: full-field ≥0.85, missing-card-only ≥0.85 (score 0.925), missing-amount <0.85 (score 0.80), partial-fingerprint <0.85 (score 0.55)

**DedupChecker** (`MyHomeApp/Features/Ingestion/DedupChecker.swift`):
- `findDuplicate(of:in:) -> Expense?` — caller supplies `[Expense]` array (no internal SwiftData fetch)
- Match rule: `existing.amount == candidate.amount` AND case-insensitive merchant substring overlap (each `contains` the other) AND `|date delta| ≤ 86400 s`
- Guard: empty `normalizedMerchant` never matches
- 4 tests GREEN: exact match, outside-1-day nil, different-amount nil, different-merchant nil

**DismissedMessageStore** (`MyHomeApp/Features/Ingestion/DismissedMessageStore.swift`):
- `isDismissed(_ messageID:)`, `dismiss(_ messageID:)`, `dismissed() -> Set<String>`
- Key `"gmail_dismissed_message_ids"` in App Group UserDefaults `"group.com.reojacob.myhome"`
- `Set<String>` ↔ `[String]` round-trip via `stringArray(forKey:)` / `set(Array(set), forKey:)`
- Exercised by controller integration tests in plan 06 (per plan spec)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DedupChecker access level: public method with internal parameter**
- **Found during:** Task 1 build (after registering DedupChecker in pbxproj before writing its body)
- **Issue:** `public static func findDuplicate(of:in:)` takes `[Expense]` which is `internal` — Swift 6 strict concurrency rejects this.
- **Fix:** Dropped `public` modifier from `DedupChecker` struct and `findDuplicate` method. All callers (`GmailSyncController`, tests) are in the same module so `internal` access is correct.
- **Files modified:** `DedupChecker.swift`
- **Commit:** 4f2fe9c

**2. [Rule 1 - Bug] MerchantSeedEntry Sendable violation on static let seed**
- **Found during:** Task 1 build
- **Issue:** `static let seed: [String: MerchantSeedEntry]` failed Swift 6 actor-isolation check because `MerchantSeedEntry` was not declared `Sendable`.
- **Fix:** Added `: Sendable` conformance to `MerchantSeedEntry`. The struct has only immutable `let` properties of `Sendable` types, so the conformance is trivially correct.
- **Files modified:** `MerchantNormalizer.swift`
- **Commit:** 0fa5b24

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `DismissedMessageStore` not exercised by unit tests in this plan | `DismissedMessageStore.swift` | Per plan spec: exercised by GmailSyncControllerTests in plan 06 |

## Threat Surface

T-07-05 accepted: DismissedMessageStore uses non-security App Group UserDefaults — worst case a dismissed email re-surfaces; no data/security impact.
T-07-06 accepted: DedupChecker reads in-process expense data already behind the Face ID gate; no egress.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| MerchantNormalizer.swift exists | FOUND |
| ConfidenceScorer.swift exists | FOUND |
| DedupChecker.swift exists | FOUND |
| DismissedMessageStore.swift exists | FOUND |
| MerchantNormalizerTests all pass | CONFIRMED (6/6) |
| ConfidenceScorerTests all pass | CONFIRMED (4/4) |
| DedupCheckerTests all pass | CONFIRMED (4/4) |
| Task 1 commit 0fa5b24 | FOUND |
| Task 2 commit 4f2fe9c | FOUND |
| BUILD SUCCEEDED | CONFIRMED |
