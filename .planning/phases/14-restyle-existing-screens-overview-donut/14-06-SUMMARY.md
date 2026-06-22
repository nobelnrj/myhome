---
phase: 14-restyle-existing-screens-overview-donut
plan: "06"
subsystem: UI/Restyle
tags: [neumorphic, accounts, assets, net-worth, SKIN-06, SKIN-07, SKIN-09]
dependency_graph:
  requires: ["14-01"]
  provides: [SKIN-06, SKIN-07]
  affects: [AccountsListView, AccountDetailView, EditAccountView, NetWorthCard, AssetsListView, AssetDetailView, EditAssetView, NetWorthTrendChart, StalenessView, AMFISchemePickerView, NPSSchemePickerView, ReconcileView, SIPSetupView, ContributionLogView]
tech_stack:
  added: []
  patterns: [neuSurface(.floating), neuSurface(.raised), DesignTokens.positive/negative/orange/catSubscriptions/catAuto/label/label2/accent, canvas background rule]
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Settings/AccountDetailView.swift
    - MyHomeApp/Features/Settings/AccountsListView.swift
    - MyHomeApp/Features/Settings/EditAccountView.swift
    - MyHomeApp/Features/Assets/NetWorthCard.swift
    - MyHomeApp/Features/Assets/AssetsListView.swift
    - MyHomeApp/Features/Assets/AssetDetailView.swift
    - MyHomeApp/Features/Assets/EditAssetView.swift
    - MyHomeApp/Features/Assets/NetWorthTrendChart.swift
    - MyHomeApp/Features/Assets/StalenessView.swift
    - MyHomeApp/Features/Assets/AMFISchemePickerView.swift
    - MyHomeApp/Features/Assets/NPSSchemePickerView.swift
    - MyHomeApp/Features/Assets/ReconcileView.swift
    - MyHomeApp/Features/Assets/SIPSetupView.swift
    - MyHomeApp/Features/Assets/ContributionLogView.swift
decisions:
  - "NetWorthCard donut segments: systemBlue->catSubscriptions (MF), systemGreen->positive (Stocks), systemOrange->orange (NPS), systemTeal->catAuto (Cash) — matches PATTERNS.md lines 452-473"
  - "Balance color zero case: primary->.label (accounts) and label2 (assets) — zero balance uses muted token not label for consistency with label tier semantics"
  - "NetWorthTrendChart: Color.accentColor swapped to DesignTokens.positive (not accent yellow) — trend line reads as gain/positive signal, not nav accent"
  - "ContributionLogView estimate badge: .orange->.orange (token), .green->.positive (token) — semantic mapping; reconciled entries are a positive-state"
metrics:
  duration: "8 min"
  completed: "2026-06-22"
  tasks: 2
  files: 14
---

# Phase 14 Plan 06: Accounts + Assets Restyle Summary

Neumorphic restyle of 14 files across the Accounts (SKIN-06) and Assets/Net-worth (SKIN-07) screen groups. All stock system colors removed; `.cardStyle()` hero sites migrated to `.neuSurface(.floating)`; account balance sign convention and SIP/NPS NAV flows unregressed (SKIN-09).

## What Was Built

**Task 1 — Accounts list/detail/edit (SKIN-06):**
- `AccountDetailView`: `.cardStyle()` → `.neuSurface(.floating)` floating hero; `systemRed`/`systemGreen` → `negative`/`positive`; `.secondary` → `label2`; canvas background on List.
- `AccountsListView`: `systemOrange` → `orange`; `systemBlue` → `catSubscriptions`; `.accentColor` → `accent`; balance color helper swapped to `positive`/`negative`/`label2`; canvas background.
- `EditAccountView`: `systemRed` → `negative`; `systemOrange` → `orange`; `.accentColor` → `accent`; symbol picker cells use `fillRecessed` background and `accent` tint for selected state.

**Task 2 — Assets / Net-worth group (SKIN-07):**
- `NetWorthCard`: `.cardStyle(cornerRadius: 16, padding: 18)` → `.neuSurface(.floating, radius: 26, padding: 18)`; donut segments recolored MF→`catSubscriptions`, Stocks→`positive`, NPS→`orange`, Cash→`catAuto`; legend text → `label`/`label2`; donut center → `label2`/`label`.
- `AssetDetailView`: `.cardStyle()` → `.neuSurface(.floating)`; `gainColor` `systemGreen`/`systemRed` → `positive`/`negative`; all `.primary`/`.secondary` → `label`/`label2`; canvas background.
- `AssetsListView`: `assetColor()` helper swapped to `catSubscriptions`/`positive`/`orange`; row text → `label`/`label2`; canvas background.
- `NetWorthTrendChart`: `Color.accentColor` → `DesignTokens.positive` for line and area fill; empty state `.secondary` → `label2`.
- `StalenessView`: `Color(.systemOrange)` → `DesignTokens.orange`.
- `AMFISchemePickerView`/`NPSSchemePickerView`: `.accentColor` → `accent`; `.primary`/`.secondary` → `label`/`label2`; canvas background.
- `ReconcileView`/`SIPSetupView`: `.accentColor` → `accent`; sum validation color `.secondary`/`.red` → `label2`/`negative`.
- `EditAssetView`: `systemRed` → `negative`; `.accentColor` → `accent`; `.secondary` → `label2`.
- `ContributionLogView`: `.orange`/`.green` badge colors → `orange`/`positive`; all `.primary`/`.secondary` → `label`/`label2`; canvas background.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | aea717e | feat(14-06): restyle Accounts list/detail/edit neumorphic (SKIN-06) |
| 2 | b2dbb3a | feat(14-06): restyle Assets / Net-worth group neumorphic (SKIN-07) |

## Verification

- `grep -rnE 'Color\(\.(secondary|system|tertiary)|accentColor|\.cardStyle\(' MyHomeApp/Features/Settings/Account*.swift | grep -v '//' | wc -l` → **0**
- `grep -rnE 'Color\(\.(secondary|system|tertiary)|accentColor|\.cardStyle\(' MyHomeApp/Features/Assets/ | grep -v '//' | wc -l` → **0**
- `grep -c 'neuSurface(.floating)' MyHomeApp/Features/Settings/AccountDetailView.swift` → **1**
- `grep -c 'neuSurface(.floating' MyHomeApp/Features/Assets/NetWorthCard.swift` → **1**
- `grep -c 'DesignTokens.catSubscriptions' MyHomeApp/Features/Assets/NetWorthCard.swift` → **2**
- Build: **SUCCEEDED**

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

No new network surface, endpoints, or schema changes introduced. All changes are view-layer color token swaps only. T-14-10 (account balance sign convention) verified: only colors changed, baseline−net math in `AccountBalance.compute()` untouched.

## Self-Check: PASSED

- All 14 modified files exist and contain DesignTokens references.
- Commits aea717e and b2dbb3a verified in git log.
- Build SUCCEEDED on iPhone 17 simulator.
