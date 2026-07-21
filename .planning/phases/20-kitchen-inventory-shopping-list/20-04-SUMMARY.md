---
phase: 20-kitchen-inventory-shopping-list
plan: 04
subsystem: ui
tags: [kitchen, shopping-list, swiftui, neumorphic, ktch-03, derived-state, screenshot-verified]

# Dependency graph
requires:
  - phase: 20-kitchen-inventory-shopping-list
    plan: 01
    provides: SchemaV11 ShoppingListItem (isChecked/checkedAt), PantryItem.restockQuantity, SyncStamped
  - phase: 20-kitchen-inventory-shopping-list
    plan: 02
    provides: SyncEntityKind.shoppingListItem + ShoppingListItemDTO (deleteSynced tombstones, snapshot round-trip)
  - phase: 20-kitchen-inventory-shopping-list
    plan: 03
    provides: KitchenLogic (stockStatus/markRestocked/icon), KitchenView, PantryItemRow furniture, -openKitchen hook
  - phase: 18-sync-foundation-schema-merge-engine-airdrop
    provides: deleteSynced / touch() LWW contract
provides:
  - "KitchenLogic.deriveShoppingItems(from:) — pure out-first/low-then/alphabetical filter over pantry rows; the auto shopping list, never materialised"
  - "KitchenLogic.toggleChecked(_:) — manual-extra check state + checkedAt + LWW touch(); never mutates the pantry"
  - "ShoppingListView — RESTOCK (derived) + EXTRAS (manual) sections, inline add, Clear checked, compact edit sheet, empty state"
  - "ShoppingRow — one row view serving .derived(PantryItem) / .manual(ShoppingListItem) with a leading CheckCircle and the '↻ + N unit' RestockPill"
  - "KitchenView — Pantry | Shopping segmented host with an accent restock badge; pantry content lifted verbatim into PantryListView"
  - "DEBUG -kitchenTab <0|1> launch hook + seeded manual extras for screenshot self-verify"
