---
phase: 16-ai-insight-card
reviewed: 2026-06-27T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - MyHomeApp/DesignSystem/DesignTokens.swift
  - MyHomeApp/Support/InsightService.swift
  - MyHomeApp/Support/InsightVerifier.swift
  - MyHomeApp/Features/Analytics/AIInsightCard.swift
  - MyHomeApp/Features/Analytics/AnalyticsView.swift
findings:
  critical: 0
  warning: 3
  info: 1
  total: 4
status: issues_found
resolution:
  resolved: [WR-01, WR-03]
  deferred: [WR-02, IN-01]
  resolved_in: d431f18
  resolved_at: 2026-06-27
---

# Phase 16: AI Insight Card — Code Review Report

**Reviewed:** 2026-06-27
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

> **Resolution (2026-06-27, commit `d431f18`):**
> - **WR-01 FIXED** — `InsightVerifier.buildCanonicalSet` now stores each rupee amount both raw and rounded to whole rupees (matching the prompt's `maximumFractionDigits: 0`), so paise-bearing data no longer falls back forever. Regression test `testVerifierPassesRoundedPaiseAmount` added.
> - **WR-03 FIXED** — dropped the bare-number `magnitude ≥ 100` guard per revised Pitfall 5; only ₹/% tokens are verified.
> - **WR-02 DEFERRED** — `InsightService.generate()` dead-code / seam-bypass (minor; no behavior change).
> - **IN-01 DEFERRED** — `_spendInsightMemberwiseInitBuildCheck` debug probe left in binary (info-level).

---

## Summary

Five files reviewed covering the full Phase 16 AI Insight Card: design tokens, the
InsightService/InsightGenerating protocol seam, InsightVerifier numeric-integrity gate,
AIInsightCard SwiftUI view, and AnalyticsView wiring. The implementation is structurally
sound — availability gating is correct, task-id cancellation wires correctly, the streaming
typewriter path is correct, and the fallback is always readable prose. No crashes, no security
vulnerabilities, no hardcoded secrets.

Three concrete bugs are present:

1. **Decimal precision mismatch between canonical fact set and prompt-injected values** — the
   verifier compares raw `Decimal` values (which include paise from bank parsers) against numbers
   the model extracted from an integer-rounded prompt. For any user with at least one bank-parsed
   expense whose amount has paise, the verifier rejects every AI-generated insight and falls back
   to the template permanently. Given that `HDFCParser`, `ICICIParser`, and `CUBParser` all call
   `Decimal(string: amtStr)` on raw bank-email strings (which routinely contain `.50`, `.75`,
   etc.), this affects real users.

2. **`InsightService.generate()` is unreachable production code** — `AIInsightCard` creates a
   fresh `LanguageModelSession` directly for both the streaming and Reduce Motion paths; it never
   calls through the `InsightGenerating` seam. The seam works for unit tests but not for the
   view, which means `AIInsightCard`'s internal generation and error-handling path has no
   unit-test coverage.

3. **Verifier guards bare integers ≥ 100 against the research's explicit revised strategy** —
   `Pitfall 5` in the research concludes: "Only flag rupee amounts ≥ ₹100 and percentage
   figures." The implementation adds a third guard (`value >= 100` without ₹ or %) that the
   research explicitly abandoned after noting it produces false rejections on prose integers. Any
   model output containing a bare number ≥ 100 that is not in the fact set (e.g., a year
   reference or a count) causes the insight to be silently replaced by the fallback.

---

## Warnings

### WR-01: Canonical fact set uses raw Decimal; prompt uses integer-rounded rupee strings — mismatch rejects valid model output

**File:** `MyHomeApp/Support/InsightVerifier.swift:57-78` (buildCanonicalSet) and `MyHomeApp/Support/InsightService.swift:107-115` (buildPrompt formatter)

**Issue:** `InsightVerifier.buildCanonicalSet` inserts the raw `Decimal` values from `SpendSummary`:

```swift
facts.insert(summary.totalSpend)        // Decimal("12500.75") if paise present
facts.insert(summary.priorTotalSpend)
```

But `InsightPromptBuilder.buildPrompt` formats all rupee amounts through a
`NumberFormatter` with `maximumFractionDigits: 0`, which rounds to the nearest rupee:

```swift
currencyFmt.maximumFractionDigits = 0
// "12500.75" → formatter → "₹12,501"
```

When the model faithfully reproduces `₹12,501` from the prompt, the verifier
extracts `Decimal(12501)` and checks it against a fact set that contains
`Decimal("12500.75")` — which is NOT equal. Result: `passed == false` → fallback
substituted for every single generation, forever.

The bank parsers (`HDFCParser.swift:410`, `ICICIParser.swift:198`, `CUBParser.swift:297`)
all use `Decimal(string: amtStr)` on raw email strings that routinely include paise
(e.g., `"1,234.56"` → `Decimal("1234.56")`). Aggregated totals in `SpendSummary` inherit
these fractional parts. This is not an edge case for real users.

**Fix:** Round amounts to 0 decimal places when building the canonical set, using the
same rounding convention as the formatter (half-up / banker's rounding via
`NSDecimalNumber`):

```swift
// In InsightVerifier.buildCanonicalSet(from:)
private static func roundedRupee(_ d: Decimal) -> Decimal {
    var result = Decimal()
    var input = d
    NSDecimalRound(&result, &input, 0, .plain)
    return result
}

static func buildCanonicalSet(from summary: SpendSummary) -> Set<Decimal> {
    var facts = Set<Decimal>()
    facts.insert(roundedRupee(summary.totalSpend))       // ← rounded
    facts.insert(roundedRupee(summary.priorTotalSpend))  // ← rounded
    facts.insert(roundedRupee(abs(summary.delta)))       // ← rounded
    // pct formula unchanged — it is already integer
    let pct = Decimal(abs(Int(summary.deltaFraction * 100)))
    facts.insert(pct)
    for item in summary.categoryBreakdown {
        facts.insert(roundedRupee(item.spentDecimal))    // ← rounded
    }
    for value in summary.priorCategorySpend.values {
        facts.insert(roundedRupee(value))                // ← rounded
    }
    return facts
}
```

Use `.plain` rounding (rounds half away from zero), which matches `NSDecimalNumber`'s
default rounding used by `NumberFormatter`. Alternatively, capture the actual formatted
string value from the prompt formatter and parse it back — either approach produces
consistent fact-set entries.

---

### WR-02: `InsightService.generate()` is unreachable in production — testability seam does not thread through AIInsightCard

**File:** `MyHomeApp/Support/InsightService.swift:178-195`, `MyHomeApp/Features/Analytics/AIInsightCard.swift:202-273`

**Issue:** `AIInsightCard.generateInsight()` creates its own `LanguageModelSession` directly
for both paths:

```swift
// Reduce Motion path (AIInsightCard.swift:210)
let session = LanguageModelSession(instructions: InsightPromptBuilder.systemInstructions)
let response = try await session.respond(to: prompt, generating: SpendInsight.self)

// Streaming path (AIInsightCard.swift:230)
let stream = session.streamResponse(to: prompt, generating: SpendInsight.self)
```

`InsightService.generate()` is never called anywhere in the app target. The
`InsightGenerating` seam exists and is tested via `MockInsightService`, but
`AIInsightCard` does not accept an `InsightGenerating` dependency, so:

1. The fallback logic inside `generateInsight()` (the `catch` block at line 266-272) has
   no automated test coverage. A regression there would only be caught by a physical
   device run.
2. `InsightService.generate()` is dead production code that compiles and links but
   executes on zero code paths. Changes to it have no effect.

**Fix (minimal):** At minimum, document that `InsightService.generate()` is not the
production streaming path — it exists as a non-streaming convenience for tests and future
Reduce Motion use. A larger fix threads the seam through by giving `AIInsightCard` an
optional `InsightGenerating?` initializer parameter (defaulting to `nil`, which triggers
the direct `LanguageModelSession` path) so `AIInsightCard` behaviour can be exercised
from Swift Testing with a mock. If the seam is intentionally unused in production for
the streaming path, mark `InsightService.generate()` with `// Used only in tests /
non-streaming contexts` to prevent future confusion.

---

### WR-03: Verifier guards bare integers ≥ 100 contrary to research's revised Pitfall 5 strategy — produces false rejections

**File:** `MyHomeApp/Support/InsightVerifier.swift:104`

**Issue:**

```swift
// Line 104
guard hasRupeePrefix || hasPercentSuffix || value >= 100 else { continue }
```

The research document (`16-RESEARCH.md`, Pitfall 5, "Revised strategy") explicitly
concluded: *"Skip numbers < 100 in the verifier unless they are %-suffixed. Only flag
rupee amounts ≥ ₹100 and percentage figures."* This means the third clause
`|| value >= 100` should not be present.

With this clause, any bare integer ≥ 100 in the model's prose is checked against the
canonical set. Numbers the model might legitimately include — a day-of-month, a count
("150 transactions"), or a year reference — that are not pre-computed facts cause the
insight to be rejected and the template fallback shown silently. The system prompt
instructs the model not to invent figures, but doesn't forbid all large integers.

**Fix:** Remove the `|| value >= 100` clause; guard only on ₹ prefix and % suffix:

```swift
// InsightVerifier.swift:104
guard hasRupeePrefix || hasPercentSuffix else { continue }
```

This matches the research's revised strategy. The ₹ prefix alone is a sufficient safety
net for rupee amounts, because the model is instructed to use the exact rupee format
from the prompt.

---

## Info

### IN-01: `_spendInsightMemberwiseInitBuildCheck` is a compile-time probe left in the production binary

**File:** `MyHomeApp/Support/InsightService.swift:48-52`

**Issue:** A private function with a leading underscore prefix exists solely to verify
at compile time that `@Generable` preserves the `SpendInsight` memberwise initializer
(Open Question 1, resolved in 16-01-SUMMARY). It is marked `private` and documented
"Never called at runtime," but it still compiles into the production build artifact.

```swift
@available(iOS 26, *)
private func _spendInsightMemberwiseInitBuildCheck() {
    _ = SpendInsight(observation: "open-question-1-build-check", suggestion: nil)
}
```

**Fix:** Wrap in `#if DEBUG` to exclude from release builds, or delete it now that the
question is resolved and recorded in the summary:

```swift
#if DEBUG
@available(iOS 26, *)
private func _spendInsightMemberwiseInitBuildCheck() {
    _ = SpendInsight(observation: "open-question-1-build-check", suggestion: nil)
}
#endif
```

---

## Confirmed Clean

The following focus-area concerns were checked and found correct:

- **Availability gating (D-01/SC-2):** `isInsightAvailable()` exhaustive switch
  (`@unknown default` present) is correct; `AIInsightCard.body` returns nothing on all
  unavailable branches; `AnalyticsView` wraps with `if #available(iOS 26, *)` at the call
  site — keeps the iOS 17.0 deployment target valid.
- **Task cancellation (D-08):** `.task(id: summary.range)` cleanly auto-cancels on range
  change; `CancellationError` is caught first (before the catch-all) and clears state
  silently; `defer { isGenerating = false }` runs on all exit paths including cancellation.
- **Session freshness (Pitfall 3):** A new `LanguageModelSession` is created on every
  `generateInsight()` call — no transcript carryover across range changes.
- **Verifier timing (Pitfall 8):** `InsightVerifier.verify()` is called exactly once after
  the `for try await snapshot in stream` loop exits — never mid-stream on a partial snapshot.
- **Double money prevention:** All rupee formatting in `buildPrompt` and
  `InsightFallbackBuilder` uses `NSDecimalNumber` bridging — no `Double` cast on any
  monetary value.
- **No persistence (AI-05):** `AIInsightCard` contains no `modelContext`, `UserDefaults`,
  `FileManager`, or `SwiftData` access — all insight state lives in `@State`.
- **Prompt injection guard (T-16-03):** `String(cat.name.prefix(30))` present in both
  `buildPrompt` and `InsightFallbackBuilder`.
- **DesignTokens scope:** Violet tokens are clearly scoped to AI use with a comment
  warning; primary canary `#FFD60A` is unchanged.
- **Reduce Motion:** Both streaming and respond() paths respect
  `@Environment(\.accessibilityReduceMotion)` correctly; orb is hidden under Reduce Motion.
- **`String??` handling in streaming:** `if let s = snapshot.content.suggestion` correctly
  skips "field not yet started" outer-nil snapshots while still updating on both
  `.some(nil)` (no suggestion) and `.some("text")`.

---

_Reviewed: 2026-06-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
