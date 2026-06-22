---
phase: 14-restyle-existing-screens-overview-donut
plan: "03"
subsystem: budgets-ui
tags: [restyle, neumorphic, budgets, skin-03, skin-09]
dependency_graph:
  requires:
    - CategoryStyle rewrite (plan 14-01 — DesignTokens.cat* palette)
    - NeuSurface.swift (plan 13 — .neuSurface modifier)
    - DesignTokens.swift (plan 13 — bgCanvas, label*, positive, negative, accent, etc.)
  provides:
    - Fully neumorphic Budgets screen group (SKIN-03)
    - Budget summary ring as floating hero card
    - Category budget cards as tappable raised cards
  affects:
    - Budgets screen appearance (all cards now .neuSurface)
    - StackBar component (fillRecessed instead of tertiarySystemFill)
tech_stack:
  added: []
  patterns:
    - .neuSurface(.floating) for hero summary ring card
    - .neuSurface(.raised, isInteractive: true) for tappable category cards
    - .neuSurface(.recessed) for EditBudgetSheet input well
    - scrollContentBackground(.hidden) + bgCanvas on all List/ScrollView
    - DesignTokens semantic colors (negative/orange/positive) for budget thresholds
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Budgets/BudgetsView.swift
    - MyHomeApp/Features/Shared/StackBar.swift
    - MyHomeApp/Features/Budgets/BudgetCategoryCard.swift
    - MyHomeApp/Features/Budgets/BudgetProgressView.swift
    - MyHomeApp/Features/Budgets/EditBudgetSheet.swift
    - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
    - MyHomeApp/Features/Budgets/FilteredExpenseListView.swift
decisions:
  - Ring color threshold logic: remaining < 0 -> negative, fraction > 0.85 -> orange, else positive (matches UI-SPEC)
  - EditBudgetSheet amount section: replaced .background(secondarySystemBackground).clipShape with .neuSurface(.recessed, radius: DesignTokens.radiusInner)
  - FilteredExpenseListView and UncategorizedExpenseListView both get bgCanvas + listRowBackground(surfaceRaised)
metrics:
  duration_minutes: ~5
  completed_date: "2026-06-22"
  tasks_completed: 2
  files_changed: 7
---

# Phase 14 Plan 03: Budgets Screen Restyle Summary

**One-liner:** Neumorphic Budgets group restyle — floating summary ring hero, tappable raised category cards, DesignTokens semantic colors throughout, and canvas background on all list/scroll views.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Restyle BudgetsView + summary ring hero + StackBar | 933e65f | BudgetsView.swift, StackBar.swift |
| 2 | Restyle remaining Budgets files | ac2cd11 | BudgetCategoryCard.swift, BudgetProgressView.swift, EditBudgetSheet.swift, ManageCategoriesView.swift, FilteredExpenseListView.swift |

## Verification Results

- `grep -rnE 'Color\(\.(secondary|system|tertiary)|\.cardStyle\(' MyHomeApp/Features/Budgets/ MyHomeApp/Features/Shared/StackBar.swift | grep -v '//' | wc -l`: **0**
- `grep -c 'neuSurface(.floating' MyHomeApp/Features/Budgets/BudgetsView.swift`: **2** (empty state + summary ring)
- `grep -c 'neuSurface' MyHomeApp/Features/Budgets/BudgetCategoryCard.swift`: **1**
- `grep -rn 'accentColor' MyHomeApp/Features/Budgets/`: **0**
- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`: **BUILD SUCCEEDED**

## Deviations from Plan

None — plan executed exactly as written.

The plan listed `.neuSurface(.floating, padding: 22)` as line 258 (empty state), which is correct. The summary ring (budgeted content) at line 304 maps to `.neuSurface(.floating, padding: 20)` — both confirmed at 2 floating hero usages. The EditBudgetSheet amount section's `.background(secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 12))` was replaced with `.neuSurface(.recessed, radius: DesignTokens.radiusInner)` per the UI-SPEC input well pattern.

## Known Stubs

None. All deliverables are fully wired:
- Budget summary ring renders real aggregation data (budgeted array from BudgetsMonthView)
- Category cards use CategoryStyle.color(for:) which returns DesignTokens.cat* after Plan 14-01 rewrite
- Progress bar colors use semantic tokens (negative/orange/positive) for budget threshold states

## Threat Flags

None. This plan introduced no new network endpoints, auth paths, file access patterns, or schema changes.

T-14-06 (EditBudgetSheet existing input): accepted — validation/save logic unchanged, only color and surface styling modified.

## Self-Check: PASSED

- [x] MyHomeApp/Features/Budgets/BudgetsView.swift — modified (3 cardStyle -> neuSurface, all system colors replaced)
- [x] MyHomeApp/Features/Shared/StackBar.swift — modified (tertiarySystemFill -> fillRecessed)
- [x] MyHomeApp/Features/Budgets/BudgetCategoryCard.swift — modified (cardStyle -> neuSurface .raised interactive, all system colors replaced)
- [x] MyHomeApp/Features/Budgets/BudgetProgressView.swift — modified (all system colors replaced)
- [x] MyHomeApp/Features/Budgets/EditBudgetSheet.swift — modified (system colors + background replaced)
- [x] MyHomeApp/Features/Budgets/ManageCategoriesView.swift — modified (all system colors replaced, bgCanvas added)
- [x] MyHomeApp/Features/Budgets/FilteredExpenseListView.swift — modified (bgCanvas + listRowBackground added)
- [x] Commits 933e65f, ac2cd11 — confirmed in git log
