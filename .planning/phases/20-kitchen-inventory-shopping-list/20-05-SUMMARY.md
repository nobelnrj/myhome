---
phase: 20-kitchen-inventory-shopping-list
plan: 05
subsystem: verification
tags: [phase-gate, regression, invariants, screenshots, sync, kitchen, ktch-01, ktch-02, ktch-03, ktch-04]

# Dependency graph
requires:
  - phase: 20-kitchen-inventory-shopping-list
    plan: 01
    provides: SchemaV11 PantryItem/ShoppingListItem
  - phase: 20-kitchen-inventory-shopping-list
    plan: 02
    provides: kitchen DTOs, SyncScope.production widening, snapshot version 11
  - phase: 20-kitchen-inventory-shopping-list
    plan: 03
    provides: KitchenLogic + pantry surface + Overview entry
  - phase: 20-kitchen-inventory-shopping-list
    plan: 04
    provides: derived shopping list + manual extras
provides:
  - "Phase 20 gate evidence: 652 tests in 90 suites passed, 0 failures, serial run (20-05-gate.log)"
  - "Five structural invariants re-verified on the integrated tree (STAB-08, bare-delete gate, schema version 11, DesignTokens untouched, pbxproj registration)"
  - "Both-theme kitchen review set (5 screenshots) for sign-off"
  - "BootstrapAdvisor now counts kitchen rows — emptiness is scope-relative and kitchen is in scope"
  - "KitchenSyncTests.selfMergeOfOwnExportIsNoOp — bytes-level export→import self-merge is a visible no-op"
affects: [21-overview-filtering]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Emptiness/eligibility checks that are scope-relative must be revisited whenever SyncScope widens — the scope is the contract, not the entity list"
    - "Where a UI loop needs share-sheet/Files taps that simctl cannot drive, automate the bytes between the taps (export→decode→merge) and hand only the taps to the human check"

key-files:
  created:
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-gate.log
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-light-pantry.png
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-light-shopping.png
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-dark-pantry.png
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-dark-shopping.png
    - .planning/phases/20-kitchen-inventory-shopping-list/20-05-light-overview-entry.png
  modified:
    - MyHomeApp/Sync/BootstrapAdvisor.swift
    - MyHomeTests/BootstrapAdvisorTests.swift
    - MyHomeTests/KitchenSyncTests.swift

key-decisions:
  - "Carried observation 1 FIXED, not deferred: BootstrapAdvisor.isStoreEffectivelyEmpty now counts PantryItem/ShoppingListItem under scope.isSynced — 20-02 widened SyncScope.production to notes + kitchen, and the advisor's own documented rationale (emptiness is scope-relative) then requires kitchen to count"
  - "Carried observation 2 NOT actioned in code: the grains/coffee icon-tile palette is a fidelity question for the user, not a correctness bug — routed to the end-of-phase human check as an explicit accept/reject item"
  - "The UI-level export→Files→import loop stays in the human check (simctl cannot drive a share sheet or the Files picker — same call 18-05 made); the automatable core was added as a bytes-level self-merge test instead"

patterns-established:
  - "Phase gate log format: command + the five structural invariants with expected values inline, then the pass/fail test lines and the final count — readable without re-running anything"

requirements-completed: [KTCH-01, KTCH-02, KTCH-03, KTCH-04]

# Metrics
duration: ~40m
completed: 2026-07-21
---

# Phase 20 Plan 05: Phase Gate Summary

**Phase 20 gates green: 652 tests in 90 suites passed with `-parallel-testing-enabled NO` and zero failures, all five structural invariants hold on the integrated tree, the kitchen surface is captured in both themes, and the one inconsistency the phase carried — a bootstrap advisor that still thought a kitchen-only phone was a fresh install — was closed rather than deferred.**

## Authoritative regression run (verbatim)

```
xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO

✔ Test run with 652 tests in 90 suites passed after 10.623 seconds.
** TEST SUCCEEDED **
```

**652 tests, 90 suites, 0 failures.** (651 before this plan; +1 for the new self-merge test. The two new `BootstrapAdvisorTests` parameterized cases run inside an existing test and do not move the top-level count — the log shows `entity → .pantryItem` and `entity → .shoppingListItem` cases started and passed.) Full output in `20-05-gate.log`. Suites confirmed present and green in the log: `SchemaV11MigrationTests`, `KitchenLogicTests`, `ShoppingListTests`, `KitchenSyncTests`, the Phase-18 sync suites at version 11, `BootstrapAdvisorTests`, and `DarkBitIdentityTests`.

The serial flag was used deliberately — a parallel run turns one fatal error into hundreds of meaningless 0.000s failures across unrelated suites.

## Structural invariants (all hold)

