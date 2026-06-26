---
phase: 16-ai-insight-card
plan: "03"
subsystem: ai-insight
tags: [foundation-models, availability-switch, prompt-builder, language-model-session, tdd-green, decimal-formatting]
dependency_graph:
  requires:
    - InsightService.swift (Plan 01 stubs: isInsightAvailable stub, InsightPromptBuilder stub, InsightGenerating protocol)
    - InsightServiceTests.swift (Plan 01 RED scaffold: testAvailabilityAvailableReturnsTrue RED)
  provides:
    - isInsightAvailable (four-branch exhaustive switch — AI-02 fully implemented)
    - InsightPromptBuilder.buildPrompt (token-budgeted en_IN rupee prompt — AI-03/AI-04 prevention-at-source)
    - InsightService (production LanguageModelSession wrapper — AI-03)
  affects:
    - AIInsightCard.swift (Plan 04 — consumes InsightService.generate + InsightPromptBuilder)
tech_stack:
  added: []
  patterns:
    - exhaustive-switch-over-unavailable-reason (no default: catch-all; @unknown default for SDK forward-compat)
    - decimal-to-nsDecimalNumber-currency-fmt (en_IN NumberFormatter on NSDecimalNumber, never Double)
    - fresh-session-per-generation (new LanguageModelSession per generate call — T-16-04/Pitfall 3)
    - error-propagation-to-caller (InsightService does not catch GenerationError; caller owns fallback mapping)
key_files:
  created: []
  modified:
    - MyHomeApp/Support/InsightService.swift
decisions:
  - "isInsightAvailable uses @unknown default (not a bare default:) to keep switch exhaustive while remaining forward-compatible with future UnavailableReason cases"
  - "buildPrompt formats rupee amounts via en_IN NumberFormatter on NSDecimalNumber — no Double boundary (WR-03/AI-04)"
  - "InsightService.generate does NOT catch LanguageModelSession.GenerationError — AIInsightCard (Plan 04) owns the streaming path and error→fallback mapping"
  - "prior-category spend lookup uses priorCategorySpend[cat.id] (PersistentIdentifier, O(1)) per Pitfall 6"
  - "pct formula abs(Int(summary.deltaFraction * 100)) mirrors InsightVerifier.buildCanonicalSet and InsightFallbackBuilder.build — self-consistent for AI-04 verification"
patterns-established:
  - "Prompt builder: inject only pre-computed Decimal facts; no instruction to calculate/round/invent (AI-04 prevention-at-source)"
  - "Category name truncation to ≤30 chars in buildPrompt (T-16-03 prompt-injection guard)"
requirements-completed: [AI-02, AI-03]
duration: ~12min
completed: 2026-06-27
---

# Phase 16 Plan 03: InsightService Implementation Summary

**isInsightAvailable four-branch exhaustive switch (AI-02 GREEN) + InsightPromptBuilder token-budgeted en_IN prompt + InsightService LanguageModelSession wrapper; all 6 InsightServiceTests fully GREEN.**

## Performance

- **Duration:** ~12 minutes
- **Started:** 2026-06-27T02:44:00Z
- **Completed:** 2026-06-27T02:57:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- `isInsightAvailable` implemented as exhaustive switch over `SystemLanguageModel.Availability` — `.available` returns `true`; all three `UnavailableReason` cases return `false`; `@unknown default` added for SDK forward-compatibility (AI-02 / D-01)
- `InsightPromptBuilder.buildPrompt(for:)` injects range label, `totalSpend`, `priorTotalSpend`, up/down direction + whole-% delta, top-5 categories with `spentDecimal` and prior spend via `priorCategorySpend[cat.id]` (Pitfall 6); rupee amounts formatted via `en_IN` `NumberFormatter` on `NSDecimalNumber` — no `Double` cast; category names truncated to ≤30 chars (T-16-03)
- `InsightService` class implements `InsightGenerating`: creates a fresh `LanguageModelSession` per call, calls `respond(to:generating:SpendInsight.self)`, returns `response.content`; does not catch `GenerationError` — caller owns fallback mapping
- `testAvailabilityAvailableReturnsTrue` flipped from RED → GREEN; all 6 `InsightServiceTests` now pass

## Task Commits

