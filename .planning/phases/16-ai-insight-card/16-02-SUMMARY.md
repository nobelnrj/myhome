---
phase: 16-ai-insight-card
plan: "02"
subsystem: ai-insight
tags: [numeric-integrity, verifier, fallback-builder, tdd-green, decimal-matching]
dependency_graph:
  requires:
    - InsightVerifier.swift (Plan 01 stubs)
    - InsightVerifierTests.swift (Plan 01 RED scaffolds)
  provides:
    - InsightVerifier.buildCanonicalSet (Set<Decimal> of all SpendSummary facts)
    - InsightVerifier.allNumbersVerified (regex-based guarded number extraction + Decimal matching)
    - InsightVerifier.verify (full AI-04 integrity gate)
    - InsightFallbackBuilder.build (terse fact-only fallback, en_IN rupee format)
  affects:
    - MyHomeApp/Support/InsightVerifier.swift (stub → full implementation)
    - MyHomeTests/InsightVerifierTests.swift (2 tests → 5 tests, all GREEN)
tech_stack:
  added: []
  patterns:
    - regex-guarded-number-extraction (₹-prefix / %-suffix / magnitude≥100 guard rule)
    - decimal-normalise-strip-commas (handles standard and Indian lakh grouping)
    - fallback-self-consistency (verify(build(for:), against:).passed == true)
key_files:
  created: []
  modified:
    - MyHomeApp/Support/InsightVerifier.swift
    - MyHomeTests/InsightVerifierTests.swift
decisions:
  - "Regex /(?:(₹)\\s*)?(\\d[\\d,]*)(?:\\.\\d+)?(%)?/ captures ₹-prefix and %-suffix in named groups; magnitude≥100 bare numbers are guarded by post-filter (Pitfall 5 compliance)"
  - "Decimal normalisation: strip all commas from match output before Decimal(string:) — handles both standard (₹12,000) and lakh (₹1,23,456) grouping transparently"
  - "InsightFallbackBuilder formats via NumberFormatter(currencyCode:INR, locale:en_IN) — no Double boundary, pure Decimal→NSDecimalNumber"
  - "Fallback uses pct = abs(Int(summary.deltaFraction * 100)) — identical formula to buildCanonicalSet ensuring self-consistency"
  - "xcodebuild must be run from worktree root (not main repo) when executing from a git worktree"
metrics:
  duration: "~20 minutes"
  completed: "2026-06-27"
  tasks_completed: 2
  files_modified: 2
---

# Phase 16 Plan 02: InsightVerifier + InsightFallbackBuilder Summary

**One-liner:** Full AI-04 numeric-integrity gate: regex-based guarded number extraction with Decimal-normalised exact matching against SpendSummary canonical fact set; self-consistent fallback builder in en_IN rupee format; all 5 InsightVerifierTests GREEN.

---

## What Was Built

### Task 1: Number Extraction + Canonical Fact Set + Matching (GREEN)

**`InsightVerifier.buildCanonicalSet(from:) -> Set<Decimal>`**

Constructs the complete set of pre-computed Decimal facts from a SpendSummary:
- `totalSpend` and `priorTotalSpend` (headline rupee figures)
- `abs(delta)` (absolute period-over-period change)
- `Decimal(abs(Int(deltaFraction * 100)))` (whole-number percentage, e.g. Decimal(20) for "20%")
- Every `categoryBreakdown[].spentDecimal` (per-category current spend)
- Every `priorCategorySpend.values` (per-category prior spend)

**`InsightVerifier.allNumbersVerified(in:against:) -> Bool`**

Uses a single Swift Regex literal to locate all number tokens with context:
```
/(?:(₹)\s*)?([\d][\d,]*)(?:\.\d+)?(%)?/
```
- Group 1 captures the `₹` prefix (present → rupee-guarded)
- Group 2 captures the digit sequence (with optional commas for grouping)
- Group 3 captures the `%` suffix (present → percent-guarded)

Guard rule (Pitfall 5): a match is only verified if it is ₹-prefixed, %-suffixed, OR has magnitude ≥ 100. Bare prose integers < 100 are skipped ("3 items", "2 days" etc.).

Normalisation (Open Question 2): strips ALL commas from the captured digit sequence before `Decimal(string:)`, so `₹12,000` (standard) and `₹1,23,456` (lakh grouping) both resolve to the correct Decimal value.

**`InsightVerifier.verify(_:against:) -> Result`**

