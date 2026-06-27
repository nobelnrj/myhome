---
phase: 16-ai-insight-card
verified: 2026-06-27T00:00:00Z
status: passed
status_history:
  - status: human_needed
    note: "Live FoundationModels generation unprovable in simulator (SC-1/SC-2/SC-3)."
  - status: passed
    note: "Reconciled to passed — human on-device sign-off recorded in 16-05-SUMMARY.md (2026-06-27, all 8 steps passed on A17 Pro+); user re-confirmed 'Approved' this session. The sole blocker for human_needed is satisfied."
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Apple Intelligence live generation on A17 Pro+ device"
    expected: "Coherent on-device insight below category bars; all rupee/% figures match on-screen values; character-by-character reveal with breathing orb; Reduce Motion degrades to instant full text; Airplane mode still generates; Week→Month→Year range switch triggers fresh insight; unavailable devices see nothing after category bars"
    why_human: "iPhone 17 simulator cannot run FoundationModels generation (SC-1, SC-2, SC-3); requires physical Apple Intelligence hardware. USER SIGN-OFF RECORDED in 16-05-SUMMARY.md (2026-06-27) — all 8 steps passed on real A17 Pro+ device."
---

# Phase 16: AI Insight Card — Verification Report

**Phase Goal:** On devices with Apple Intelligence enabled, the Analytics screen surfaces
a natural-language spending insight generated entirely on-device; on every other device
the card is silently absent with zero error noise, and no rupee figure ever appears in the
insight that was not pre-computed in Swift.

**Verified:** 2026-06-27
**Status:** human_needed (live-generation behavior verified on real hardware by user; logged for audit trail)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | AI Insight card appears on Analytics screen on Apple Intelligence devices (AI-01) | VERIFIED | `AnalyticsView.swift:89-92` — `if #available(iOS 26, *)` block instantiates `AIInsightCard(summary:)`; human sign-off step 2 confirms visible card on A17 Pro+ |
| 2 | Two-layer gating — `#available(iOS 26, *)` compile-time + `SystemLanguageModel.default.availability` runtime — with all three unavailability cases mapped to `EmptyView`; no error noise (AI-02) | VERIFIED | `InsightService.swift:215-231` — exhaustive switch with `@unknown default: false`; `AIInsightCard.swift:58-65` — `isInsightAvailable()` guards `cardChrome`; returns nothing on all unavailable branches; 4 unit tests GREEN |
| 3 | Guided generation with `@Generable SpendInsight` struct; `guardrailViolation` and `exceededContextWindowSize` both route to template fallback; no error ever surfaces to UI (AI-03) | VERIFIED | `InsightService.swift:19-36` — `@Generable SpendInsight { observation, suggestion? }`; `AIInsightCard.swift:261-272` — `catch is CancellationError` then `catch` → `InsightFallbackBuilder.build`; 2 error-routing unit tests GREEN |
| 4 | All rupee/percentage figures pre-computed in Swift (`Decimal`) and injected as literal context; model output verified by `InsightVerifier` before display; invented numbers replaced by template fallback (AI-04) | VERIFIED | `InsightService.swift:105-158` — `buildPrompt` injects only pre-computed facts via `NSDecimalNumber`; `InsightVerifier.swift:113-136` — guards only `₹`-prefixed and `%`-suffixed tokens against canonical set; `buildCanonicalSet` stores each amount both raw and rounded (WR-01 fix, d431f18); 6 unit tests GREEN including paise-rounding regression test; human sign-off step 5 cross-checked figures |
| 5 | Insights generated on demand, discarded after session (no persistence); streaming typewriter reveal; Reduce Motion degrades to instant text (AI-05) | VERIFIED | `AIInsightCard.swift:44-47` — all state in `@State`, no SwiftData/UserDefaults/FileManager; `AIInsightCard.swift:227-258` — streaming `for try await snapshot in stream` loop; `AIInsightCard.swift:216-225` — Reduce Motion instant path via `session.respond`; human sign-off steps 3, 7 confirm on real hardware |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Support/InsightService.swift` | `InsightGenerating` protocol, `@Generable SpendInsight`, `InsightPromptBuilder`, `isInsightAvailable()` | VERIFIED | All present, substantive, and wired |
| `MyHomeApp/Support/InsightVerifier.swift` | `InsightVerifier.verify`, `InsightFallbackBuilder.build`, `buildCanonicalSet` | VERIFIED | All present; WR-01 + WR-03 fixed in d431f18 |
| `MyHomeApp/Features/Analytics/AIInsightCard.swift` | Full view with availability gating, violet glow, orb, streaming typewriter | VERIFIED | 274-line implementation; no stubs |
| `MyHomeApp/Features/Analytics/AnalyticsView.swift` | `if #available(iOS 26, *)` block wiring `AIInsightCard(summary:)` after category bars | VERIFIED | Line 89-92 |
| `MyHomeApp/DesignSystem/DesignTokens.swift` | `aiVioletTop`, `aiVioletBottom`, `aiVioletGlow` tokens, canary accent unchanged | VERIFIED | Lines 28-34; `accent = Color(hex: "#FFD60A")` untouched |
| `MyHomeTests/InsightServiceTests.swift` | `MockInsightService` + 4 availability + 2 error-routing tests | VERIFIED | All 6 tests present and GREEN |
| `MyHomeTests/InsightVerifierTests.swift` | Reject + pass + Pitfall-5 + WR-01 regression + 2 fallback-builder tests | VERIFIED | 6 tests present and GREEN (including `testVerifierPassesRoundedPaiseAmount`) |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AnalyticsView.swift` | `AIInsightCard` | `if #available(iOS 26, *)` + instantiation at line 89-92 | WIRED | Passes `summary` computed fresh from `AnalyticsAggregator` at top of body |
| `AIInsightCard.swift` | `InsightVerifier.verify` | Called once post-stream at lines 226, 252 | WIRED | Applied on both Reduce Motion and streaming paths; never mid-stream |
| `AIInsightCard.swift` | `InsightFallbackBuilder.build` | Called in `catch` block at line 269 | WIRED | Covers `GenerationError` + any other error |
| `AIInsightCard.swift` | `InsightPromptBuilder.buildPrompt` | Called at line 213 in `generateInsight()` | WIRED | Fresh prompt per generation |
| `InsightVerifier.buildCanonicalSet` | `InsightVerifier.allNumbersVerified` | Called within `verify(_:against:)` at line 150 | WIRED | Token guard: only `₹`-prefix and `%`-suffix |
| `MyHome.xcodeproj/project.pbxproj` | All 5 new `.swift` files | PBXBuildFile + PBXFileReference + PBXGroup + PBXSourcesBuildPhase | WIRED | Confirmed: `InsightService.swift in Sources`, `InsightVerifier.swift in Sources`, `AIInsightCard.swift in Sources`, `InsightServiceTests.swift in Sources`, `InsightVerifierTests.swift in Sources` |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `AIInsightCard` | `displayedObservation`, `displayedSuggestion` | `LanguageModelSession.streamResponse` driven by `InsightPromptBuilder.buildPrompt(for: summary)` | Yes — injected from `SpendSummary` facts pre-computed by `AnalyticsAggregator` | FLOWING |
| `AIInsightCard` | Fallback path | `InsightFallbackBuilder.build(for: summary)` — formats `summary.totalSpend`, `categoryBreakdown.first` | Yes — same `SpendSummary` source | FLOWING |
| `InsightVerifier` | `facts` Set | `buildCanonicalSet(from: summary)` — inserts all `Decimal` amounts raw + rounded | Yes — directly from `SpendSummary` | FLOWING |

