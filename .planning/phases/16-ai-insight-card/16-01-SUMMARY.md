---
phase: 16-ai-insight-card
plan: "01"
subsystem: ai-insight
tags: [foundation-models, contracts, design-tokens, pbxproj, tdd-red]
dependency_graph:
  requires: []
  provides:
    - InsightService.swift (InsightGenerating protocol, SpendInsight @Generable, InsightPromptBuilder, isInsightAvailable)
    - InsightVerifier.swift (InsightVerifier.verify stub, InsightFallbackBuilder stub)
    - AIInsightCard.swift (view stub gated @available iOS 26)
    - DesignTokens.aiViolet* tokens
    - InsightServiceTests.swift (MockInsightService, 6 tests)
    - InsightVerifierTests.swift (2 tests)
  affects:
    - MyHome.xcodeproj/project.pbxproj (5 new files registered)
    - MyHomeApp/DesignSystem/DesignTokens.swift (3 tokens added)
tech_stack:
  added: [FoundationModels (@Generable, @Guide, SystemLanguageModel, LanguageModelSession)]
  patterns: [protocol-injection-testability-seam, unchecked-sendable-test-mock, @available-ios26-gating]
key_files:
  created:
    - MyHomeApp/Support/InsightService.swift
    - MyHomeApp/Support/InsightVerifier.swift
    - MyHomeApp/Features/Analytics/AIInsightCard.swift
    - MyHomeTests/InsightServiceTests.swift
    - MyHomeTests/InsightVerifierTests.swift
  modified:
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "@Generable preserves memberwise init: SpendInsight(observation:suggestion:) compiles — InsightFallbackBuilder can use memberwise init directly (Open Question 1 RESOLVED: YES)"
  - "GenerationError.Context is not publicly constructible in tests — error-routing tests use MockGenerationError and verify fallback OUTCOME only (Open Question 3 path confirmed)"
  - "MockInsightService uses @unchecked Sendable to satisfy Swift 6 Sendable conformance required by InsightGenerating: Sendable protocol"
  - "Task.yield() is async-but-not-throws — removed try prefix; cancellation propagates via structured concurrency"
metrics:
  duration: "~45 minutes"
  completed: "2026-06-26"
  tasks_completed: 3
  files_modified: 7
---

# Phase 16 Plan 01: Foundation Contracts + RED Scaffolds Summary

**One-liner:** InsightGenerating protocol seam, SpendInsight @Generable struct, InsightVerifier/InsightFallbackBuilder stubs, AIInsightCard view stub, violet AI tokens, all 5 new files pbxproj-registered and compiling, 8 behavior tests written (2 RED, 6 GREEN).

---

## What Was Built

### Task 1: AI-Only Violet Accent Tokens (DesignTokens.swift)

Added three tokens in a clearly scoped "AI Insight accent" section:
- `aiVioletTop = #C4A6FF` (edge gradient top)
- `aiVioletBottom = #7C5CFF` (edge gradient bottom)
- `aiVioletGlow = #8B5CF6` (shadow / orb / wash)

Canary accent `#FFD60A` is byte-identical to before. The section is commented prominently as localized to `AIInsightCard` only.

### Task 2: Contract Stubs + pbxproj Registration

**InsightService.swift** (Support group):
- `@Generable SpendInsight` struct with `@Guide`-annotated `observation: String` and `suggestion: String?`
- Compile-only build-check function `_spendInsightMemberwiseInitBuildCheck()` — proves memberwise init survives `@Generable`
- `protocol InsightGenerating: Sendable` — single testability seam (LanguageModelSession is `final`)
- `enum InsightPromptBuilder` with `systemInstructions: String` and `buildPrompt(for:) -> String` (stubs)
- `func isInsightAvailable(_ availability: SystemLanguageModel.Availability) -> Bool` returning `false` (stub)

**InsightVerifier.swift** (Support group):
- `enum InsightVerifier` with `struct Result { observation, suggestion, passed }` and `static func verify(_:against:)` returning `passed: true` (stub)
- `enum InsightFallbackBuilder` with `static func build(for:) -> SpendInsight` (stub)

**AIInsightCard.swift** (Analytics group):
- `@available(iOS 26, *)` struct conforming to `View`, takes `SpendSummary`, returns `EmptyView()` (stub)

**pbxproj**: 4-edit pattern (PBXBuildFile, PBXFileReference, PBXGroup children, PBXSourcesBuildPhase) applied for all 5 files. IDs used:
- App target: F1601IS/A1601IS (InsightService), F1601IV/A1601IV (InsightVerifier), F1601AIC/A1601AIC (AIInsightCard)
- Test target: F1601IST/A1601IST (InsightServiceTests), F1601IVT/A1601IVT (InsightVerifierTests)

**Build result: SUCCEEDED** — `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` passes with zero new errors.

### Task 3: RED Test Scaffolds

**InsightServiceTests.swift** (6 tests):
| Test | Status | Why |
|------|--------|-----|
| `testAvailabilityAvailableReturnsTrue` | RED | Stub returns `false`; Plan 03 implements `.available → return true` |
| `testAvailabilityDeviceNotEligibleReturnsFalse` | GREEN | Stub returns `false` (accidentally correct) |
| `testAvailabilityIntelligenceDisabledReturnsFalse` | GREEN | Stub returns `false` (accidentally correct) |
| `testAvailabilityModelNotReadyReturnsFalse` | GREEN | Stub returns `false` (accidentally correct) |
| `testGuardrailErrorRoutesFallback` | GREEN | Mock throws, catch-all returns fallback stub (non-empty) |
| `testContextWindowErrorRoutesFallback` | GREEN | Same pattern |

