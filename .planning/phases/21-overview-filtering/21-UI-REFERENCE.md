# Phase 21 — UI Reference (user-supplied, 2026-07-21)

| File | Covers |
|---|---|
| `21-REF-overview-pill.png` | Overview header with the scope pill (default all-accounts state) |
| `21-REF-filter-sheet.png` | "Show data from" account sheet |

Executors of 21-03 MUST view both images before writing view code. This
document's **Decisions** section overrides any conflicting prose in 21-03.
Dark mode is not mocked — derive from existing token twins
(`DesignTokens.swift` is READ ONLY; DarkBitIdentityTests pin dark values).

---

## As drawn

**Header pill** — trailing the `Overview` title, level with it: a raised
capsule containing a filled status dot, the scope label ("All accounts"), and a
chevron-down. The eyebrow month ("JULY 2026") stays above the title.

**Sheet** — grabber; title **Show data from** + subtitle; then rows in a plain
(not carded) list:
- Pinned first row **All accounts** — selected state is an accent-outlined
  raised container + a filled accent check circle; secondary line
  "4 accounts · +₹14,000 in"; trailing period total (₹33,040).
- One row per account: rounded-square colored icon tile (card glyph for credit,
  house glyph for savings), name, secondary "Credit ··42" / "Savings ··07 ·
  +₹12,000 in", trailing period spend, and a recessed selection circle.
- Footer text action: ⚙ **Manage accounts**.

Note the sheet is doing real work beyond selection — every row shows that
account's spend (and income where non-zero) for the current period, so the sheet
doubles as a per-account glance. Those numbers must come from the same
`BudgetCalculator.grossSpend`/`grossIncome` transfer-excluding path the hero
uses, not a separate sum.

## Decisions (user, 2026-07-21) — BINDING

**1. Reach is the Overview only.** The mocked subtitle "Applies across Home,
Expenses & Budgets" is WRONG for this phase — 21-02 deliberately suppresses the
Budgets sections while a filter is active. Ship the subtitle as
**"Applies to your Overview"**. An app-wide filter is a future phase, not this
one.

**2. The date range lives in this same sheet.** Add a `PERIOD` block below the
account list (above "Manage accounts"): **This Month** (default) / **Custom
range** with from–to day pickers, per OVF-02. One sheet owns the whole filter,
so `OverviewFilter()` default = one-tap clear stays true.

**3. Single header pill — NO separate chip bar.** This replaces the planned
`OverviewFilterBar` chip row. Everywhere 21-03 says "chip", read "the header
pill". Specifically:
- The pill is always present (it is also the entry point), unlike the chip which
  rendered only when `filter.isActive`.
- Inactive: neutral dot + "All accounts".
- Active: accent dot + a summary label ("HDFC + 1", "HDFC · Jul 1–15",
  "Jul 1–15") — never let filtered figures read as all-account totals (OVF-03,
  threat T-21-05 is satisfied by the pill, not the chip).
- One-tap clear: an `xmark.circle.fill` replaces the chevron while
  `filter.isActive`; tapping it sets `filter = OverviewFilter()` without opening
  the sheet. The sheet also offers "All accounts" as the equivalent reset.
- 21-03's `OverviewFilterBar.swift` becomes `OverviewScopePill.swift`.

## Gaps to fill from plan text (not mocked)

- **Unassigned row** — 21-01's `includeUnassigned` needs a picker row so
  filtered money can never silently vanish. Place it last in the account list.
- **Multi-select** — the mockup's circles read as radios, but the plan (and the
  file name "scales to any # of accounts") is a subset selection. Selecting a
  second account adds to the set; selecting "All accounts" clears the set.
- **Account icon tiles** — reuse whatever `Account` already renders elsewhere;
  do NOT add model fields for this.
