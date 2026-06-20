---
phase: 13
slug: design-system-foundation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-21
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `13-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (bundled Xcode 26.5) — `import Testing`, `@testable import MyHome` |
| **Config file** | None — existing pattern; tests live in `MyHomeTests/` |
| **Quick run command** | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~90 seconds (build) / ~3–5 min (full suite, simulator boot included) |

---

## Sampling Rate

- **After every task commit:** Run quick build command (confirms compilation — catches missing pbxproj registration immediately).
- **After every plan wave:** Run full suite command.
- **Before `/gsd-verify-work`:** Full suite must be green **and** Xcode Accessibility Inspector manual pass on `NeuSurface` + `NeuTabBar` previews.
- **Max feedback latency:** ~90 seconds (quick build).

---

## Per-Task Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| DS-01 | `DesignTokens.accent` equals `#FFD60A` | unit | `xcodebuild test … -only-testing:MyHomeTests/DesignTokensTests` | ❌ W0 | ⬜ pending |
| DS-01 | `shadowRaised` offsets equal spec (light −6, dark +7) | unit | same | ❌ W0 | ⬜ pending |
| DS-01 | `radiusCard` equals 26 | unit | same | ❌ W0 | ⬜ pending |
| DS-01 | `tabBarClearance` equals 100 | unit | same | ❌ W0 | ⬜ pending |
| DS-02 | `NeuSurface` compiles + renders in preview without crash | preview/build | `xcodebuild clean build` | ❌ W0 | ⬜ pending |
| DS-03 | Tapping tab N sets `selectedTab = N` | manual (preview host) | simulator | Manual | ⬜ pending |
| DS-03 | Programmatic `selectedTab = 3` selects Notes tab (deep-link) | manual (integration) | simulator | Manual | ⬜ pending |
| DS-04 | `reduceMotion = true` → `.identity` transition, zero intermediate frames | unit | `xcodebuild test … -only-testing:MyHomeTests/RollingMoneyTextTests` | ❌ W0 | ⬜ pending |
| DS-04 | `Decimal(123456)` formats as `₹1,23,456.00` (en_IN) | unit | same | ❌ W0 | ⬜ pending |
| DS-05 | No `systemBackground`/`secondarySystemBackground` in `DesignSystem/` | static/grep | `grep -r "systemBackground" MyHomeApp/DesignSystem/` | Automated | ⬜ pending |
| DS-06 | `xcodebuild clean build` succeeds after all pbxproj edits | build gate | full build command | — | ⬜ pending |
| DS-06 | No hardcoded numeric font size in `DesignSystem/` | static/grep | `grep -rE '\.system\(size: [0-9]+' MyHomeApp/DesignSystem/` | Automated | ⬜ pending |
| DS-06 | Accessibility Inspector → zero contrast warnings on NeuSurface/NeuTabBar previews | manual | Xcode Inspector | Manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeApp/DesignSystem/` directory created on disk before any source file is written
- [ ] pbxproj `DesignSystem` group block + 4-edit registration pattern established (PBXBuildFile, PBXFileReference, PBXGroup children, PBXSourcesBuildPhase) — **#1 execution risk; blocks all compilation**
- [ ] `MyHomeTests/DesignTokensTests.swift` — token-value assertions for DS-01
- [ ] `MyHomeTests/RollingMoneyTextTests.swift` — INR formatting + Reduce Motion assertions for DS-04
- [ ] Visual confirmation: `NeuSurface(.recessed)` overlay-gradient inset shadow at spec values (blur 5, ±2px) — open question from research, resolve in a 5-min preview

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tab selection binding propagation | DS-03 | SwiftUI tap-gesture binding not unit-testable without UI host | Run app in simulator, tap each of the 5 tabs, confirm content switches and index matches |
| Deep-link tab selection | DS-03 | Requires running app + notification post | Trigger `kOpenNoteNotification`; confirm Notes tab (index 3) activates |
| Non-text contrast (WCAG 1.4.11, 3:1) | DS-06 | Visual/contrast judgment | Open `NeuSurface` + `NeuTabBar` previews, run Xcode Accessibility Inspector, confirm zero contrast warnings |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (test files, DesignSystem dir, pbxproj group)
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s (quick build)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
