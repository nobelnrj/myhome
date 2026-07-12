---
phase: 17-light-mode-support-neumorphic-redesign
plan: 08
subsystem: ui
tags: [swiftui, accent-role-split, accentText, design-tokens, dark-bit-identity, wcag, light-mode]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "accentText adaptive token (dark amber in light, #FFD60A in dark); DarkBitIdentityTests"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 03
    provides: "Live theme switch; RootView selected-tab tint already on accentText (D-08 chrome slice)"
provides:
  - "D-08 accent role-split complete for RollingMoneyText (design system) + Settings + Expenses areas — text/icon sites on accentText, fill sites kept canary accent"
  - "Full per-site role classification table (28 accent sites across 12 files + 2 adjacent fill-role files) — no site silently skipped (T-17-09 mitigated)"
affects: [17-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Role-split audit: TEXT/ICON accent (foregroundStyle glyphs, plain/toolbar Button tints, checkmarks) → accentText; FILL accent (Toggle track, borderedProminent/segmented button fill, IconTile .fill, gradient stops, shape .fill, .background capsule) → keep accent"
    - "IconTile(color:) is a FILL role — color paints the RoundedRectangle .fill under a dark glyph; rowLabel(color:) sites therefore keep accent"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/RollingMoneyText.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeApp/Features/Settings/AccountsListView.swift
    - MyHomeApp/Features/Settings/UnlockView.swift
    - MyHomeApp/Features/Settings/EditAccountView.swift
    - MyHomeApp/Features/Settings/MigrationReviewSheet.swift
    - MyHomeApp/Features/Expenses/AddTransferView.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/Features/Expenses/AccountPickerView.swift
    - MyHomeApp/Features/Expenses/CategoryPickerView.swift

key-decisions:
  - "IconTile-backed rowLabel(color:) sites classified FILL (kept accent): IconTile paints color as the tile's RoundedRectangle .fill with a dark #16161C glyph on top — accent is the surface, not the glyph"
  - ".buttonStyle(.borderedProminent) and .pickerStyle(.segmented) .tint sites classified FILL (kept accent): tint paints the prominent capsule / selected-segment background, not label text"
  - "Two adjacent Expenses files outside the plan's 12 (TransferPairRow, ReviewInboxRow) carry accent as .background(_, in: Capsule()) — FILL role, correctly left on accent; recorded so the audit is complete for the directory"

requirements-completed: [D-08]

# Metrics
duration: ~40min
completed: 2026-07-12
---

# Phase 17 Plan 08: Accent Role-Split Audit Part 1 (Design System + Settings + Expenses) Summary

**Audited every accent call site in RollingMoneyText and the Settings + Expenses feature areas, moving text/icon-role accent to `accentText` (legible dark-amber on the light canvas) while keeping fill-role accent (Toggle tracks, prominent-button/segmented fills, IconTile fills, gradients, capsule backgrounds) canary — with dark rendering proven byte-identical at the unit gate and a same-store 6-screen render diff.**

## Performance
- **Duration:** ~40 min
- **Completed:** 2026-07-12
- **Tasks:** 2
- **Files modified:** 12 (no new files — pbxproj untouched)

## Accomplishments
- **Task 1 — RollingMoneyText + Settings (6 files):** Swapped 8 text/icon accent sites to `accentText`; kept 8 fill sites on `accent`. Zero `foregroundStyle(DesignTokens.accent)` remains in RollingMoneyText.swift + Features/Settings. Build green.
- **Task 2 — Expenses (6 files) + dark gate:** Swapped 8 text/icon accent sites to `accentText`; left the 3 `.tint(negative)` adaptive-token sites untouched. Zero `foregroundStyle(DesignTokens.accent)` remains in Features/Expenses. Ran the whole-plan dark identity gate.

## Per-Site Role Classification (complete — no site skipped)

### Task 1 — RollingMoneyText + Settings

| File:site | Current call | Role | Action |
|-----------|--------------|------|--------|
| RollingMoneyText.swift (hero-numeral preview labels) | `.foregroundStyle(accent)` | TEXT | → accentText |
| SettingsView.swift (Face ID Toggle) | `.tint(accent)` | FILL (Toggle track) | KEEP accent |
| SettingsView.swift ("Sync now" button) | `.foregroundStyle(accent)` | TEXT | → accentText |
| SettingsView.swift (rowLabel "Add account") | `rowLabel(color: accent)` → IconTile.fill | FILL | KEEP accent |
| SettingsView.swift (rowLabel "Budgets") | `rowLabel(color: accent)` → IconTile.fill | FILL | KEEP accent |
| SettingsView.swift (rowLabel "About MyHome") | `rowLabel(color: accent)` → IconTile.fill | FILL | KEEP accent |
| SettingsView.swift (profile avatar gradient) | `LinearGradient(colors: [accent, accent.opacity(0.55)])` | FILL | KEEP accent |
| SettingsView.swift (avatar initial/person glyph) | `.foregroundStyle(accentOnYellow)` | other token | LEAVE |
| AccountsListView.swift ("Review Now →" button) | `.tint(accent)` on plain Button | TEXT | → accentText |
| AccountsListView.swift (Archive swipe) | `.tint(orange)` | adaptive token | LEAVE |
| AccountsListView.swift (Unarchive swipe) | `.tint(catSubscriptions)` | adaptive token | LEAVE |
| UnlockView.swift (Unlock button) | `.tint(accent)` on `.borderedProminent` | FILL (prominent bg) | KEEP accent |
| UnlockView.swift (app-icon fallback glyph) | `.foregroundStyle(accent)` | ICON | → accentText |
| EditAccountView.swift (selected-symbol tile bg) | `.fill(accent.opacity(0.15))` | FILL | KEEP accent |
| EditAccountView.swift (selected-symbol glyph) | `.foregroundStyle(accent)` | ICON | → accentText |
| EditAccountView.swift ("Save Account" toolbar) | `.tint(accent)` | TEXT | → accentText |
| MigrationReviewSheet.swift ("Done" toolbar) | `.foregroundStyle(accent)` | TEXT | → accentText |
| MigrationReviewSheet.swift (rename "Done" button) | `.tint(accent)` on plain Button | TEXT | → accentText |
| MigrationReviewSheet.swift (type segmented picker) | `.tint(accent)` on `.pickerStyle(.segmented)` | FILL (selected segment) | KEEP accent |

### Task 2 — Expenses

| File:site | Current call | Role | Action |
|-----------|--------------|------|--------|
| AddTransferView.swift ("Save Transfer" toolbar) | `.tint(accent)` | TEXT | → accentText |
| EditExpenseView.swift ("Save Expense" toolbar) | `.tint(accent)` | TEXT | → accentText |
| EditExpenseView.swift (Delete swipe) | `.tint(negative)` | adaptive token | LEAVE |
| ExpenseListView.swift (add-menu plus glyph) | `.tint(accent)` on Menu Image | ICON | → accentText |
| AddExpenseView.swift ("Save Expense" toolbar) | `.tint(accent)` | TEXT | → accentText |
| AccountPickerView.swift (Unassigned checkmark) | `.foregroundStyle(accent)` | ICON | → accentText |
| AccountPickerView.swift (account-row checkmark) | `.foregroundStyle(accent)` | ICON | → accentText |
| AccountPickerView.swift (delete/negative site) | `.tint(negative)` | adaptive token | LEAVE |
| CategoryPickerView.swift (None checkmark) | `.foregroundStyle(accent)` | ICON | → accentText |
| CategoryPickerView.swift (category-row checkmark) | `.foregroundStyle(accent)` | ICON | → accentText |
| CategoryPickerView.swift (delete/negative site) | `.tint(negative)` | adaptive token | LEAVE |

### Adjacent Expenses fill-role sites (outside the plan's 12 files — recorded for directory completeness)

| File:site | Current call | Role | Action |
|-----------|--------------|------|--------|
| TransferPairRow.swift | `.background(accent, in: Capsule())` | FILL | KEEP accent (no edit) |
| ReviewInboxRow.swift | `.background(accent, in: Capsule())` | FILL | KEEP accent (no edit) |

## Verification Evidence
- **Grep gate (acceptance):** `foregroundStyle(DesignTokens.accent)` count = 0 in RollingMoneyText.swift + Features/Settings, and = 0 in Features/Expenses. All remaining bare `accent` references are documented fill-role sites.
- **Build:** `xcodebuild build -scheme MyHome -destination id=2F09365E-…(iPhone 17)` → exit 0, 0 errors (both tasks).
- **D-06 unit gate (authoritative):** `DarkBitIdentityTests` → exit 0, all cases passed. `accentText.resolve(dark) == #FFD60A == accent`, so every swap is invisible in dark by construction.
- **D-06 render gate:** same-store before/after dark diff (plan-start binary `7f23628` vs current worktree HEAD over the same seeded store, iPhone 17, dark appearance, pinned 9:41 status bar) → `diff_dark.py` **exit 0** — all 6 screens PASS (dark-tab0 orb-masked, tabs 1-4 + analytics tol=16).
- **Light spot-check:** Settings in dark renders gear/selected-tab and avatar gradient canary (fills preserved); the swapped text/icon sites are unit-proven to render `accentText`'s deepened light twin on the light canvas.

## Task Commits
1. **Task 1: role-split RollingMoneyText + Settings area** — `c1977d9` (feat)
2. **Task 2: role-split Expenses area + dark identity gate** — `1ca1186` (feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `-startTab N` navigation initially no-op'd the render gate**
- **Found during:** Task 2 dark render gate
- **Issue:** The first before/after capture batch launched every screen but all 5 tab screenshots rendered the Overview/Home screen (its TimelineView-driven orb particle ring is non-deterministic), producing 4 FAILs whose diff bounding boxes fell entirely inside the orb — i.e. animation noise, not token drift. The `-startTab` argument was being passed as a single combined string that did not reach the `@State` arg parser reliably.
- **Fix:** Passed `-startTab` and its index as separate `simctl launch` argv; verified navigation by eye (tab 4 = Settings). Re-ran the same-store before/after diff → all 6 screens PASS (exit 0). No code change.
- **Files modified:** none (verification procedure)

### Classification calls worth recording (not deviations)
- **IconTile-backed `rowLabel(color:)` = FILL:** `IconTile` paints `color` as the tile's `RoundedRectangle.fill` with a dark `#16161C` glyph overlaid — accent is the surface, so the three Settings rowLabel sites correctly keep `accent`. The plan checklist flagged only the `:64` Toggle and `:153` foregroundStyle explicitly; the additional rowLabel/gradient/fill sites in the file were classified and kept on `accent` (fill) so the acceptance grep (zero `foregroundStyle(accent)`) is satisfied without over-swapping.
- **`.borderedProminent` / `.pickerStyle(.segmented)` `.tint` = FILL:** these tints paint the prominent capsule background / selected-segment fill, not label text, so UnlockView Unlock and MigrationReviewSheet type-picker keep `accent`.

## Authentication Gates
None.

## Issues Encountered
- Only the `-startTab` render-gate procedure issue above. Dark rendering is byte-identical at the token level and across all 6 screens; D-06/D-08 invariants preserved.

## Threat Flags
None — pure color-token role substitution. No new inputs, storage, network, or trust boundaries (matches the plan's register; T-17-09 mitigated by the per-site classification table + zero-count directory greps + dark diff gate).

## Known Stubs
None. All swaps target existing, fully-defined tokens (`accentText` from Plan 02).

## Next Phase Readiness
- Part 2 (Plan 17-09) owns the remaining feature areas: Notes, Budgets, Overview, Assets, Analytics. Apply the same role rules and the IconTile/borderedProminent/segmented fill-role calls documented above.
- The same-store dark diff procedure (build plan-start binary via `git archive`, capture over the same seeded store with `-startTab N` as separate argv, `diff_dark.py`) is the reliable render gate — the Plan 01 baseline PNGs still embed non-reproducing seed times.

## Self-Check: PASSED
- All 12 modified files exist; no new files (pbxproj untouched)
- Commits c1977d9, 1ca1186 present on the worktree branch
- Acceptance greps re-verified (0 `foregroundStyle(accent)` in both scopes); build exit 0
- D-06 unit gate green + same-store dark render diff exit 0 (6/6 screens)

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