affects: [20-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "The auto shopping list is a PURE FUNCTION of pantry state — derived at render time, never written as rows, so two phones cannot mint duplicate auto entries (20-01 locked design, T-20-08)"
    - "One row view, two identities via an enum (.derived / .manual) — the two list semantics cannot be confused at a call site"
    - "Check-off consequence is visible before the tap: the derived row's '↻ + N unit' pill states exactly what markRestocked will add"
    - "Custom neumorphic segmented control (not .pickerStyle(.segmented)) because the mockup's segment carries a count badge the native control cannot render"

key-files:
  created:
    - MyHomeApp/Features/Kitchen/ShoppingListView.swift
    - MyHomeApp/Features/Kitchen/ShoppingRow.swift
    - MyHomeTests/ShoppingListTests.swift
  modified:
    - MyHomeApp/Features/Kitchen/KitchenLogic.swift
    - MyHomeApp/Features/Kitchen/KitchenView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Manual extras are deleted via context menu (Edit / Delete) + a 'Clear checked' header action instead of swipe-to-delete: the mockup's card is a neumorphic VStack, not a List, and .swipeActions only exists inside List — converting would have thrown away the binding visual contract"
  - "The empty state keeps an 'Add item…' field the mockup omits: with both sections empty there would otherwise be no way to add a manual extra at all (Rule 2 — missing critical functionality)"
  - "Derived rows never render as 'checked' — checking one restocks its pantry item and the row simply stops being derived, which is the honest representation of a list with no stored auto rows"
  - "Restock badge on the Shopping segment counts derived rows PLUS unchecked manual extras (everything still to buy), not just the derived count"

patterns-established:
  - "neuSurface on a fixed-size decoration needs .fixedSize(): a flexible parent stretches the well into an oval / full-width bar (bit the check circle and the empty-state tile)"
  - "A bare Circle() under .neuSurface(.recessed) paints the inherited black foreground over the well — fill it with DesignTokens.bgCanvas explicitly"

requirements-completed: [KTCH-03]

# Metrics
duration: ~50m
completed: 2026-07-21
---

# Phase 20 Plan 04: Shopping List Summary

**Shipped the shopping half of the Kitchen to the user's binding mockups — a `Pantry | Shopping` segmented host whose RESTOCK section is computed live from pantry state and never written to disk, where one tap restocks the pantry by `restockQuantity` and the row leaves the list, alongside manually-added EXTRAS that sync, check off without touching the pantry, and are deleted only through tombstoned `deleteSynced(kind: .shoppingListItem)`.**

## What shipped

- **KitchenLogic.deriveShoppingItems(from:)** — pure filter/sort: every row that is not `.inStock`, out-of-stock first, then low, case-insensitive alphabetical within each group with unnamed rows last. No `ModelContext` parameter, no inserts — the derived-not-materialised invariant (20-01) is documented on the function and pinned by a test.
- **KitchenLogic.toggleChecked(_:)** — flips a manual extra's `isChecked`, sets/clears `checkedAt`, stamps `touch()`. Explicitly does not touch the pantry: only derived rows restock, because only they have a pantry staple behind them.
- **ShoppingRow.swift** — one row view, two identities through `Kind.derived(PantryItem)` / `.manual(ShoppingListItem)`. Both lead with a 44pt `CheckCircle` (recessed well → `checkmark.circle.fill` on the positive twin). Derived rows carry the icon tile, LOW/OUT badge, "N unit left" and a trailing `RestockPill` ("↻ + 12 pcs") that states the check-off consequence before the tap; extras carry the plain name (no tile, per the mockup) with strikethrough + dimmed styling when checked.
- **ShoppingListView.swift** — RESTOCK card over the derived rows with a right-aligned count and the user-facing footnote "Pulled live from your pantry — never saved as tasks…"; EXTRAS card with unchecked-then-checked ordering, an inline dashed-`+` "Add item…" field, per-row context menu (Edit / Delete), a "Clear checked" header action, and a compact `EditShoppingItemView` sheet (name / quantity stepper / unit / tombstoned remove). Empty state matches `20-REF-shopping-empty.png`. Zero `DesignTokens.swift` edits.
- **KitchenView.swift** — now a thin segmented host: a custom neumorphic `Pantry | Shopping` control under the inline title, the Shopping segment badged with the count of everything still to buy (derived + unchecked extras), and the toolbar `+` shown only on the pantry segment. The 20-03 pantry content moved verbatim into `PantryListView` — a move, not a rewrite. DEBUG `-kitchenTab <0|1>` mirrors `-startTab`.
- **MyHomeApp.swift** — `seedSampleShoppingExtras` adds "Aluminium foil", "Paper napkins · 2 pack" and a checked "Batteries · 4 pcs" so both row stylings appear in screenshots. Idempotent.
- **ShoppingListTests.swift** — 10 tests: ordering, unnamed-last, live-state reaction, check-off-restocks-and-leaves with a strict `updatedAt` bump, insufficient-restock-stays-listed (pinned intentional behaviour), zero materialisation (T-20-08), manual round-trip, toggle stamping both directions, manual-check-off-leaves-pantry-alone, and `shoppingListItem` tombstones on clear-checked (T-20-09).

## Deviations from Plan

**1. [Binding UI contract] Extras are deleted via context menu + "Clear checked", not swipe-to-delete**
- **Found during:** Task 2
- **Issue:** The plan asked for swipe-to-delete AND a Clear-checked action. `.swipeActions` only exists inside a `List`; the mockup's EXTRAS section is a single raised `.neuSurface` card of Divider-separated rows (the 20-03 pattern). Converting to a `List` would have discarded the binding visual contract.
- **Fix:** Long-press context menu with Edit / Delete per row, plus the "Clear checked" action in the EXTRAS header. Both delete exclusively through `deleteSynced(kind: .shoppingListItem)`, so the T-20-09 mitigation is unchanged.
- **Files:** `ShoppingListView.swift`

**2. [Rule 2 - Missing critical functionality] The empty state keeps an "Add item…" field**
- **Found during:** Task 2
- **Issue:** `20-REF-shopping-empty.png` shows only the basket tile and copy. With both sections empty, the EXTRAS card (which hosts the inline add row) is not rendered — so a user with a fully stocked pantry would have had no way to add a manual extra at all.
- **Fix:** A single recessed "Add item…" field under the empty-state copy, same `addItem()` path. Everything else in the empty state matches the mockup exactly.
- **Files:** `ShoppingListView.swift`

**3. [Rule 1 - Bug, screenshot-driven] Neumorphic decorations stretched**
- **Found during:** Task 2 screenshot verification
- **Issue:** The first light capture showed the check circles as black ovals (a bare `Circle()` paints the inherited foreground over the recessed well, and the flexible parent stretched it), and the second showed the empty-state basket tile spanning the full canvas width.
- **Fix:** `Circle().fill(DesignTokens.bgCanvas)` + `.fixedSize()` on the check circle; `.fixedSize()` on the empty-state tile. Both re-captured and re-checked against the mockups.
- **Files:** `ShoppingRow.swift`, `ShoppingListView.swift`

**4. [Plan text] The segmented control is custom, not `.pickerStyle(.segmented)`**
- **Found during:** Task 2
- **Issue:** The plan pointed at the NotesHomeView pattern (a native segmented `Picker`), but the mockup's Shopping segment carries an accent count pill, which the native control cannot render, and the surrounding chrome is neumorphic.
- **Fix:** A two-button neumorphic control (recessed track, raised selected capsule, `.isSelected` accessibility trait) with the badge. The segment enum + host structure still follow the NotesHomeView shape.
- **Files:** `KitchenView.swift`

**5. [Rule 3 - Blocking] pbxproj registration split across the two tasks**
- **Found during:** Task 1
- **Issue:** The plan asked Task 1 to register `ShoppingListView.swift` / `ShoppingRow.swift` before those files existed; Xcode fails the build outright on a missing build input, so Task 1's own test run could not have passed. (Same call as 20-03.)
- **Fix:** Task 1 registered `ShoppingListTests.swift`; Task 2 registered the two view files with the same 4-edit pattern. End state is identical — all three show as `… in Sources`.

## Verification

- **Acceptance criteria:** `grep -rn 'context.delete(' MyHomeApp/Features/Kitchen` = **0**; `kitchenTab` present in `KitchenView.swift`; `markRestocked` reached from the derived check-off (`ShoppingRow.swift`, documented in `ShoppingListView.swift`); `git diff --stat MyHomeApp/DesignSystem/DesignTokens.swift` **empty** (dark byte-identity untouched); all three new files registered `in Sources`.
- **Targeted:** `ShoppingListTests` — 10/10 passed.
- **Full suite serial (`-parallel-testing-enabled NO`): `✔ Test run with 651 tests in 90 suites passed` — 0 failures, DarkBitIdentityTests and KitchenSyncTests included.**
- **Screenshot self-verify (iPhone 17, Xcode 26.5):**
  - `20-04-light-shopping.png` — matches `20-REF-shopping.png`: RESTOCK (3) with icon tiles, OUT/LOW badges, "0 pack left", "↻ + 2 pack" pills; the derived footnote; EXTRAS with a struck-through checked "Batteries" and the dashed-`+` "Add item…" row; Shopping segment badged `5`.
  - `20-04-dark-shopping.png` — luminous category twins, accent-yellow restock pills and badge, legible LOW/OUT on the dark canvas, green check on the checked extra.
  - `20-04-light-shopping-empty.png` — matches `20-REF-shopping-empty.png`: raised basket tile, "Nothing to buy" / "Pantry looks stocked. Items land here the moment something runs low.", no segment badge (plus the deviation-2 add field).
  - `20-04-light-pantry-segmented.png` — the 20-03 pantry surface unchanged beneath the new segmented control, toolbar `+` still present.

## Known Stubs

None. Every rendered value is backed by live `PantryItem` / `ShoppingListItem` state; the derived section is computed, not placeholder.

## Threat Flags

None new. T-20-08 (derived-row materialisation drift) is mitigated and test-pinned by `derivationNeverMaterialisesRows`; T-20-09 (manual-item deletes) is mitigated by routing every delete through `deleteSynced(kind: .shoppingListItem)` with the bare-delete grep gate at zero. Manual free text is trimmed, stored as a plain `String`, and rendered with plain `Text` (never `AttributedString(markdown:)`). No packages installed (T-20-SC).

## Self-Check: PASSED

`ShoppingListView.swift`, `ShoppingRow.swift` and `ShoppingListTests.swift` exist on disk; commits `358c2d0` and `5b4485b` present in git history; all four evidence PNGs present in the phase directory.