| # | Invariant | Result |
|---|-----------|--------|
| 1 | `typealias X = SchemaV10.` under `Persistence/Models/` | **0** (STAB-08 still atomic after 4 plans) |
| 2 | bare `context.delete(` outside `DeletionTracker.swift` | **0** (18-04 gate survived the kitchen UI work) |
| 3 | `currentSchemaVersion = 11` in `SyncSnapshot.swift` | **1** |
| 4 | `DesignTokens.swift` last commit | `032d6b9 feat(17): light-mode chart dishes…` — **Phase 17, predates Phase 20**; no phase-introduced dark-branch change |
| 5 | Kitchen/test files `in Sources` | all 11 registered (PantryItem, ShoppingListItem, KitchenLogic, KitchenView, PantryItemRow, ShoppingRow, ShoppingListView, EditPantryItemView + KitchenLogicTests, ShoppingListTests, KitchenSyncTests) |

## Sync invariants on the final build

All machine-verified in `KitchenSyncTests` on the gate run:

- **Round-trip idempotent** — `reImportIsIdempotent`: re-merging the same kitchen snapshot yields 0 inserted / 0 adopted / 0 deleted and no duplicate rows.
- **NEW — bytes-level self-merge is a no-op** — `selfMergeOfOwnExportIsNoOp`: `exportData` (production scope) → `SnapshotCodec.decode` asserts `schemaVersion == 11`, 2 pantry + 1 shopping row aboard → `mergeData` back into the SAME store → 0/0/0, counts and quantities unchanged. This is the automatable core of the Settings export → Save to Files → Import → Merge loop.
- **v10 refused at (found: 10, expected: 11)** — `v10PayloadRefused`: `SyncError.schemaVersionMismatch(found: 10, expected: 11)` thrown, and the local pantry row is untouched.
- **Tombstones honored** — deleted pantry and shopping rows are never resurrected by an older snapshot that still contains them; shopping deletes tombstone with `kind: .shoppingListItem`.
- **Financial privacy invariant re-checked (footgun 3):** `productionExportExcludesAllMoney` (SnapshotRoundTripTests) asserts kitchen present (`pantryItems == 1`, `shoppingListItems == 1`) AND `expenses / categories / accounts / assets / netWorthSnapshots / sips / sipAmountChanges / contributions` all empty, plus a companion test asserting money never appears in the exported **bytes**. The tests still assert what they claim; money still never leaves the device.

## Review set

`-seedSampleData` on iPhone 17 (Xcode 26.5), captured into the phase directory:

- `20-05-light-pantry.png` — RUNNING LOW (3) / STOCKED (3) raised cards on bgCanvas, red `⊖ OUT` on Filter coffee, amber `⚠ LOW` on Eggs and Milk, −/+ steppers (− disabled at 0), Shopping segment badged `5`.
- `20-05-light-shopping.png` — RESTOCK (3) derived rows with `↻ + 2 pack` / `+ 12 pcs` / `+ 3 L` pills and the "Pulled live from your pantry — never saved as tasks" footnote; EXTRAS with a struck-through checked "Batteries · 4 pcs", "Clear checked", and the dashed-`+` add row.
- `20-05-dark-pantry.png`, `20-05-dark-shopping.png` — the dark neon treatment: luminous category twins, accent-yellow restock pills/badge/"Clear checked", legible LOW/OUT on the dark canvas, green check on the checked extra. Structurally identical to light; no layout drift.
- `20-05-light-overview-entry.png` (`-scrollTo kitchen`) — the Overview "Kitchen / Open pantry" section with the Pantry card reading "6 items · 3 need restocking".

Self-review against the v1.2 bar: neumorphic raised cards on `bgCanvas` in light, neon instrument look preserved in dark, badges legible in both. One open fidelity question is routed to the user below.

## Carried observations — disposition

**1. BootstrapAdvisor kitchen counts — FIXED (commit `0b67ebc`).**
`isStoreEffectivelyEmpty` counted notes and the (out-of-scope) financial kinds but not pantry/shopping rows, so a phone whose only user data was a stocked kitchen was still offered the first-run bootstrap sheet. Its own doc comment says emptiness is scope-relative — and 20-02 put kitchen IN `SyncScope.production` — so the fix is the rule the function already claimed to follow: count `PantryItem` and `ShoppingListItem` under `scope.isSynced(.pantryItem)` / `.shoppingListItem`. `BootstrapAdvisorTests` needed only the two new enum cases: the suite derives `syncable` / `outOfScope` from `SyncScope.production`, so both the "makes the store non-empty" and the inverse assertion picked them up automatically (log confirms `entity → .pantryItem` and `entity → .shoppingListItem` ran and passed).

