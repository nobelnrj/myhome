# Phase 20 — UI Reference (user-supplied, 2026-07-21)

Four light-mode mockups supplied by the user as the visual contract for Phase 20.
Executors of 20-03 and 20-04 MUST read the corresponding PNG before writing view
code, and the end-of-plan screenshot self-verify compares against it.

| File | Covers | Plan |
|---|---|---|
| `20-REF-pantry.png` | Kitchen → Pantry segment, Running low over Stocked | 20-03 |
| `20-REF-edit-sheet.png` | Edit item sheet | 20-03 |
| `20-REF-shopping.png` | Shopping segment, derived Restock + manual Extras | 20-04 |
| `20-REF-shopping-empty.png` | Shopping empty state | 20-04 |

Dark mode is not mocked — derive it from the existing token twins
(`DesignTokens.swift` is READ ONLY; DarkBitIdentityTests pin every dark value).

---

## Confirmed by the mockups (matches existing plan text)

- Push navigation from Overview: nav bar shows `‹ Overview` + title **Kitchen**.
  The 5-tab bar (Home/Expenses/Budgets/Notes/Settings) stays untouched.
- `Pantry | Shopping` neumorphic segmented control directly under the title.
- Pantry: `RUNNING LOW` section above `STOCKED`, each a single raised
  `.neuSurface` card with Divider-separated rows.
- Row: name + `LOW` / `OUT` badge, secondary "N unit in stock", trailing
  circular `−` / `+` steppers. `−` renders disabled/recessed at quantity 0.
- Badges are text + SF Symbol + color (never color alone): `OUT` =
  `minus.circle` on the negative twin, `LOW` = `exclamationmark.triangle` on the
  warning/orange twin.
- Shopping: `RESTOCK` (derived) above `EXTRAS` (manual), inline `Add item…` row
  with a dashed `+` circle.
- Empty state: basket glyph in a raised rounded tile, **Nothing to buy** /
  "Pantry looks stocked. Items land here the moment something runs low."

## New details the mockups add (not previously in the plans)

1. **Section count badges** — right-aligned muted count on each section header
   (`RUNNING LOW … 3`, `STOCKED … 8`, `RESTOCK … 3`).
2. **Segment badge** — `Shopping` carries a filled accent pill with the restock
   count (`3`); absent when zero (see empty-state mockup).
3. **Per-item icon tile** — a rounded-square colored tile with an SF Symbol at
   the leading edge of every pantry row, the shopping Restock row, and the edit
   sheet's name field. Extras rows have NO tile. See OPEN QUESTION 1.
4. **Restock pill on derived rows** — trailing capsule `↻ + 3 L` instead of the
   plain "will restock +N unit" secondary text the plan described.
5. **Derived-list footnote** — under the Restock card: "↻ Pulled live from your
   pantry — never saved as tasks. Check one to restock it and it leaves the
   list." (This is the user-facing statement of the 20-01 locked
   derived-not-materialized design — keep it.)
6. **Shopping rows lead with a recessed check circle**, both sections.
7. **Edit sheet layout** (`20-REF-edit-sheet.png`): Cancel / **Edit item** /
   Save header on a grabber sheet; name field with icon tile; a `UNIT` chip row
   (`kg g L ml pcs pack pkt btl`, selected chip filled accent yellow); then three
   labeled stepper cards — **In stock**, **Low when at or below** ("Shows a LOW
   badge and adds it to Shopping."), **Restock to** ("Checking it off in Shopping
   fills back to here."); footer destructive **Remove from pantry**.
   Note the unit chips are a UI affordance over the model's free-text
   `unit: String?` — chips must not preclude a value already stored that isn't in
   the chip set.

## Decisions (user, 2026-07-21) — BINDING

**1. Item icon tiles are DERIVED, not stored.** No schema change: `PantryItem`
gains no `symbolName`/`colorHex`. 20-03 adds a pure helper in `KitchenLogic`
(name-keyword → SF Symbol + semantic tile color, with a neutral fallback tile),
unit-tested for the mockup's items and for the fallback. No icon picker in the
edit sheet — the tile there is display-only, driven by the typed name.

**2. Restock is ADDITIVE.** `markRestocked` stays `quantity += restockQuantity`,
matching 20-01/20-04 and the mockup's `↻ + 3 kg` pill. The edit sheet's third
card must therefore NOT read "Restock to / fills back to here" — relabel it
**"Restock by"** with subtitle "Adds this much when you check it off in
Shopping." Everything else in `20-REF-edit-sheet.png` is as drawn.

## Not mocked

**Overview entry card.** 20-03 Task 3 specifies it in prose
(section header "Kitchen" + compact raised card, "2 need restocking"); it will be
built to the plan text and the surrounding Overview rhythm.
