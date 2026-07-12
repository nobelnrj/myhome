---
phase: 17-light-mode-support-neumorphic-redesign
plan: 09
subsystem: ui
tags: [swiftui, accent-role-split, accentText, design-tokens, dark-bit-identity, wcag, light-mode]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "accentText adaptive token (#755C00 light / #FFD60A dark); DarkBitIdentityTests + accentTextFloor contrast test"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 08
    provides: "D-08 part 1 (Design System + Settings + Expenses); fill-vs-text role precedents (IconTile fill, borderedProminent, segmented picker = FILL)"
provides:
  - "D-08 accent role-split complete for Notes/Budgets/Overview/Assets/Analytics — text/icon accent on accentText, fill accent kept canary"
  - "App-wide D-08 closure: zero foregroundStyle(DesignTokens.accent) anywhere outside NeuSurface.swift:288 (delegated to Plan 04)"
  - "Full per-site classification of every accent call site in these 5 feature areas (no site skipped, T-17-10 mitigated) + Gate B .tint(accent) cross-reference"
affects: [17-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Role-split rule (D-08): text/icon accent (foregroundStyle glyphs+labels, plain/toolbar Button .tint, checkmarks, chevrons, custom-segmented selected label) → accentText; fill accent (Toggle track, ProgressView tint, IconTile fill, gradient stops, neonGlow tint, shadow, shape/capsule .fill/.background, chart element color) → keep canary accent"
    - "ProgressView(value:).tint(accent) is a FILL role — tint paints the progress-bar track fill, not label text (CalendarView day-progress); kept canary"
    - "Custom segmented control (AnalyticsView range picker) paints selected-segment fill with surfaceElevatedControl and the selected LABEL with accent → the accent is text-role → accentText (distinct from native .pickerStyle(.segmented) whose tint is the fill)"

key-files:
  created: []
  modified:
    - MyHomeApp/Features/Notes/AddNoteView.swift
    - MyHomeApp/Features/Notes/CalendarView.swift
    - MyHomeApp/Features/Notes/NotesListView.swift
    - MyHomeApp/Features/Notes/ReminderEditView.swift
    - MyHomeApp/Features/Notes/NoteRow.swift
    - MyHomeApp/Features/Notes/EditNoteView.swift
    - MyHomeApp/Features/Budgets/EditBudgetSheet.swift
    - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
    - MyHomeApp/Features/Budgets/BudgetsView.swift
    - MyHomeApp/Features/Overview/PinnedNoteCard.swift
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeApp/Features/Assets/ReconcileView.swift
    - MyHomeApp/Features/Assets/AMFISchemePickerView.swift
    - MyHomeApp/Features/Assets/NPSSchemePickerView.swift
    - MyHomeApp/Features/Assets/SIPSetupView.swift
    - MyHomeApp/Features/Assets/EditAssetView.swift
    - MyHomeApp/Features/Analytics/DeltaDrillDownSheet.swift
    - MyHomeApp/Features/Analytics/AnalyticsView.swift

key-decisions:
  - "ProgressView(value:).tint(accent) classified FILL (kept accent): tint paints the progress-bar track, not text — CalendarView:378 remains canary and is the sole 17-09-owned Gate B remainder"
  - "Ternary text/icon accent sites (checkboxes, today-date, month chevron, custom-segmented selected label) swapped to accentText even though the plan's exact-pattern checklist did not enumerate them — required by must_have truth #1 (all accent TEXT/ICONS in these areas use accentText) and dark-safe (accentText==accent in dark)"
  - "Five files carrying qualifying text/icon accent sites outside the plan's 14 (EditNoteView, SpendBudgetCard, SIPSetupView, EditAssetView, AnalyticsView) were also role-split to make the audit complete for the 5 feature areas app-wide"

requirements-completed: [D-08]

# Metrics
duration: ~55min
completed: 2026-07-12
---

# Phase 17 Plan 09: Accent Role-Split Audit Part 2 (Notes + Budgets + Overview + Assets + Analytics) Summary

**Audited every `DesignTokens.accent` call site across the Notes, Budgets, Overview, Assets, and Analytics feature areas, moving text/icon-role accent to `accentText` (legible dark-amber on the light canvas) while keeping fill-role accent (Toggle/ProgressView tracks, IconTile fills, gradients, neonGlow, shadows, capsule/shape fills, chart element colors) canary — then closed the D-08 audit app-wide (Gate A returns 0 outside `NeuSurface.swift:288`, which is delegated to Plan 04) with dark rendering proven byte-identical at the authoritative unit gate and corroborated by a same-store 6-screen render diff (exit 0).**

## Performance
- **Duration:** ~55 min
- **Completed:** 2026-07-12
- **Tasks:** 2
- **Files modified:** 19 (no new files — pbxproj untouched)

## Accomplishments
- **Task 1 — Notes + Budgets (9 files):** Swapped 15 text/icon accent sites to `accentText`; kept all fill sites (selection/dot fills, ProgressView tint, capsule bg, neonGlow, gradient, shadow, budget-progress bar color). Gate A exact-pattern grep = 0 in Features/Notes + Features/Budgets. Build green.
- **Task 2 — Overview + Assets + Analytics (10 files) + app-wide closure:** Swapped 16 text/icon accent sites to `accentText`; kept fill sites (IconTile fill, neonGlow, gradients, selection bg, chart color). Closed the app-wide D-08 audit: Gate A = 0 outside `NeuSurface.swift`; Gate B remainder (4 `.tint(accent)`) all cross-referenced to documented fill-role verdicts. Dark identity gate green (unit + same-store render diff).

## Per-Site Role Classification (complete — no site skipped)

### Task 1 — Notes + Budgets

| File:line | Current call | Role | Action |
|-----------|--------------|------|--------|
| AddNoteView.swift:47 | `.tint(accent)` "Add Note" toolbar button | TEXT/nav | → accentText |
| CalendarView.swift:181 | `isToday ? accent : label` day number | TEXT | → accentText |
| CalendarView.swift:185 | `.fill(isSelected ? accent.opacity(0.15) : clear)` | FILL | KEEP accent |
| CalendarView.swift:191 | `.fill(accent)` reminder dot | FILL | KEEP accent |
| CalendarView.swift:378 | `.tint(accent)` on `ProgressView(value:)` | FILL (bar track) | KEEP accent |
| CalendarView.swift:393 | `item.isChecked ? accent : label3` checkbox icon | ICON | → accentText |
| CalendarView.swift:564 | `isCompleteToday ? accent : label3` checkbox icon | ICON | → accentText |
| NotesListView.swift:73 | `.tint(accent)` "plus" toolbar button | ICON | → accentText |
| ReminderEditView.swift:228 | `.tint(accent)` "Save" confirmation button | TEXT/nav | → accentText |
| ReminderEditView.swift:291 | `.foregroundStyle(accent)` date value text | TEXT | → accentText |
| ReminderEditView.swift:369 | `.fill(selected ? accent : fillRecessed)` chip | FILL | KEEP accent |
| ReminderEditView.swift:400 | `.foregroundStyle(accent)` end-date value text | TEXT | → accentText |
| NoteRow.swift:64 | `.foregroundStyle(accent)` reminder badge text+bell | TEXT/ICON | → accentText |
| NoteRow.swift:67 | `.background(accent.opacity(0.12), in: Capsule())` | FILL | KEEP accent |
| NoteRow.swift:87 | `block.isChecked ? accent : label3` checkbox icon | ICON | → accentText |
| EditNoteView.swift:256 | `block.isChecked ? accent : label3` checkbox icon | ICON | → accentText (dev — see below) |
| EditNoteView.swift:306 | `.fill(focused ? accent.opacity(0.15) : clear)` | FILL | KEEP accent |
| EditBudgetSheet.swift:87 | `.tint(accent)` "Save Budget" toolbar button | TEXT/nav | → accentText |
| EditBudgetSheet.swift:146 | `.tint(negative)` | adaptive token | LEAVE (unmodified) |
| ManageCategoriesView.swift:52 | `.tint(accent)` "Done" add button | TEXT | → accentText |
| ManageCategoriesView.swift:139 | `.tint(accent)` "Done" rename button | TEXT | → accentText |
| BudgetsView.swift:81 | `.foregroundStyle(accent)` chevron.left prev-month | ICON | → accentText |
| BudgetsView.swift:97 | `isAtCurrentMonth ? label3 : accent` chevron.right | ICON | → accentText |
| BudgetsView.swift:260 | `.foregroundStyle(accent)` chart.pie empty-state icon | ICON | → accentText |
| BudgetsView.swift:263 | `.neonGlow(accent, ...)` | FILL (glow tint) | KEEP accent |
| BudgetsView.swift:349 | `LinearGradient(colors: [accent, positive])` | FILL | KEEP accent |
| BudgetsView.swift:355 | `.shadow(color: (over ? negative : accent)...)` | FILL | KEEP accent |
| BudgetProgressView.swift:19 | `case .normal: return accent` (progress bar color) | FILL | KEEP accent (no edit) |

### Task 2 — Overview + Assets + Analytics

| File:line | Current call | Role | Action |
|-----------|--------------|------|--------|
| PinnedNoteCard.swift:63 | `.foregroundStyle(accent)` pin.fill glyph | ICON | → accentText |
| PinnedNoteCard.swift:91 | `.tint(accent)` "Open note" button | TEXT/nav | → accentText |
| PinnedNoteCard.swift:107 | `.tint(accent)` "Go to Notes" button | TEXT/nav | → accentText |
| OverviewView.swift:328 | `.foregroundStyle(accent)` section-action button | TEXT | → accentText |
| OverviewView.swift:329 | `.tint(accent)` same section-action button | TEXT/nav | → accentText |
| OverviewView.swift:353 | `IconTile(color: accent, ...)` | FILL (tile fill) | KEEP accent |
| OverviewView.swift:354 | `.neonGlow(accent, ...)` | FILL (glow tint) | KEEP accent |
| SpendBudgetCard.swift:140 | `.tint(accent)` "Set a budget →" button | TEXT/nav | → accentText (dev) |
| SpendBudgetCard.swift:220 | `LinearGradient(colors: [accent, positive])` | FILL | KEEP accent |
| SpendByCategoryChart.swift:30 | `var color = accent` (chart element default) | FILL | KEEP accent (no edit) |
| SpendOverTimeChart.swift:91 | `LinearGradient(colors: [accent, negative])` | FILL | KEEP accent (no edit) |
| ReconcileView.swift:95 | `.tint(accent)` "Confirm Units" toolbar button | TEXT/nav | → accentText |
| AMFISchemePickerView.swift:80 | `.tint(accent)` "Fetch Now" button | TEXT/nav | → accentText |
| AMFISchemePickerView.swift:109 | `.foregroundStyle(accent)` selected checkmark | ICON | → accentText |
| AMFISchemePickerView.swift:115 | `? accent.opacity(0.12)` row selection bg | FILL | KEEP accent |
| NPSSchemePickerView.swift:86 | `.tint(accent)` "Fetch Now" button | TEXT/nav | → accentText |
| NPSSchemePickerView.swift:124 | `.foregroundStyle(accent)` selected checkmark | ICON | → accentText |
| NPSSchemePickerView.swift:130 | `? accent.opacity(0.12)` row selection bg | FILL | KEEP accent |
| SIPSetupView.swift:253 | `.tint(accent)` "Save SIP" toolbar button | TEXT/nav | → accentText (dev) |
| EditAssetView.swift:225 | `.tint(accent)` "Save Holding" toolbar button | TEXT/nav | → accentText (dev) |
| DeltaDrillDownSheet.swift:80 | `.foregroundStyle(accent)` "Done" toolbar button | TEXT | → accentText |
| AnalyticsView.swift:153 | `selection == range ? accent : label2` segmented selected label | TEXT | → accentText (dev) |
| AnalyticsTrendChart.swift:105 | `LinearGradient(colors: [accent, negative])` | FILL | KEEP accent (no edit) |

## App-Wide D-08 Gate Evidence

- **Gate A** — `grep -rn 'foregroundStyle(DesignTokens.accent)' MyHomeApp --include="*.swift" | grep -v NeuSurface.swift` → **0 lines**. The only remaining `foregroundStyle(accent)` in the codebase is `NeuSurface.swift:288` (`NeuSecondaryButtonStyle`), explicitly delegated to Plan 04 alongside that file's shadow-token work.
- **Gate B** — every remaining `.tint(DesignTokens.accent)` app-wide is a documented fill-role verdict:

| File:line | Control | Role | Documented in |
|-----------|---------|------|---------------|
| Settings/SettingsView.swift:75 | Face ID Toggle track | FILL | 17-08 SUMMARY |
| Settings/MigrationReviewSheet.swift:130 | `.pickerStyle(.segmented)` type picker | FILL (selected segment) | 17-08 SUMMARY |
| Settings/UnlockView.swift:45 | `.borderedProminent` Unlock button | FILL (prominent bg) | 17-08 SUMMARY |
| Notes/CalendarView.swift:378 | `ProgressView(value:)` day-progress | FILL (bar track) | 17-09 (this plan) |

## Verification Evidence
- **Build:** `xcodebuild build -scheme MyHome -destination id=2F09365E-…(iPhone 17)` → exit 0 for both tasks (pre-existing UINotificationFeedbackGenerator actor warnings only, no errors).
- **Gate A grep:** 0 in Features/Notes + Features/Budgets (Task 1) and 0 app-wide outside NeuSurface (Task 2).
- **D-06/D-08 unit gate (authoritative):** `DarkBitIdentityTests`, `DesignTokensTests`, `ContrastTests`, `AppearanceThemeTests` → exit 0, all cases passed. `accentColorMatchesSpec` (accent == #FFD60A in dark), `accentTextFloor` (accentText ≥ 4.5:1 on bgCanvas). Since `accentText.resolve(dark) == accent == #FFD60A`, every swap is invisible in dark by construction.
- **D-06 render gate (same-store before/after):** base binary built from plan-start commit `bd51163` in a throwaway detached worktree; installed over the SAME seeded data container as the current binary (reinstall preserves container); dark appearance; pinned 9:41 status bar; captured all 6 screens (`-startTab 0-4` + `-openAnalytics`, each arg as separate argv per 17-08 lesson); `diff_dark.py before after` → **exit 0**, all 6 screens PASS (dark-tab0 orb-masked, tol=16).

## Deviations from Plan

### Auto-fixed / completeness-driven (Rule 2 — missing critical functionality for D-08 truth #1)

**1. [Rule 2] Ternary text/icon accent sites swapped to accentText**
- **Found during:** Tasks 1 & 2 full-directory audit
- **Issue:** must_have truth #1 requires ALL accent TEXT/ICONS in these 5 areas to use `accentText`, but the plan's per-file checklist enumerated only exact-pattern (`foregroundStyle(DesignTokens.accent)` / `.tint(accent)`) sites — it did not list ternary sites (`cond ? accent : other`) that are also text/icon role: checkbox glyphs, calendar today-date, month chevron, custom-segmented selected label. Left as canary they would render illegible on the light canvas.
- **Fix:** Swapped the ternary text/icon sites to `accentText` (CalendarView:181/393/564, NoteRow:87, BudgetsView:97, AnalyticsView:153). Dark-safe (accentText==accent in dark; render diff exit 0).
- **Files modified:** CalendarView.swift, NoteRow.swift, BudgetsView.swift, AnalyticsView.swift
- **Commits:** accfc10, 73ba2f8

**2. [Rule 2] Five files outside the plan's 14 role-split for area completeness**
- **Found during:** Tasks 1 & 2 audit of the 5 feature directories
- **Issue:** truth #1 is scoped to the feature AREAS, not just the enumerated files. Five files in those directories carried qualifying text/icon accent sites but were not in `files_modified`: EditNoteView.swift (checkbox icon), SpendBudgetCard.swift ("Set a budget" CTA), SIPSetupView.swift ("Save SIP"), EditAssetView.swift ("Save Holding"), AnalyticsView.swift (segmented selected label).
- **Fix:** Role-split each (all text/nav/icon → accentText). Their fill sites (SpendBudgetCard:220 gradient, SpendByCategoryChart:30, SpendOverTimeChart:91, AnalyticsTrendChart:105) were classified FILL and left on accent.
- **Files modified:** EditNoteView.swift, SpendBudgetCard.swift, SIPSetupView.swift, EditAssetView.swift, AnalyticsView.swift
- **Commits:** accfc10, 73ba2f8

### Classification calls worth recording (not deviations)
- **ProgressView(value:).tint(accent) = FILL:** CalendarView:378 tints the progress-bar track, not text → kept canary; it is the only 17-09-owned Gate B remainder.
- **Custom segmented control label = TEXT:** AnalyticsView:153 paints the selected-segment fill with `surfaceElevatedControl` and the selected LABEL with accent, so accent here is text-role → accentText (distinct from native `.pickerStyle(.segmented)` where tint is the fill, per 17-08).
- **`ReminderEditView:228` is a Save button, not a Toggle:** the plan checklist flagged it "(Toggle = KEEP)" as a guess; the actual control is the "Save" confirmationAction Button → text-role → accentText.

## Authentication Gates
None.

## Issues Encountered
None blocking. Status-bar override initially rejected `--wifibars` (correct flag is `--wifiBars`); re-issued with correct casing before both capture passes so before/after status bars are identical.

## Threat Flags
None — pure color-token role substitution. No new inputs, storage, network, or trust boundaries (matches the plan's register; T-17-10 mitigated by the complete per-site classification table + app-wide Gate A/B cross-reference + same-store dark render diff).

## Known Stubs
None. All swaps target the existing `accentText` token (Plan 02).

## Next Phase Readiness
- D-08 is now complete across the entire app EXCEPT `NeuSurface.swift:288` (`NeuSecondaryButtonStyle` accent-text on a raised pill), which Plan 04 owns and will swap alongside that file's shadow-token work. After Plan 04, Gate A (`foregroundStyle(accent)`) is 0 with no exclusions.
- The same-store before/after dark diff procedure (build plan-start commit in a detached `git worktree`, reinstall over the shared data container, capture with separate-argv `-startTab N` / `-openAnalytics`, `diff_dark.py`) remains the reliable render gate — the Plan 01 baseline PNGs still embed non-reproducing seed times.

## Self-Check: PASSED
- All 19 modified files exist; no new files (pbxproj untouched)
- Commits accfc10, 73ba2f8 present on the worktree branch
- Gate A re-verified = 0 (Notes+Budgets and app-wide outside NeuSurface); Gate B remainder = 4 documented fill-role sites
- Build exit 0; unit gate green (DarkBitIdentityTests + accentTextFloor); same-store dark render diff exit 0 (6/6 screens)

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
