---
phase: 20-kitchen-inventory-shopping-list
plan: 03
subsystem: ui
tags: [kitchen, pantry, swiftui, neumorphic, ktch-01, ktch-02, navigation, screenshot-verified]

# Dependency graph
requires:
  - phase: 20-kitchen-inventory-shopping-list
    plan: 01
    provides: SchemaV11 PantryItem (quantity, lowStockThreshold, restockQuantity), SyncStamped
  - phase: 20-kitchen-inventory-shopping-list
    plan: 02
    provides: SyncEntityKind.pantryItem (deleteSynced tombstones), kitchen in SyncScope.production
  - phase: 18-sync-foundation-schema-merge-engine-airdrop
    provides: deleteSynced / touch() LWW contract
provides:
  - "KitchenLogic — StockStatus (inStock/low/out) + stockStatus(quantity:threshold:) as the single source of stock truth for 20-04's derived shopping list"
  - "KitchenLogic.markUsed / markRestocked — clamped-at-zero decrement and additive restock, both touch()-stamping"
  - "KitchenLogic.icon(forName:) — DERIVED name→(SF Symbol, semantic colour) tiles; no schema field, no icon picker"
  - "KitchenView — pushed pantry surface (Running low over Stocked, counts, empty state); 20-04 lifts this content into the Pantry|Shopping segmented host"
  - "PantryItemRow + StockBadge + StepperCircle + KitchenFormat.quantity — reusable row furniture for the 20-04 shopping rows"
  - "EditPantryItemView — add/edit sheet with unit chips, three stepper cards, deleteSynced remove"
  - "Overview Kitchen entry (navigateToKitchen) + DEBUG -openKitchen / -editFirstPantryItem launch hooks"