---

## Behavioral Spot-Checks

Live Apple Intelligence generation cannot be checked without a running device. Simulator-verifiable behaviors are covered by the unit test suite (confirmed GREEN per context).

| Behavior | Check | Status |
|----------|-------|--------|
| All 4 availability branches return correct Bool | Unit tests in `InsightServiceTests` | PASS (confirmed GREEN on iPhone 17 sim) |
| Error routing to fallback (2 error types) | Unit tests in `InsightServiceTests` | PASS (confirmed GREEN) |
| Verifier rejects invented rupee amount | `testVerifierRejectsInventedNumber` | PASS (confirmed GREEN) |
| Verifier passes fact-only numbers | `testVerifierPassesFactOnlyNumbers` | PASS (confirmed GREEN) |
| Paise-bearing total rounds correctly (WR-01) | `testVerifierPassesRoundedPaiseAmount` | PASS (confirmed GREEN; added in d431f18) |
| Prose bare integers not flagged (Pitfall 5 / WR-03) | `testVerifierIgnoresSmallProseIntegers` | PASS (confirmed GREEN) |
| Fallback is self-consistent with verifier | `testFallbackIsVerifierConsistent` | PASS (confirmed GREEN) |
| Fallback suggestion always nil | `testFallbackSuggestionIsNil` | PASS (confirmed GREEN) |
| Live on-device generation, figures match, airplane mode | Human verification (16-05-SUMMARY) | PASS — user sign-off 2026-06-27 |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AI-01 | 16-05 | On-device generation via Apple Intelligence | SATISFIED | `AIInsightCard` uses `LanguageModelSession` directly; airplane-mode generation confirmed by user (16-05 step 6) |
| AI-02 | 16-01 / 16-03 | Two-layer gating; all unavailability cases silently absent | SATISFIED | `isInsightAvailable()` exhaustive switch; `AIInsightCard.body` returns nothing on unavailable; 4 unit tests GREEN |
| AI-03 | 16-01 / 16-03 | `@Generable SpendInsight`; guardrail + context-window handled | SATISFIED | `SpendInsight` struct; `catch` block routes both error types to `InsightFallbackBuilder`; 2 unit tests GREEN |
| AI-04 | 16-02 | Numeric integrity — pre-computed facts only; verifier rejects invented numbers | SATISFIED | `InsightPromptBuilder` injects only `Decimal` facts; `InsightVerifier` checks `₹`/`%` tokens; WR-01 fixed (paise rounding); 4 verifier tests GREEN + human cross-check (16-05 step 5) |
| AI-05 | 16-04 / 16-05 | On-demand generation, no persistence, streaming typewriter + Reduce Motion | SATISFIED | No SwiftData/UserDefaults/FileManager in `AIInsightCard`; streaming path implemented; Reduce Motion instant path present; human sign-off steps 3, 4, 7 |

