---
phase: 16
slug: ai-insight-card
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-26
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`) — confirmed used by `AnalyticsAggregatorTests.swift` |
| **Config file** | None — Xcode test target configuration via `MyHome.xcodeproj/project.pbxproj` |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/InsightServiceTests -only-testing:MyHomeTests/InsightVerifierTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~90 seconds (full suite); ~25 seconds (insight-only) |

---

## Sampling Rate

- **After every task commit:** Run quick command (`InsightServiceTests` + `InsightVerifierTests`)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green + simulator screenshot verify
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 16-W0-01 | — | 0 | AI-02/03/04 | — | N/A | scaffold | (test stubs + protocol/stub files exist, build green) | ❌ W0 | ⬜ pending |
| 16-avail-01 | — | — | AI-02 | — | Card omitted on `.unavailable(.deviceNotEligible)` | unit | `... -only-testing:MyHomeTests/InsightServiceTests` | ❌ W0 | ⬜ pending |
| 16-avail-02 | — | — | AI-02 | — | Card omitted on `.unavailable(.appleIntelligenceNotEnabled)` | unit | same | ❌ W0 | ⬜ pending |
| 16-avail-03 | — | — | AI-02 | — | Card omitted on `.unavailable(.modelNotReady)` | unit | same | ❌ W0 | ⬜ pending |
| 16-avail-04 | — | — | AI-02 | — | Card shown on `.available` | unit | same | ❌ W0 | ⬜ pending |
| 16-err-01 | — | — | AI-03 | — | `guardrailViolation` → ViewModel → fallback (no crash, no error UI) | unit | same | ❌ W0 | ⬜ pending |
| 16-err-02 | — | — | AI-03 | — | `exceededContextWindowSize` → ViewModel → fallback | unit | same | ❌ W0 | ⬜ pending |
| 16-ver-01 | — | — | AI-04 | — | `InsightVerifier` rejects model-invented number → fallback | unit | `... -only-testing:MyHomeTests/InsightVerifierTests` | ❌ W0 | ⬜ pending |
| 16-ver-02 | — | — | AI-04 | — | `InsightVerifier` passes fact-only numbers unchanged | unit | same | ❌ W0 | ⬜ pending |
| 16-sc5-01 | — | — | AI-05 / SC-5 | — | Deployment target unchanged | shell | `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` returns `17.0` | ✅ | ⬜ pending |
| 16-sc5-02 | — | — | SC-5 | — | Project compiles with FoundationModels behind `#available(iOS 26, *)` | build | `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*(Plan/Wave columns are filled in by the planner once PLAN.md task IDs exist.)*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/InsightServiceTests.swift` — availability branches (AI-02) + generation error cases (AI-03), driven via `MockInsightService` / mock session seam
- [ ] `MyHomeTests/InsightVerifierTests.swift` — number extraction + fact-match + fallback substitution (AI-04)
- [ ] `MyHomeApp/Support/InsightService.swift` — `InsightGenerating: Sendable` protocol declaration (the testability seam; `LanguageModelSession` is `final` and cannot be subclassed)
- [ ] `MyHomeApp/Support/InsightVerifier.swift` — stub needed by `InsightVerifierTests`
- [ ] Wave 0 build-check: confirm `@Generable` preserves memberwise init on `SpendInsight` (Open Question 1 from RESEARCH) before `InsightFallbackBuilder` depends on it

*All new `.swift` and test files MUST be registered in `MyHome.xcodeproj/project.pbxproj` (4 manual edits each — no synchronized groups).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live coherent insight generated on-device, no network | AI-01, AI-03 | FoundationModels produces real output only on an A17 Pro+ device with Apple Intelligence enabled; simulator availability/behavior may differ | Run on physical A17 Pro+ device, open Analytics, confirm a coherent insight appears with no network activity |
| Typewriter character-by-character reveal; Reduce Motion shows full text instantly; orb absent under Reduce Motion | AI-05 (SC-3) | Streaming cadence + animation timing are visual/temporal | Observe reveal on device/simulator; toggle Reduce Motion and re-observe |
| Card silently absent (no shell/gap/spinner) on unavailable device | AI-02 (D-01, SC-2) | End-to-end visual confirmation on an ineligible device | Run on a non-eligible device/sim; confirm Analytics ends cleanly after category bars |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
