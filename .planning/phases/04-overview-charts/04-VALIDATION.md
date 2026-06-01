---
phase: 4
slug: overview-charts
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-01
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (bundled, no SPM dep) |
| **Config file** | Xcode Test Plan (existing `MyHomeTests` target) |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SpendOverTimeAggregatorTests -only-testing:MyHomeTests/OverviewAggregationTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~60–120 seconds (simulator boot + build) |

---

## Sampling Rate

- **After every task commit:** Run quick command (SpendOverTimeAggregatorTests + OverviewAggregationTests)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Req ID | Behavior | Test Type | Automated Command (target) | File Exists | Status |
|--------|----------|-----------|----------------------------|-------------|--------|
| OVR-01 | Aggregate bar: fractionUsed = totalSpend / totalBudget; thresholds 0.8 / 1.0 | unit | `MyHomeTests/OverviewAggregationTests` | ❌ W0 | ⬜ pending |
| OVR-01 | "No budget set" when totalBudget == 0 | unit | `MyHomeTests/OverviewAggregationTests` | ❌ W0 | ⬜ pending |
| OVR-02 | Top-3 sorted by spend desc; tie-break alphabetical; <3 renders correctly | unit | `MyHomeTests/OverviewAggregationTests` | ❌ W0 | ⬜ pending |
| OVR-03 | Pinned note surfaced; fallback to checklist note; empty when neither | unit | `MyHomeTests/OverviewAggregationTests` | ❌ W0 | ⬜ pending |
| OVR-04 | Quick-add `+` presents existing Add Expense sheet | manual smoke | app launch → tap `+` → sheet appears | — | ⬜ pending |
| EXP-10 | Spend-by-category chart (display-only; data from BudgetCalculator) | unit (existing) | `MyHomeTests/BudgetCalculatorTests` | ✅ | ⬜ pending |
| EXP-11 | Week→7 daily, Month→28-31 daily, Year→12 monthly; all slots emitted | unit | `MyHomeTests/SpendOverTimeAggregatorTests` | ❌ W0 | ⬜ pending |
| EXP-11 | Zero-spend range: all buckets present with spent = 0.0 | unit | `MyHomeTests/SpendOverTimeAggregatorTests` | ❌ W0 | ⬜ pending |
| EXP-11 | Decimal→Double conversion: no money rounding in display | unit | `MyHomeTests/SpendOverTimeAggregatorTests` | ❌ W0 | ⬜ pending |
| D4-01 | Tab reorder: Overview tag 0 (default), Notes tag 3, deep-link re-tagged | manual smoke | app launch → check tab order + Notes banner deep-link | — | ⬜ pending |
| formattedINRCompact() | < 1000 → "₹N"; ≥ 1000 → "₹Nk"; ≥ 100000 → "₹NL" | unit | `MyHomeTests/DecimalINRTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/SpendOverTimeAggregatorTests.swift` — EXP-11 bucketing (week/month/year), zero-spend slots, Decimal→Double boundary
- [ ] `MyHomeTests/OverviewAggregationTests.swift` — OVR-01 threshold math, OVR-02 top-3 sort + tie-break, OVR-03 pinned/fallback/empty logic
- [ ] `MyHomeTests/DecimalINRTests.swift` — `formattedINRCompact()` thresholds (< 1000, 1000–99999, ≥ 100000) — only if the planner introduces `formattedINRCompact()`

**Note:** `BudgetCalculatorTests.swift` already exists and covers `monthlySpend`, `monthBoundaries`, `BudgetProgressData`, and `BudgetColor`. No new tests needed for those existing helpers.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Quick-add `+` presents the existing Add Expense sheet | OVR-04 | Sheet presentation is a SwiftUI UI behavior, not pure logic | Launch app → Overview tab → tap `+` → confirm full Add Expense sheet appears |
| Tab order + default landing tab | D4-01 | TabView ordering / launch tab is visual | Launch app → confirm lands on Overview (tag 0); order Overview→Expenses→Budgets→Notes; tap a Notes banner deep-link → lands on Notes (tag 3) |
| Charts render with real data and degrade to empty states | EXP-10, EXP-11, D4-07 | Chart rendering + empty-state copy is visual | Launch with data → charts populate; launch with no spend → "No spend yet" states (not blank/broken charts) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
