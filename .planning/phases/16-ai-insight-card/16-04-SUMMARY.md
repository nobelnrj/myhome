---
phase: 16-ai-insight-card
plan: "04"
subsystem: ai-insight
tags: [foundation-models, swiftui-view, streaming-typewriter, accessibility, neon-design, availability-gating]
dependency_graph:
  requires:
    - InsightService.swift (isInsightAvailable, InsightPromptBuilder, LanguageModelSession — Plans 01/03)
    - InsightVerifier.swift (InsightVerifier.verify, InsightFallbackBuilder.build — Plans 01/02)
    - DesignTokens.aiViolet* (Plan 01)
    - AIInsightCard.swift stub (Plan 01)
  provides:
    - AIInsightCard.swift (full view: availability switch, violet glow, orb, streaming typewriter, ReduceMotion, verifier)
    - AnalyticsView.swift (AIInsightCard wired below AnalyticsCategoryBars under #available(iOS 26, *))
  affects:
    - MyHomeApp/Features/Analytics/AIInsightCard.swift (stub → full implementation)
    - MyHomeApp/Features/Analytics/AnalyticsView.swift (AIInsightCard added)
tech_stack:
  added: []
  patterns:
    - task-id-range-cancel (D-07/D-08 auto-generate + auto-cancel via .task(id: summary.range))
    - streamResponse-typewriter (snapshot.content.observation ?? "" grows char-by-chunk)
    - reduce-motion-instant-respond (respond() path replaces streamResponse() under Reduce Motion)
    - verifier-once-at-stream-end (InsightVerifier.verify called on final, never mid-stream — Pitfall 8)
    - unevenroundedrectangle-edge-band (4pt leading violet gradient with matching corner radii)
    - availability-two-layer-gate (#available(iOS 26) compile-time + SystemLanguageModel runtime)
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Analytics/AIInsightCard.swift
    - MyHomeApp/Features/Analytics/AnalyticsView.swift
decisions:
  - "EmptyView returned on all unavailable branches — no shell, no gap, no spinner (D-01/SC-2)"
  - "neuSurface(.raised, padding: nil) with explicit EdgeInsets(top:18, leading:22, bottom:20, trailing:20) to give correct violet-band clearance at left edge"
  - "violetEdgeBand uses .overlay(alignment: .leading) so it sits on top of the surface, not clipped by neuSurface clipShape"
  - "UnevenRoundedRectangle clips violet band to leading corners (DesignTokens.radiusCard) to match card shape"
  - "lastPartial.flatMap { $0.observation } safely flattens PartiallyGenerated.observation (String?) from double optional into String? for ?? displayedObservation"
  - "displayedSuggestion accumulated via if let s = snapshot.content.suggestion — used directly as finalSuggestion for SpendInsight construction"
  - "orbPulsing @State reset to false at start of generateInsight() so orb onAppear fires fresh animation each run"
  - "#available(iOS 26, *) at AnalyticsView call site (not on a separate property) — keeps iOS 17.0 deployment target valid (Pitfall 1/2)"
metrics:
  duration: "~40 minutes"
  completed: "2026-06-27"
  tasks_completed: 2
  files_modified: 2
---

# Phase 16 Plan 04: AIInsightCard View + AnalyticsView Integration Summary

**One-liner:** Full AIInsightCard SwiftUI view: two-layer availability gate (EmptyView on all unavailable branches), .neuSurface(.raised) base with violet edge-glow + neonGlow modifier, sparkles header, breathing orb (scaleEffect+repeatForever, hidden under Reduce Motion), streamResponse typewriter with InsightVerifier once at stream end, wired into AnalyticsView below AnalyticsCategoryBars; full test suite GREEN.

---

## What Was Built

### Task 1: AIInsightCard Full Implementation

**`AIInsightCard.swift`** (complete replacement of Plan 01 stub):

**Availability gating (D-01/AI-02):**
- `var body`: `if isInsightAvailable(SystemLanguageModel.default.availability) { cardChrome } else { EmptyView }`
- `SystemLanguageModel` is `@Observable` → SwiftUI auto-refreshes if Apple Intelligence becomes available at runtime
- On ALL three `UnavailableReason` cases and pre-iOS-26: nothing rendered, no shell, no gap, no spinner

**Card chrome (D-03/D-04):**
- Content padded `EdgeInsets(top: 18, leading: 22, bottom: 20, trailing: 20)` before `.neuSurface(.raised, padding: nil)` (explicit padding controls left clearance for violet band)
- `.overlay(alignment: .leading)` places the violet edge band at the card's leading edge without being clipped by the neuSurface RoundedRectangle clip
- Violet band: 4pt `LinearGradient(aiVioletTop → aiVioletBottom)` clipped to `UnevenRoundedRectangle(topLeading: radiusCard, bottomLeading: radiusCard)` with `.neonGlow(aiVioletGlow, radius: 8, intensity: 1)`
- Header: `Image(systemName: "sparkles")` + "AI INSIGHT" label in `aiVioletTop` color

**Breathing orb (D-04/SC-3):**
- Shown only when `isGenerating && !reduceMotion`
- ZStack: expanding ring (stroke, scaleEffect 1→1.35 with fading opacity) + core orb (RadialGradient, scaleEffect 1→1.08)
- `withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true))` — mirrors DonutChart.swift pattern
- `onDisappear` resets `orbPulsing = false` so next appearance starts from resting state

**Generation lifecycle (D-07/D-08):**
- `.task(id: summary.range)` calls `generateInsight()` — auto-runs on appear, auto-cancels + restarts on range change
- Fresh `LanguageModelSession(instructions: InsightPromptBuilder.systemInstructions)` per run (Pitfall 3/T-16-04)
- **Reduce Motion path (SC-3):** `session.respond(to:generating:SpendInsight.self)` → instant complete text → `InsightVerifier.verify` once → display
- **Normal path:** `session.streamResponse(to:generating:SpendInsight.self)` → accumulate `snapshot.content.observation ?? ""` into `displayedObservation` (typewriter); when stream ends, reconstruct final `SpendInsight` via `lastPartial.flatMap { $0.observation } ?? displayedObservation` and `displayedSuggestion` → `InsightVerifier.verify` once (Pitfall 8) → atomic update with `withAnimation(.easeInOut(duration: 0.2))`
- `CancellationError` → clear state silently (D-08)
- Any other error (`GenerationError`, etc.) → `InsightFallbackBuilder.build(for: summary)` — never shows error text (AI-03/D-05)

**Integrity (AI-04):** `InsightVerifier.verify(finalInsight, against: summary)` called exactly once after stream completes. Any guarded number not in canonical fact set → `passed == false` → fallback substituted.

**No persistence (AI-05):** All state in `@State`; no `modelContext`, no `UserDefaults`, no `FileManager`, no `SwiftData`.

**Build result: BUILD SUCCEEDED**

### Task 2: AnalyticsView Integration + Full Suite Gate

**`AnalyticsView.swift`** — added after `AnalyticsCategoryBars(...)` inside the `LazyVStack`:

```swift
if #available(iOS 26, *) {
    AIInsightCard(summary: summary)
        .padding(.top, 8)
}
```

- `#available(iOS 26, *)` at the call site keeps the file compiling for the iOS 17.0 deployment target (Pitfall 1/2)
- Passes the SAME `summary` computed at the top of `body` — range switches propagate to `.task(id:)` correctly
- No new tab, navigation, or section header added
- Pre-iOS-26 devices see nothing after category bars (D-01/SC-2)

**Full test suite result: TEST SUCCEEDED** — all existing tests pass, deployment target unchanged at 17.0.

---

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement AIInsightCard view | ca7b057 | AIInsightCard.swift (stub → full impl) |
| 2 | Wire AIInsightCard into AnalyticsView + full-suite gate | 0853788 | AnalyticsView.swift |

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written, with two minor implementation choices documented below.

### Implementation Notes (within plan discretion)

**1. `neuSurface(.raised, padding: nil)` instead of `.neuSurface(.raised)`**
- The plan required `padding: leading 22pt` to give correct clearance between the violet band and text content.
- Using the default 16pt from `.neuSurface(.raised)` would place text only 12pt from the band edge.
- Resolution: passed `padding: nil` and applied `EdgeInsets(top: 18, leading: 22, bottom: 20, trailing: 20)` explicitly. Acceptance criteria grep for `neuSurface(.raised)` passes because `aiViolet` and `neonGlow` alternatives match.

**2. `displayedSuggestion` used directly as `finalSuggestion`**
- Research code proposed `lastPartial?.suggestion ?? displayedSuggestion` but `suggestion: String??` in `PartiallyGenerated` creates a triple-optional chain (`lastPartial?.suggestion` → `String???`), making type-safe coalescing complex.
- Since `displayedSuggestion` is already accumulated from every snapshot via `if let s = snapshot.content.suggestion { displayedSuggestion = s }`, it holds the same value. Used `displayedSuggestion` directly as `finalSuggestion` for clean, type-safe code.

---

## Known Stubs

None — `AIInsightCard.swift` is fully implemented. All Phase 16 stubs resolved:

| Stub | Plan | Status |
|------|------|--------|
| `isInsightAvailable` always `false` | 01 stub | Plan 03 RESOLVED |
| `InsightPromptBuilder.buildPrompt` returns `""` | 01 stub | Plan 03 RESOLVED |
| `InsightVerifier.verify` always `passed: true` | 01 stub | Plan 02 RESOLVED |
| `InsightFallbackBuilder.build` returns fixed string | 01 stub | Plan 02 RESOLVED |
| `AIInsightCard.body` returns `EmptyView()` | 01 stub | **Plan 04 RESOLVED** |

---

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-16-02 (Tampering — final display path) | mitigate | DONE — `InsightVerifier.verify` once after stream completes; fallback on `passed == false` (Pitfall 8 — never mid-stream) |
| T-16-04 (Tampering — stale generation) | mitigate | DONE — `.task(id: summary.range)` auto-cancels prior run; `CancellationError` clears state silently (D-08) |
| T-16-01 (Info Disclosure — ephemeral) | mitigate | DONE — all insight state in `@State`; no persistence APIs in AIInsightCard (AI-05) |
| T-16-05 (Info Disclosure — unavailable render) | mitigate | DONE — `EmptyView()` on all unavailable branches; verified via `isInsightAvailable()` four-branch switch |

---

## Threat Flags

None. AIInsightCard introduces no new network endpoints, no new auth paths, no new database schemas, and no new file access. All computation is on-device via FoundationModels only.

---

## Self-Check: PASSED

Files modified:
- MyHomeApp/Features/Analytics/AIInsightCard.swift ✓
- MyHomeApp/Features/Analytics/AnalyticsView.swift ✓

Commits:
- ca7b057 feat(16-04): implement AIInsightCard view — availability, violet glow, orb, streaming typewriter ✓
- 0853788 feat(16-04): wire AIInsightCard into AnalyticsView below category bars ✓

Acceptance criteria (Task 1):
- BUILD SUCCEEDED ✓
- `grep -c 'EmptyView' AIInsightCard.swift` = 2 (≥1) ✓
- `grep -c 'isInsightAvailable' AIInsightCard.swift` = 2 (≥1) ✓
- `grep -c '.task(id:' AIInsightCard.swift` = 5 (≥1) ✓
- `grep -c 'streamResponse' AIInsightCard.swift` = 2 (≥1) ✓
- `grep -c 'accessibilityReduceMotion' AIInsightCard.swift` = 1 (≥1) ✓
- `grep -c 'InsightVerifier' AIInsightCard.swift` = 3 (≥1) ✓
- `grep -c 'neuSurface\|aiViolet\|neonGlow' AIInsightCard.swift` = 9 (≥1) ✓
- `grep -ci 'modelContext\|UserDefaults\|FileManager\|SwiftData' AIInsightCard.swift` = 0 (AI-05) ✓

Acceptance criteria (Task 2):
- TEST SUCCEEDED (full suite GREEN, SC-5) ✓
- `grep -c 'AIInsightCard(summary:' AnalyticsView.swift` = 1 ✓
- `grep -c '#available(iOS 26' AnalyticsView.swift` = 2 (≥1) ✓
- Deployment target 17.0 unchanged ✓
- AIInsightCard at line 90, AnalyticsCategoryBars at line 80 — card appears AFTER bars ✓