---

## Anti-Patterns Found

| File | Pattern | Severity | Notes |
|------|---------|----------|-------|
| `InsightService.swift:49-52` | `_spendInsightMemberwiseInitBuildCheck` private function in production binary | Info (IN-01) | Deferred from code review — not a blocker; no behavior change; harmless dead function |
| `InsightService.swift:178-195` | `InsightService.generate()` is dead production code — `AIInsightCard` creates its own `LanguageModelSession` directly | Warning (WR-02) | Deferred from code review — seam is used by `MockInsightService` in tests; no runtime behavior gap; labelled as deferred minor |

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 16 file. No blocker anti-patterns.

---

## Human Verification Required

All automated checks (unit tests, pbxproj registration, deployment target, wiring greps) are VERIFIED. The remaining open item is live Apple Intelligence generation, which the simulator cannot exercise.

### 1. On-Device Live Generation (COMPLETED — sign-off recorded)

**Test:** Build and run on a physical A17 Pro+ device with Apple Intelligence enabled; navigate Overview → Analytics; observe AI Insight card behavior.

**Expected:**
- Card appears below category bars with neumorphic raised surface, violet edge glow, sparkles label
- Character-by-character typewriter reveal with breathing orb during generation
- All rupee amounts and percentages in generated text match values shown in headline card and category bars
- Week → Month → Year tab switches trigger fresh insight per range
- Airplane mode: generation still completes (confirming on-device)
- Reduce Motion enabled: instant full text appears, no orb
- On a non-Apple-Intelligence device: clean end after category bars — no shell, no spinner, no gap

**Why human:** iPhone 17 simulator cannot run `LanguageModelSession` generation.

**Status:** COMPLETED — user sign-off 2026-06-27, all 8 steps passed (16-05-SUMMARY.md).

---

## Deferred Items (Not Actionable Gaps)

| Item | Addressed | Notes |
|------|-----------|-------|
| WR-02: `InsightService.generate()` unreachable in production | Deferred (code review) | Minor — seam works for tests; AIInsightCard generates directly which is the intended production path for streaming; no behavior change |
| IN-01: `_spendInsightMemberwiseInitBuildCheck` in release binary | Deferred (code review) | Info-level; `#if DEBUG` wrap or deletion recommended in a future cleanup pass |

---

## Summary

Phase 16 goal is achieved. All five requirement IDs (AI-01 through AI-05) are satisfied by substantive, wired, data-flowing implementation:

- **AI-01/AI-05:** `AIInsightCard` generates on-demand via `LanguageModelSession`, streams character-by-character, discards state after session (no persistence), respects Reduce Motion.
- **AI-02:** Two-layer gating (`#available(iOS 26, *)` + `isInsightAvailable()`) with exhaustive switch covering all three `UnavailableReason` cases; `EmptyView` on every unavailable branch; 4 unit tests GREEN.
- **AI-03:** `@Generable SpendInsight` with `@Guide` annotations; `guardrailViolation` and `exceededContextWindowSize` both route to `InsightFallbackBuilder`; 2 unit tests GREEN.
- **AI-04:** All figures injected as pre-computed `Decimal` facts via `InsightPromptBuilder`; `InsightVerifier` checks only `₹`-prefixed and `%`-suffixed tokens; WR-01 (paise rounding) and WR-03 (magnitude guard) fixed in commit d431f18; 6 verifier unit tests GREEN including paise-rounding regression.
- **pbxproj / deployment target:** All 5 new files registered with all 4 required edits; `IPHONEOS_DEPLOYMENT_TARGET = 17.0` confirmed unchanged across all configurations.

The `human_needed` status reflects that live on-device generation cannot be verified programmatically. The user's sign-off (16-05-SUMMARY.md, 2026-06-27) covering all 8 behaviors is on record. The two deferred code-review items (WR-02, IN-01) are minor/info and do not affect goal achievement.

---

_Verified: 2026-06-27_
_Verifier: Claude (gsd-verifier)_