affects: [20-04, 20-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stock state is DERIVED at render time (KitchenLogic), never stored — two phones cannot disagree about a materialised flag"
    - "Item iconography is derived from the name too: no symbolName/colorHex to sync, diverge, or migrate"
    - "Kitchen is a PUSHED Overview destination, not a 6th tab — iOS caps the native tab bar at 5 before a More spillover, and -startTab indices 0–4 stay byte-identical"
    - "Badges carry text + SF Symbol + semantic tint; colour is never the sole state indicator"

key-files:
  created:
    - MyHomeApp/Features/Kitchen/KitchenLogic.swift
    - MyHomeApp/Features/Kitchen/KitchenView.swift
    - MyHomeApp/Features/Kitchen/PantryItemRow.swift
    - MyHomeApp/Features/Kitchen/EditPantryItemView.swift
    - MyHomeTests/KitchenLogicTests.swift
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Kitchen screen chrome follows the user-supplied mockup (inline nav title 'Kitchen' + toolbar +) rather than the plan's 34pt title header + Add pill — the mockups are the binding visual contract"
  - "Third stepper card reads 'Restock by' with 'Adds this much when you check it off in Shopping.' — the mockup's 'Restock to' text is overridden by the user's binding decision that restock is ADDITIVE"
  - "Icon tiles derived from name keywords with a neutral bag fallback (user decision 2026-07-21) — unit-tested for the mockup's items AND the fallback"
  - "pbxproj registration was split Task 1 (2 files) / Task 2 (3 view files) instead of all-in-Task-1: referencing build inputs that do not exist yet fails the build outright"
  - "Pantry|Shopping segmented control is deliberately absent — 20-04 owns it; KitchenView keeps the pantry content in one place so that becomes a move, not a rewrite"

patterns-established:
  - "Screenshot self-verify needs a reachable state: a DEBUG launch hook (-editFirstPantryItem) is the cheap way to photograph a sheet simctl cannot tap open"
  - "A fresh simulator install shows the first-run bootstrap sheet; set `sync.bootstrapResolved` via `simctl spawn booted defaults write` before a screenshot run"

requirements-completed: [KTCH-01, KTCH-02]

# Metrics
duration: ~55m
completed: 2026-07-21
---

# Phase 20 Plan 03: Pantry Surface Summary

**Built the pantry half of the Kitchen surface to the user's binding mockups — a neumorphic Running-low/Stocked list with derived icon tiles, LOW/OUT badges, 44pt −/+ steppers, and a unit-chip edit sheet — all stock state derived through a single tested `KitchenLogic`, every delete tombstoned via `deleteSynced(kind: .pantryItem)`, and the surface reachable from day one through a pushed Overview entry that leaves the 5-tab bar and `-startTab` indices untouched.**

## What shipped

- **KitchenLogic.swift** — `StockStatus` (`inStock`/`low`/`out`) with `stockStatus(quantity:threshold:)`: zero is always `.out` (even at a zero threshold), at-or-below is `.low` (KTCH-02). `markUsed` decrements by 1 clamped at 0, `markRestocked` adds `restockQuantity`; both call `touch()` so a user action carries an honest LWW clock (18-04) and leave the save to the caller. `icon(forName:)` maps name keywords to an SF Symbol + existing category/semantic colour token, with a neutral `bag.fill` fallback — derived, never stored.
- **PantryItemRow.swift** — icon tile, name + `StockBadge` (text + SF Symbol + `orange`/`negative` twin), "N unit in stock", and two 44pt `StepperCircle` pucks (raised when enabled, recessed + dimmed for `−` at zero). Mutations route through `KitchenLogic`, then `try? context.save()` + `Haptics.selection()`. Also exports `KitchenFormat.quantity` (drops a trailing `.0`).
- **EditPantryItemView.swift** — add AND edit in one sheet: name field with the live derived tile, the mockup's `kg g L ml pcs pack pkt btl` chip row (a stored unit outside the set is preserved and shown as an extra chip), three labelled stepper cards ("In stock", "Low when at or below", "Restock by"), optional category/notes, and a destructive "Remove from pantry" with confirmation. Existing items get `touch()` before save; delete is `context.deleteSynced(item, kind: .pantryItem)` — zero bare `context.delete(` in `Features/Kitchen`. Chips wrap via a local `Layout` conformance (no packages, T-20-SC).
- **KitchenView.swift** — pushed surface with no NavigationStack of its own: "RUNNING LOW" (out first, then low, then alphabetical) above "STOCKED", each a single raised `.neuSurface` card of Divider-separated rows with a right-aligned section count, plus a friendly empty state on `bgCanvas`.
- **OverviewView.swift** — `navigateToKitchen` + `navigationDestination { KitchenView() }` beside the existing Assets/Analytics destinations, a "Kitchen" section header with an "Open pantry" action, and `KitchenGlanceCard` ("6 items · 3 need restocking", tinted with the row badges' semantic twins and an accompanying status symbol). DEBUG `-openKitchen` mirrors `-openAnalytics`; `-startTab`/`-scrollTo`/`-openAnalytics` behaviour is unchanged.
- **MyHomeApp.swift** — `seedSamplePantry` adds 6 items covering all three states (rice/atta/dishwash stocked, milk at threshold and eggs below → LOW, coffee at 0 → OUT), idempotent on an existing pantry.
- **KitchenLogicTests.swift** — 11 tests: the three status boundaries incl. at-threshold and zero-threshold, the item overload, decrement + LWW bump, clamp-at-zero, additive restock + LWW bump, `pantryItem` tombstone-on-delete, and the icon rules incl. case-insensitivity and fallback.

## Deviations from Plan

### Auto-fixed / plan-adjacent

**1. [Rule 3 - Blocking] pbxproj registration split across Task 1 and Task 2**
- **Found during:** Task 1
- **Issue:** The plan asked for all five files (including the three not-yet-written views) to be registered in Task 1. Xcode fails the build outright on a referenced build input that does not exist, so Task 1's own test verification could not have run.
- **Fix:** Task 1 created the `Kitchen` PBXGroup and registered `KitchenLogic.swift` + `KitchenLogicTests.swift`; Task 2 added the three view files with the same 4-edit pattern. End state is identical: all five files show as `… in Sources`.
- **Commits:** `5b9d02c`, `4e1ad40`

**2. [Binding UI contract] Screen chrome follows the mockup, not the plan prose**
- **Found during:** Task 2
- **Issue:** The plan described a 34pt "Kitchen" title header with an "Add" pill (BudgetsView template). `20-REF-pantry.png` instead shows an inline nav bar (`‹ Overview` + "Kitchen") with the sections starting immediately below. `20-UI-REFERENCE.md` states the mockups are binding.
- **Fix:** Inline `navigationTitle("Kitchen")` + a toolbar `+` (the add affordance the plan wanted, in the position the mockup leaves free).
- **Files:** `MyHomeApp/Features/Kitchen/KitchenView.swift`

**3. [Binding user decision] "Restock to" relabelled "Restock by" + derived icon tiles added**
- **Found during:** Task 2
- **Issue:** The mockup's third card says "Restock to / fills back to here", which contradicts the additive `markRestocked` semantics locked by 20-01/20-04. The UI-REFERENCE "Decisions (BINDING)" section resolves this explicitly, and also mandates derived (never stored) icon tiles with a unit-tested fallback — neither is in the plan's task text.
- **Fix:** Card reads "Restock by / Adds this much when you check it off in Shopping."; `KitchenLogic.icon(forName:)` + three icon tests shipped in Task 1.
- **Files:** `KitchenLogic.swift`, `EditPantryItemView.swift`, `KitchenLogicTests.swift`

**4. [Rule 3 - Verification enabler] Extra DEBUG hook and extra screenshots**
- **Found during:** Task 3
- **Issue:** The edit sheet is only reachable by tapping a row, which `simctl` cannot do — it would have shipped visually unverified against `20-REF-edit-sheet.png`.
- **Fix:** DEBUG-only `-editFirstPantryItem` in KitchenView (mirrors the existing `-openAnalytics`/`-scrollTo` hook style). Captured two evidence PNGs beyond the two the plan named: `20-03-light-edit-sheet.png` and `20-03-light-overview-kitchen-card.png`.

**5. [Screenshot-driven fixes]** The first light capture showed truncated names ("Filte…", "Sona Mas…") and wrapped badges ("O U T") because the steppers stretched inside the row HStack. Fixed with `.fixedSize()` on the badge and the stepper pucks plus `minimumScaleFactor` on the name; the edit sheet's stepper columns were likewise pinned to a fixed-width trailing group so all three cards align when a title wraps. Both re-captured and re-checked.

### Not a deviation — deferred by design

The `Pantry | Shopping` segmented control visible in every mockup belongs to 20-04; this plan renders the pantry content directly in `KitchenView` exactly as the plan specifies, so 20-04's host is a move rather than a rewrite.

## Observation for a later plan (not fixed here)

`BootstrapAdvisor.isStoreEffectivelyEmpty` counts notes/expenses/accounts/assets/SIPs/snapshots but not the kitchen kinds, so a phone whose only user data is a pantry is still treated as "fresh" and offered the first-run bootstrap sheet. Bootstrap merges and never deletes, so nothing can be lost — but 20-05 (or a sync follow-up) may want to add the kitchen counts for consistency. Logged here rather than changed, because the counting rule is a sync-scope decision, not a pantry-UI one.

## Verification

- **Acceptance criteria:** zero bare `context.delete(` in `MyHomeApp/Features/Kitchen` (grep = 0); `deleteSynced` present in `EditPantryItemView.swift`; `git diff --stat MyHomeApp/DesignSystem/DesignTokens.swift` empty (no token edits — dark byte-identity untouched); all five Kitchen files registered `in Sources`; `navigateToKitchen` and `openKitchen` present in `OverviewView.swift`; RootView tab structure untouched.
- **Targeted:** `KitchenLogicTests` — 11/11 passed.
- **Full suite serial (`-parallel-testing-enabled NO`): `✔ Test run with 641 tests in 89 suites passed` — 0 failures, DarkBitIdentityTests included.**
- **Screenshot self-verify (iPhone 17, Xcode 26.5):**
  - `20-03-light-pantry.png` — matches `20-REF-pantry.png`: RUNNING LOW (3) over STOCKED (3), OUT badge on Filter coffee with a disabled `−`, LOW badges on Eggs and Milk, icon tiles, full untruncated names.
  - `20-03-dark-pantry.png` — luminous category twins, legible LOW/OUT badges on the dark canvas, recessed disabled `−`.
  - `20-03-light-edit-sheet.png` — matches `20-REF-edit-sheet.png`: Cancel / Edit item / Save, derived tile beside the name, accent-filled `pack` chip, three aligned stepper cards, destructive footer.
  - `20-03-light-overview-kitchen-card.png` — Kitchen section header + "Pantry · 6 items · 3 need restocking" entry card.

## Known Stubs

None. Every rendered value is backed by live `PantryItem` state; no placeholder text and no hardcoded empty collections.

## Threat Flags

None. Trust boundary is unchanged: pantry free text is trimmed and stored as plain `String` properties, rendered with plain `Text` (T-20-06), and the only delete path is `deleteSynced(kind: .pantryItem)` (T-20-07). No packages installed (T-20-SC).

## Self-Check: PASSED

All five created files exist on disk; commits `5b9d02c`, `4e1ad40`, `c811ee5` present in git history; all four evidence PNGs present in the phase directory.