1. **Task 1: Implement isInsightAvailable four-branch switch** — `8d9fce9` (feat)
2. **Task 2: Implement InsightPromptBuilder.buildPrompt + InsightService** — `5110342` (feat)

## Files Created/Modified

- `MyHomeApp/Support/InsightService.swift` — `isInsightAvailable` real switch, `InsightPromptBuilder.buildPrompt` full implementation, `InsightService` class added

## Decisions Made

- Used `@unknown default` (not bare `default:`) in `isInsightAvailable` so all three known `UnavailableReason` cases are explicit and a future SDK case surfaces as a warning (not silently handled)
- Rupee formatting via `en_IN` `NumberFormatter` on `NSDecimalNumber`, not `Double` — prevents floating-point drift in prompt figures (WR-03 / AI-04 prevention-at-source)
- `InsightService.generate` does NOT catch `LanguageModelSession.GenerationError` — the plan explicitly assigns error→fallback ownership to `AIInsightCard` (Plan 04 `generateInsight()`); tests verify fallback OUTCOME via `MockInsightService`, not through `InsightService`
- `pct` formula `abs(Int(summary.deltaFraction * 100))` is byte-for-byte identical to `InsightVerifier.buildCanonicalSet` and `InsightFallbackBuilder.build` — self-consistency ensures the injected percentage is always in the canonical fact set (AI-04 guarantee)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-16-01 (Info Disclosure — on-device only) | mitigate | DONE — `InsightService` uses `LanguageModelSession` only; no `URLSession`, no network |
| T-16-03 (Tampering — category name injection) | mitigate | DONE — `String(cat.name.prefix(30))` in `buildPrompt` |
| T-16-04 (Tampering — session transcript contamination) | mitigate | DONE — fresh `LanguageModelSession` per `generate(for:)` call |

## Known Stubs

| Stub | File | Resolved By |
|------|------|-------------|
| `AIInsightCard.body` returns `EmptyView()` | AIInsightCard.swift | Plan 04 |

No stubs remain in `InsightService.swift` — `isInsightAvailable`, `InsightPromptBuilder.buildPrompt`, and `InsightService.generate` are all fully implemented.

## TDD Gate Compliance

- RED gate (Plan 01): `test(16-01): write RED test scaffolds for 8 AI insight behaviors` ✓ (e2880d5)
- GREEN gate (Plan 03): `feat(16-03): implement isInsightAvailable four-branch switch (AI-02 GREEN)` ✓ (8d9fce9) and `feat(16-03): implement InsightPromptBuilder.buildPrompt + InsightService (AI-03 GREEN)` ✓ (5110342)

## Self-Check: PASSED

Files modified:
- MyHomeApp/Support/InsightService.swift ✓

Commits:
- 8d9fce9 feat(16-03): implement isInsightAvailable four-branch switch (AI-02 GREEN) ✓
- 5110342 feat(16-03): implement InsightPromptBuilder.buildPrompt + InsightService (AI-03 GREEN) ✓

Acceptance criteria:
- all 6 InsightServiceTests PASS (4 availability + 2 error-routing) ✓
- `grep -c 'func isInsightAvailable' InsightService.swift` → 1 ✓
- `grep -c 'priorCategorySpend\[' InsightService.swift` → 2 (≥ 1) ✓
- `grep -c 'LanguageModelSession(' InsightService.swift` → 1 (≥ 1) ✓
- No `Double(` cast on money in `buildPrompt` ✓
- `String(cat.name.prefix(30))` truncation present ✓
- No `URLSession` in InsightService.swift ✓

## Next Phase Readiness

- `InsightService` is ready for Plan 04 (`AIInsightCard`) to call `generate(for:)` in the `.task(id:)` streaming lifecycle
- `InsightPromptBuilder.buildPrompt(for:)` is wired and tested — Plan 04 creates a fresh `LanguageModelSession(instructions: InsightPromptBuilder.systemInstructions)` and calls `streamResponse(to: prompt, generating:)` for the typewriter path
- Plan 04 must implement the `catch is LanguageModelSession.GenerationError` → `InsightFallbackBuilder.build(for:)` mapping that `InsightService` deliberately does not own

---
*Phase: 16-ai-insight-card*
*Completed: 2026-06-27*