Combines observation + suggestion text, runs `allNumbersVerified`, returns:
- `passed: true` with original observation/suggestion if all guarded numbers match
- `passed: false` with `InsightFallbackBuilder.build(for:)` output if any number fails

**Tests turned GREEN:**
- `testVerifierRejectsInventedNumber`: ₹15,000 ∉ {12000,10000,2000,20} → passed=false, fallback substituted ✓
- `testVerifierPassesFactOnlyNumbers`: ₹12,000 + 20% both ∈ fact set → passed=true, original returned ✓
- `testVerifierIgnoresSmallProseIntegers`: bare "3" and "2" skipped (< 100, no ₹/%) → passed=true ✓

### Task 2: InsightFallbackBuilder Templated Fallback (GREEN)

**`InsightFallbackBuilder.build(for:) -> SpendInsight`**

Produces a terse, normal-sounding one-sentence insight using ONLY fact-derived values:

With top category:
```
"You spent ₹12,000 — Dining was the top category at ₹4,500, with total spend up 20% vs last period."
```

Without categories (as in Wave 1 test fixture):
```
"You spent ₹12,000 this period, up 20% vs the previous period."
```

Key implementation details:
- Rupee formatting via `NumberFormatter(numberStyle: .currency, currencyCode: "INR", locale: en_IN)` — no Double boundary
- Percentage via `abs(Int(summary.deltaFraction * 100))` — identical to `buildCanonicalSet` ensuring self-consistency
- Category name truncated to ≤ 30 characters via `String(name.prefix(30))`
- `suggestion` is always `nil`
- Zero error/apology wording in string literals

**Tests turned GREEN:**
- `testFallbackIsVerifierConsistent`: `verify(build(for: fixture), against: fixture).passed == true` ✓
- `testFallbackSuggestionIsNil`: `fallback.suggestion == nil` ✓

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as specified. One environmental note (not a deviation):

**[Discovery] xcodebuild must run from worktree root**
- The plan's `<verify>` steps specify `cd "/Users/reo/My Projects/my-home"` (main repo root), but the modified source files live in the git worktree at `.claude/worktrees/agent-a189cb5adb0be64df/`. Running xcodebuild from the main repo path compiled stale stub code.
- Fix: ran xcodebuild from the worktree root. Tests went GREEN immediately.
- No source code changes needed.

---

## Known Stubs

Remaining intentional stubs (resolved in later plans):

| Stub | File | Resolved By |
|------|------|-------------|
| `isInsightAvailable` always returns `false` | InsightService.swift | Plan 03 Task 1 |
| `InsightPromptBuilder.buildPrompt` returns `""` | InsightService.swift | Plan 03 Task 2 |
| `AIInsightCard.body` returns `EmptyView()` | AIInsightCard.swift | Plan 04 |

No stubs remain in InsightVerifier.swift or InsightVerifierTests.swift.

---

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-16-02 (Tampering — InsightVerifier) | mitigate | DONE — any guarded number not in canonical Set<Decimal> → rejected, fallback substituted; exact Decimal match, ±0 tolerance |
| T-16-03 (Info Disclosure — InsightFallbackBuilder) | mitigate | DONE — fallback emits ONLY summary-derived figures; raw model text never echoed on rejection path |

---

## TDD Gate Compliance

- RED gate (Plan 01): `test(16-01): write RED test scaffolds for 8 AI insight behaviors` ✓ (e2880d5)
- GREEN gate (Plan 02): `feat(16-02): implement InsightVerifier + InsightFallbackBuilder (AI-04 GREEN)` ✓ (a7c7023)

---

## Self-Check: PASSED

Files modified:
- MyHomeApp/Support/InsightVerifier.swift ✓
- MyHomeTests/InsightVerifierTests.swift ✓

Commits:
- a7c7023 feat(16-02): implement InsightVerifier + InsightFallbackBuilder (AI-04 GREEN) ✓

Acceptance criteria:
- `xcodebuild test -only-testing:MyHomeTests/InsightVerifierTests` → all 5 tests PASSED ✓
- `grep -c 'buildCanonicalSet' InsightVerifier.swift` → 2 (≥ 1) ✓
- `grep -c 'InsightFallbackBuilder' InsightVerifier.swift` → 5 (≥ 1) ✓
- `grep -ci 'sorry\|unavailable\|couldn' InsightVerifier.swift` → 0 ✓
- No `import SwiftUI` in InsightVerifier.swift ✓
