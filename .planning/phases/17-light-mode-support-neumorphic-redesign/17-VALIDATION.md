---
phase: 17
slug: light-mode-support-neumorphic-redesign
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-11
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`, Xcode test target MyHomeTests) |
| **Config file** | none — Xcode-managed target |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination "id=2F09365E-5099-490E-9484-B8788C53C816" -only-testing:MyHomeTests/DesignTokensTests -quiet` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination "id=2F09365E-5099-490E-9484-B8788C53C816" -quiet` |
| **Render gate** | `python3 .planning/phases/17-light-mode-support-neumorphic-redesign/diff_dark.py <baselines> <after_dir>` (orb region masked on tab0) |
| **Estimated runtime** | quick run ~30s warm; full suite several minutes |

---

## Sampling Rate

- **After every task commit:** quick run (DesignTokensTests: dark-bit-identity + contrast + theme mapping)
- **After every plan wave:** dark screenshot sweep + diff_dark.py vs Plan 01 baselines
- **Before `/gsd-verify-work`:** full suite green + double dark sweep (system-dark AND pinned-dark) + light review set (Plan 07)
- **Max feedback latency:** one quick test run per task

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | D-06 | — | N/A | scripted | diff_dark.py self-diff exit 0 | ❌ W0 (this task creates it) | ⬜ pending |
| 17-01-02 | 01 | 1 | D-06 | T-17-01 | malformed hex → gray fallback | build+grep | xcodebuild build + grep adaptive | ✅ | ⬜ pending |
| 17-01-03 | 01 | 1 | D-06 | — | N/A | unit | quick run (DarkBitIdentityTests, AdaptiveFactoryTests) | ✅ extends existing | ⬜ pending |
| 17-02-01 | 02 | 2 | D-04/08/09/10/13 | — | N/A | unit+grep | quick run + zero Color(hex:) in DesignTokens | ✅ | ⬜ pending |
| 17-02-02 | 02 | 2 | D-14, D-06 | — | N/A | build+grep | build + 4 unchanged neonGlow call sites | ✅ | ⬜ pending |
| 17-02-03 | 02 | 2 | D-06/08/09/10/15 | — | N/A | unit+render | quick run (ContrastTests) + diff_dark.py exit 0 | ✅ | ⬜ pending |
| 17-03-01 | 03 | 3 | D-01, D-02 | T-17-03 | garbage UserDefaults → .system | unit | quick run (AppearanceThemeTests) | ✅ | ⬜ pending |
| 17-03-02 | 03 | 3 | D-03 | — | N/A | build+grep | build + Section("Appearance") count 1 | ✅ | ⬜ pending |
| 17-03-03 | 03 | 3 | D-07, D-08, D-06 | T-17-04 | privacy blur scheme-independent | grep+render | zero foregroundStyle(accent) outside NeuSurface + dark diff | ✅ | ⬜ pending |
| 17-04-01 | 04 | 6 | D-05, D-06, D-08 | T-17-05 | no alpha multiplication on adaptive tokens | unit+render | quick run + dark diff | ✅ | ⬜ pending |
| 17-04-02 | 04 | 6 | D-04, D-05 | — | N/A | unit + manual-visual | quick run; light screenshots (tuning is the deliverable) | ✅ | ⬜ pending |
| 17-04-03 | 04 | 6 | D-06 (preview hygiene) | — | N/A | build+grep | 4 light preview pins | ✅ | ⬜ pending |
| 17-05-01 | 05 | 7 | D-11/12/13, D-06 | T-17-06 | override on content only | unit+render+grep | quick run + dark diff + env-override count | ✅ | ⬜ pending |
| 17-05-02 | 05 | 7 | D-12, D-14, D-06 | T-17-06 | same | unit+render+grep | quick run + dark diff + 2 override sites | ✅ | ⬜ pending |
| 17-05-03 | 05 | 7 | D-13 | — | N/A | unit + manual-visual | quick run (dishSlate contrast floors) | ✅ | ⬜ pending |
| 17-06-01 | 06 | 8 | D-12, D-06 | T-17-07 | light-only insets never render in dark | unit+render+grep | quick run + dark diff tabs 0/3/analytics + zero #FFB43C | ✅ | ⬜ pending |
| 17-06-02 | 06 | 8 | D-09 | — | N/A | unit+grep+visual | quick run + zero hex in IconTile | ✅ | ⬜ pending |
| 17-06-03 | 06 | 8 | D-15 | — | N/A | unit+grep+visual | quick run + aiViolet scope == 2 files | ✅ | ⬜ pending |
| 17-07-01 | 07 | 9 | D-06 (final gate) | — | N/A | full suite+render | full suite + double dark sweep exit 0 | ✅ | ⬜ pending |
| 17-07-02 | 07 | 9 | D-01/02/14 + A2/A7 | T-17-08 | blur over light surfaces | scripted+human-check | light set ≥6 + end-of-phase sign-off | ✅ | ⬜ pending |
| 17-08-01 | 08 | 4 | D-08 | T-17-09 | accent role-split, no silent partial pass | build+grep | build + grep foregroundStyle(accent) in RollingMoneyText+Settings == 0 | ✅ | ⬜ pending |
| 17-08-02 | 08 | 4 | D-08, D-06 | T-17-09 | same + dark identity | build+grep+render | build + grep Expenses accent == 0 + dark diff | ✅ | ⬜ pending |
| 17-09-01 | 09 | 5 | D-08 | T-17-10 | accent role-split | build+grep | build + grep Notes/Budgets accent == 0 | ✅ | ⬜ pending |
| 17-09-02 | 09 | 5 | D-08, D-06 | T-17-10 | app-wide accent gate | build+grep+render | build + app-wide grep accent (excl NeuSurface) == 0 + dark diff | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Baseline dark screenshots (5 tabs + Analytics, pinned status bar) captured on unmodified main — **before the first token edit** (Plan 01 Task 1)
- [ ] `diff_dark.py` masked-pixel diff script (Plan 01 Task 1)
- [ ] `MyHomeTests/DesignTokensTests.swift` extended: DarkBitIdentityTests (38-token legacy hex table), AdaptiveFactoryTests (A1/A3), contrastRatio helper; hexString assertion removed (Plan 01 Task 3)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Light-mode neumorphic quality (depth, slate harmony, glow whisper) | D-04/05/13/14 | Visual tuning IS the deliverable; no pixel oracle exists for "same object under different lighting" | Simulator screenshot loop per plan; final device review in Plan 07 human-check |
| In-app tap flip of Appearance row (live re-theme, no stale drawingGroup rasters) | D-01/D-03 (A7) | simctl cannot tap; requires interactive session | Plan 07 human-check step 2 |
| Sheet/keyboard/lock-overlay scheme inheritance when pinned ≠ system | D-01 (A2) | Sheets unreachable via launch args | Plan 07 human-check step 4 |
| Final both-theme sign-off, all 5 tabs + Analytics | phase gate | config human_verify_mode = end-of-phase | Plan 07 `<human-check>` block |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (Wave 0 = Plan 01)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (baselines, diff script, identity tests)
- [x] No watch-mode flags
- [x] Feedback latency: one quick xcodebuild test run per task
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending (set green statuses during execution; final approval in Plan 07 Task 2)
