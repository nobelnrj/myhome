---
phase: 14
slug: restyle-existing-screens-overview-donut
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-21
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 26.5) |
| **Config file** | none — MyHome.xcodeproj scheme `MyHome` |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests` |
| **Full suite command** | `xcodebuild clean build test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~120 seconds (build + tests) |

---

## Sampling Rate

- **After every task commit:** Run quick build (`xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 150 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 14-XX-XX | TBD | TBD | OVR-05 | — / — | N/A | unit | `xcodebuild test ... -only-testing:MyHomeTests/DonutDataTests` | ❌ W0 | ⬜ pending |

*Planner fills this map per generated plan. Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/DonutDataTests.swift` — top-4 + Others roll-up math and confirmed-self-transfer exclusion for OVR-05
- [ ] Existing XCTest target covers regression flows (CRUD, Gmail sync, self-transfer confirm)

*Restyle (SKIN-*) is primarily visual and verified by `xcodebuild clean build` succeeding with zero stock system colors remaining (grep assertion) — see Manual-Only Verifications.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All 9 screen groups render neumorphic, no stock system colors | SKIN-01..09 | Visual appearance | Launch on iPhone 17 sim; inspect each screen group in dark mode; confirm charcoal surfaces + canary accent + luminous category palette |
| Donut segments fully visible, no card clipping | OVR-05 | Visual layout | Open Overview; confirm all donut segments render inside card bounds |
| Tap donut segment → Activity pre-filtered by category | OVR-06 | Navigation interaction | Tap a donut segment; confirm Activity opens filtered to that category |
| No-regression: CRUD, Gmail sync, self-transfer confirm, Face ID, deep-links | (all) | End-to-end behavior | Exercise each v1.1 flow; confirm identical behavior |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 150s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