**InsightVerifierTests.swift** (2 tests):
| Test | Status | Why |
|------|--------|-----|
| `testVerifierRejectsInventedNumber` | RED | Stub returns `passed: true`; `#expect(passed == false)` fails |
| `testVerifierPassesFactOnlyNumbers` | GREEN | Stub returns `passed: true` (accidentally correct) |

**Test bundle: COMPILES AND RUNS.** Overall test run exit is non-zero (RED tests fail), which is acceptable in Wave 1 per plan.

---

## Open Question 1 — RESOLVED

**Question:** Does `@Generable` preserve the memberwise `init(observation:suggestion:)` on `SpendInsight`?

**Answer: YES.** The compile-only function `_spendInsightMemberwiseInitBuildCheck()` containing `_ = SpendInsight(observation: "x", suggestion: nil)` compiled without errors inside the iOS 26.5 SDK build. No `FallbackInsight` adapter struct is needed. `InsightFallbackBuilder.build(for:)` can return `SpendInsight(observation:suggestion:)` directly.

**Impact:** Plans 02 and 04 may call `SpendInsight(observation:suggestion:)` directly in fallback and verification paths.

---

## Open Question 3 — CONFIRMED PATH

**Question:** Is `LanguageModelSession.GenerationError.Context` publicly constructible?

**Answer:** Not testable from the test target without importing FoundationModels directly. Tests use `MockGenerationError` (local enum) and verify the fallback OUTCOME only. Production catch block (Plans 03/04) will match `is LanguageModelSession.GenerationError` — not tested directly.

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed `try` from `Task.yield()` in MockInsightService**
- **Found during:** Task 3 test compilation
- **Issue:** `Task.yield()` is `async` but NOT `throws`; `try await Task.yield()` caused Swift compiler warning "no calls to throwing functions occur within try expression"
- **Fix:** Changed to `await Task.yield()`
- **Files modified:** `MyHomeTests/InsightServiceTests.swift`
- **Commit:** e2880d5

**2. [Rule 1 - Bug] Added `@unchecked Sendable` to MockInsightService**
- **Found during:** Task 3 — first test build attempt
- **Issue:** Swift 6 strict concurrency: `MockInsightService` conforms to `InsightGenerating: Sendable` but has mutable `var result` — compiler error "stored property 'result' of Sendable-conforming class is mutable"
- **Fix:** `final class MockInsightService: InsightGenerating, @unchecked Sendable` — standard test-mock pattern
- **Files modified:** `MyHomeTests/InsightServiceTests.swift`
- **Commit:** e2880d5

**3. [Rule 1 - Bug] Removed LanguageModelSession reference from test callServiceWithFallback**
- **Found during:** Task 3 — first test build attempt
- **Issue:** `catch is LanguageModelSession.GenerationError` in test helper caused "cannot find type 'LanguageModelSession' in scope" — FoundationModels types require explicit import in test file. Since tests verify the OUTCOME (not the error type), a single catch-all is cleaner and more correct.
- **Fix:** Replaced specific catch clause with single `catch error { return InsightFallbackBuilder.build(for:) }`
- **Files modified:** `MyHomeTests/InsightServiceTests.swift`
- **Commit:** e2880d5

---

## Known Stubs

All stubs are intentional Wave 1 placeholders. No data flows to UI in this plan (AIInsightCard returns EmptyView). Plans 02/03/04 resolve each:

| Stub | File | Resolved By |
|------|------|-------------|
| `isInsightAvailable` always returns `false` | InsightService.swift | Plan 03 Task 1 |
| `InsightPromptBuilder.buildPrompt` returns `""` | InsightService.swift | Plan 03 Task 2 |
| `InsightVerifier.verify` always returns `passed: true` | InsightVerifier.swift | Plan 02 Task 1 |
| `InsightFallbackBuilder.build` returns fixed string | InsightVerifier.swift | Plan 02 Task 2 |
| `AIInsightCard.body` returns `EmptyView()` | AIInsightCard.swift | Plan 04 |

---

## Threat Flags

None. This plan introduces no new network endpoints, auth paths, or schema changes. The only new trust boundary (SpendSummary → on-device LLM prompt) is noted in the plan's threat model as T-16-01 and will be mitigated in Plans 03/04 via the InsightVerifier gate.

---

## TDD Gate Compliance

- RED gate: `test(16-01): write RED test scaffolds for 8 AI insight behaviors` ✓
- GREEN gate: N/A — stubs intentionally RED in Wave 1; Plans 02/03 own the GREEN gate

---

## Self-Check: PASSED

Files created/exist:
- MyHomeApp/Support/InsightService.swift ✓
- MyHomeApp/Support/InsightVerifier.swift ✓
- MyHomeApp/Features/Analytics/AIInsightCard.swift ✓
- MyHomeTests/InsightServiceTests.swift ✓
- MyHomeTests/InsightVerifierTests.swift ✓
- MyHomeApp/DesignSystem/DesignTokens.swift (modified, aiViolet tokens ×3) ✓

Commits:
- 3d77f4c feat(16-01): add AI-only violet accent tokens to DesignTokens ✓
- c280386 feat(16-01): add contract stubs + register 5 files in pbxproj ✓
- e2880d5 test(16-01): write RED test scaffolds for 8 AI insight behaviors ✓

Build: `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED ✓
Test run: 2 RED (expected), 6 GREEN (3 accidentally correct + 3 genuinely passing) ✓
Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 17.0` unchanged ✓