**2. Icon tile palette for grains and coffee — NOT changed; routed to the user (UAT item).**
Confirmed visible in `20-05-light-pantry.png`: "Atta" and "Sona Masoori rice" resolve to `shippingbox.fill` in a **purple** tile, and "Filter coffee" is **orange-red**; the reference mockup used warm amber/brown jar tiles for grains and brown for coffee. This is a fidelity preference, not a correctness bug, and retuning the keyword→token mapping is a design change the gate plan has no mandate to make unilaterally. Item 9 of the human check below asks the user to accept the current palette or request the warm retune (a contained change to `KitchenLogic.icon`'s token mapping — no schema, no new API).

## Deviations from Plan

**1. [Rule 2 — missing critical functionality] BootstrapAdvisor fixed inside a verification-only plan**
- **Found during:** Task 1 (carried observation from 20-03)
- **Issue:** As above — a kitchen-only phone was treated as a fresh install.
- **Fix:** kitchen counts added under `scope.isSynced`; tests extended; the FULL suite was re-run afterwards so the committed gate log reflects the fixed tree (the plan forbids marking done on a stale run).
- **Files:** `MyHomeApp/Sync/BootstrapAdvisor.swift`, `MyHomeTests/BootstrapAdvisorTests.swift` — commit `0b67ebc`

**2. [Not automatable] The simulator export→Files→import UI loop was not driven end-to-end**
- **Found during:** Task 2 step 2
- **Issue:** The loop requires taps on a `UIActivityViewController` share sheet and the Files picker. `simctl` has no tap primitive and the project has no UI-test target, so no agent can perform steps the plan describes as UI actions. 18-05 hit the same wall and handed the identical loop to the human check.
- **Fix:** the automatable core was added as a real test instead — `selfMergeOfOwnExportIsNoOp` exercises export bytes → decode → merge-into-self on the production scope and asserts the 0-inserted no-op the UI stats row displays. The remaining share-sheet/Files taps are steps 7–8 of the human check.
- **Files:** `MyHomeTests/KitchenSyncTests.swift` — commit `31f02eb`

**3. [Plan text] Gate command used `-parallel-testing-enabled NO`**
- The plan's literal command omitted the flag while its prose warned against parallelizing around the serialized lock suites. The serial flag was used (project footgun 1) and is recorded verbatim in the log header.

## Known Stubs

None. No stub patterns introduced by this plan; the prior plans' summaries report none, and every value in the review-set screenshots is backed by live `PantryItem` / `ShoppingListItem` state.

## Threat Flags

None new. T-20-10 (regression drift across the four implementation plans) is mitigated: full-suite run plus the five structural greps on the integrated tree, evidence committed. T-20-SC holds — no package-manager installs anywhere in Phase 20.

## HUMAN VERIFICATION — end of phase (single check, `human_verify_mode = end-of-phase`)

Code is complete and the suite is green. This is Phase 20's only human gate.

1. Home tab → **Kitchen** card → pantry opens. Add "Milk", quantity 3, unit L, low-stock threshold 2, restock quantity 3.
2. Tap **−** twice → quantity 1 → the row shows **LOW**. Tap **−** again → 0 → **OUT**.
3. **Shopping** segment → Milk is in **RESTOCK** automatically, with a "↻ + 3 L" hint.
4. Add a manual extra ("Sponges") → appears under **EXTRAS**; check it off → struck through; **Clear checked** removes it.
5. Check **Milk** off in RESTOCK → back on **Pantry**, Milk reads 3 and the flag is gone (check-off restocked the pantry).
6. Toggle light/dark → the kitchen matches the v1.2 neumorphic system in light and the neon treatment in dark.
7. **Two-phone sync (KTCH-04):** Settings → Data → **Export Sync Snapshot** → AirDrop to the other phone (both on the Phase-20 build) → **Merge** → the other phone shows the same pantry items, flags, and manual extras. Delete a pantry item on phone B, export B → merge on A → it stays deleted on A.
8. *(Optional, only if one phone is still on the previous build)* importing its v10 snapshot must show the incompatible-version message and change nothing.
9. **Design accept/reject (carried observation 2):** on the pantry screen, "Atta" / "Sona Masoori rice" show a **purple** box tile and "Filter coffee" an **orange-red** cup tile. The reference mockup used warm amber/brown for grains and brown for coffee. Reply **"palette ok"** to keep as-is, or **"warm grains"** to have the keyword→token mapping retuned.

**Resume signal:** reply "approved" (plus your answer to item 9), or describe issues.

## Self-Check: PASSED

- `.planning/phases/20-kitchen-inventory-shopping-list/20-05-gate.log` — FOUND
- `20-05-light-pantry.png`, `20-05-light-shopping.png`, `20-05-dark-pantry.png`, `20-05-dark-shopping.png`, `20-05-light-overview-entry.png` — all FOUND (5 ≥ 5)
- Commit `0b67ebc` — FOUND
- Commit `31f02eb` — FOUND
