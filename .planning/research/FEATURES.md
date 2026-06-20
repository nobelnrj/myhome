# Feature Research

**Domain:** Personal household finance + ops hub (iOS, 2-person household, India)
**Researched:** 2026-06-08 (v1.1 update; v1.0 research preserved below) | 2026-06-20 (v1.2 update)
**Confidence:** HIGH (self-transfer detection signals, daily-routine data model), MEDIUM (asset tracker scope and India stock API reliability)

---

## v1.1 Scoping Principle

v1.1 adds four feature areas to a shipped app. Every feature is judged against:
"would a 2-person household actually use this within the first week of it shipping?"
NOT against what fintech products offer.

PROJECT.md already excludes: broker account linking, Open Banking, CAS import, XIRR, goal planning, multi-currency UI, CloudKit sync (v2), widgets (v2). This document does not re-litigate those.

---

## Feature Area 1: Accounts Management

### What It Is

A named registry of the household's bank accounts (HDFC Savings, ICICI CC,
etc.) that the existing `Expense.sourceAccount: String?` field can reference as
a real model, enabling per-account spend totals and a manual balance figure.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Create / edit / delete BankAccount with name, type, last-4, and opening balance | Without this, sourceAccount strings are unstructured orphans | LOW | type: savings / current / credit-card / wallet as String raw value |
| Manual balance entry + last-updated timestamp | Balance is known after each bank statement; manual update is the only reliable path | LOW | Store as `Decimal`, never `Double`; timestamp stored as UTC Date |
| Link existing expenses to an account via sourceAccount string matching | Expenses already carry `sourceAccount: String?` — Account model makes that field meaningful | LOW | Linkage is by string equality; migration can backfill from `sourceLabel` |
| Per-account expense total for the current month | "How much did we spend on the ICICI card this month?" | LOW | @Query on Expense filtered by sourceAccount; computed, not stored |
| Account list view showing name, type, balance, and monthly spend | Single screen to see all accounts at a glance | LOW | |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Color / icon (SF Symbol) per account | Fast visual identification on expense list and transfer inbox | LOW | Store symbolName and colorHex on BankAccount |
| "Unlinked expenses" indicator | Surfaces expenses whose sourceAccount string matches no known account | LOW | Simple @Query predicate; helps after initial account setup |
| Account balance history (store a snapshot per manual update) | See how a savings balance trends over time; feeds net-worth history | MEDIUM | Separate BalanceSnapshot model; defer until net worth chart is built |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic balance sync via Open Banking / bank API | Sounds convenient | Paid APIs, unstable India coverage, OAuth complexity per bank — no free path | Manual entry after checking the bank app; takes 30 seconds |
| CSV / PDF bank statement import for batch balance update | Auto-populate balances | Parsing is fragile across all Indian banks; adds file picker + parser surface | Manual balance update; email ingestion already handles transactions |
| Credit limit + utilisation % | Looks useful | Adds fields (limit, due date, minimum payment) that require regular upkeep | Show the balance; that is enough |

### User Stories (testable)

- User can add a bank account with name, type, last-4 digits, and opening balance.
- User can edit any account field; last-updated timestamp updates automatically.
- User can delete an account; linked expenses lose the FK reference (nullify) but are not deleted.
- User can see total expenses for the current month for each account.
- The account list shows name, type, balance (with last-updated date), and this-month spend.

---

## Feature Area 2: Self-Transfer Detection

### What It Is

When a bank sends a debit alert (money left Account A) and a credit alert
(money arrived at Account B) for the same amount on or near the same day, and
both accounts are the user's own accounts, this is a fund transfer — not spend.
It must be excluded from budget totals. Decision: **auto-detect then surface a
confirm prompt; never silent exclusion**.

### Detection Signals (in priority order)

Research findings from YNAB matching documentation and USPTO transaction
matching patent literature (7-day window for exact-amount match in opposite
directions) — adapted to Indian bank patterns.

**Signal 1 — Exact amount match (strongest)**
The debit and credit Decimal amounts are identical to the paisa. Indian bank
alerts always show exact amounts (no rounding). Fuzzy matching is NOT used;
it would introduce false positives.

**Signal 2 — Both accounts are known own accounts**
Both `Expense.sourceAccount` values resolve to accounts that exist in the
BankAccount registry. A debit to an unknown account (third-party payee) must
NOT be auto-flagged. This is the gate that prevents false positives.

**Signal 3 — Opposite direction within a 3-day calendar window**
One transaction is a debit (negative direction) and the other a credit
(positive direction). The pair must fall within 3 calendar days of each other.
Rationale: Indian NEFT and IMPS typically settle same-day; UPI is instant;
3 days covers weekend lag without being so wide it produces false positives.
(The 7-day window from research literature is appropriate for multi-bank
international contexts; 3 days is the right tightening for domestic Indian
transfers.)

**Signal 4 — Neither transaction is already categorised or confirmed as spend**
If the user manually set a category on the debit, do not second-guess it. Only
flag pairs where both transactions are uncategorised or auto-ingested without
user correction. This prevents the detector from overriding intentional
categorisation.

**Signal 5 — Neither transaction is already flagged as reversal/refund**
The existing ingestion pipeline handles reversals. Do not double-flag.

**Scoring rule**: A pair scoring 4+ signals → surface in Transfer Inbox
automatically. A pair scoring exactly 3 (e.g. no category check possible on a
manual entry) → surface with a lower-priority flag. A pair scoring 2 or fewer
→ leave alone; too ambiguous.

### Confirm Flow

```
[Detection runs after each Gmail sync and on first v1.1 launch for historical data]
    └──> Pair scores ≥ 3 signals
             └──> Both expenses move to "Possible Transfer" inbox
                  UI shows: "₹50,000 moved from HDFC Savings → ICICI CC on 7 Jun.
                             Mark as transfer? This excludes both from spend totals."

[Mark as Transfer]
    → Both expenses get transferStateRaw = "confirmed"
    → Excluded from all spend / budget calculations immediately
    → Shown in a separate "Transfers" section in expense list (not deleted)

[Not a Transfer]
    → Both expenses get transferStateRaw = "dismissed"
    → Treated as normal spend; appear normally in all views

[Dismiss for now]
    → Pair stays in inbox; neither expense is excluded
    → Badge count persists; user can return and decide later
```

Critical constraint: The confirm step is mandatory. The system never silently
removes spend. A false-positive silent exclusion in a finance tool is worse
than a false-negative (missing a transfer).

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Detect debit+credit pairs meeting ≥ 3 signals | Core feature; transfers inflate spend totals without it | MEDIUM | Run scorer after each sync; also retroactively on v1.1 first launch |
| `Expense.transferStateRaw: String?` field | Persists the confirm decision | LOW | Values: nil / "pending" / "confirmed" / "dismissed" |
| "Possible Transfer" inbox (mirrors Review Inbox UX) | User must confirm before exclusion | LOW | Same triage pattern already exists in the ingestion inbox |
| Mark as Transfer / Not a Transfer / Dismiss for now | Full three-state confirm | LOW | |
| Confirmed transfers excluded from all @Query spend predicates | This is the entire purpose | MEDIUM | Every spend query needs `transferStateRaw != "confirmed"` filter |
| Badge on Transfer inbox (pending count) | User needs to know there are unreviewed pairs | LOW | Same badge pattern as ingestion inbox |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Retroactive detection over all historical expenses on v1.1 first launch | Catch transfers that predate the feature | LOW | One-time scorer pass; surface in inbox for review |
| Net transfer flow summary on Overview (₹X moved between own accounts this month) | Gives a sense of cash movement separate from spend | LOW | Sum of confirmed-transfer amounts; single line on overview |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Silent auto-exclusion without confirm | Faster UX | A false positive silently removes real spend — unacceptable in a finance tool | Always show the confirm inbox; one-tap confirm is fast enough |
| ML-based transfer detection | "More intelligent" | 5 deterministic signals capture all real Indian domestic transfer patterns; ML adds a training-data burden with no accuracy gain for a household with ~20 accounts max | Use the signal scorer |
| Fuzzy amount matching (±1%) | Might catch rounding | Indian bank alerts are always exact rupees+paise; fuzzy matching introduces false positives with near-identical amounts | Exact Decimal match only |

### User Stories (testable)

- Given expense A (debit ₹25,000 from HDFC Savings on 5 Jun) and expense B (credit ₹25,000 to ICICI CC on 5 Jun), both accounts are in the BankAccount registry: the pair appears in the Transfer Inbox automatically after the next sync.
- User confirms the pair as a transfer; both expenses disappear from spend/budget views but remain visible in a "Transfers" section.
- User marks a pair as "Not a Transfer"; both expenses remain in spend/budget views as normal.
- The monthly spend total on Overview does not include any expense with `transferStateRaw == "confirmed"`.
- A debit+credit pair where one account is not in the BankAccount registry does NOT appear in the Transfer Inbox.
- On first v1.1 launch, the scorer runs over all historical expenses and surfaces any matching historical pairs.

---

## Feature Area 3: Asset Tracker

### What It Is

A lightweight net-worth view covering mutual funds (NAV-priced via free API),
stocks (quote-priced, best-effort), NPS (manual), and bank account balances
(from BankAccount) — summing to a net-worth figure. Holdings are entered
manually; prices refresh from free public APIs; manual override always
available. This is NOT a trading or portfolio-analytics app.

### Minimum Viable Holding Model

```
Holding
  id: UUID
  name: String                — "Parag Parikh Flexi Cap Fund"
  assetTypeRaw: String        — "mutualFund" | "stock" | "nps" | "fd" | "other"
  units: Decimal              — number of units / shares / notional
  costBasis: Decimal          — total amount invested (Decimal, not per-unit)
  currentNAV: Decimal         — last fetched or manually overridden price per unit
  navLastUpdated: Date?       — when price was last refreshed; nil = never fetched
  navIsManual: Bool           — true if user overrode the fetched price
  amfiSchemeCode: String?     — for mutualFund type; used to fetch from mfapi.in
  tickerSymbol: String?       — for stock type; NSE/BSE symbol
  notes: String?
  createdAt: Date
```

Derived at query time, never stored:
- `currentValue = units × currentNAV`
- `gainLoss = currentValue - costBasis`
- `gainLossPct = gainLoss / costBasis × 100`
- `netWorth = sum(all holding currentValues) + sum(BankAccount.balance)`

### Free Public Data Sources

**Mutual funds — HIGH confidence (reliable, official data)**
mfapi.in: no authentication, no API key, no rate limits published, pure JSON.
- Latest NAV: `GET https://api.mfapi.in/mf/{schemeCode}/latest` → `{ "data": [{ "nav": "87.23", "date": "08-06-2026" }] }`
- Search by name: `GET https://api.mfapi.in/mf/search?q={name}`
- Scheme codes are AMFI codes (unique per scheme, stable).
- Source: mfapi.in docs verified 2026-06-08.

**Stocks — MEDIUM confidence (unofficial, fragile)**
No official free NSE/BSE API exists for third-party iOS apps. Unofficial
wrappers (Yahoo Finance-backed) exist on GitHub (0xramm/Indian-Stock-Market-API,
maanavshah/stock-market-india) but have no uptime guarantee and no ToS clarity.
Recommended approach: attempt a best-effort fetch; if it fails, show the last
known price with a "stale — as of [date]" label; never block the UI or show an
error modal. Manual override is always available.

**NPS, FD, gold, other — manual only**
No public API. `navIsManual = true` permanently for these types. User enters
current value / units manually when they check their NPS statement.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Add / edit / delete a holding (name, type, units, cost basis) | Without this there is nothing to track | LOW | |
| Current value, gain/loss, and gain/loss% per holding | Every portfolio tracker shows these; missing = useless | LOW | Computed from `units × currentNAV` |
| Total net worth = sum of all holding current values + sum of BankAccount balances | The headline number the user wants | LOW | BankAccount.balance feeds in automatically if Accounts is built first |
| Asset allocation chart (% by type: MF / stocks / NPS / cash / other) | Instant visual of where money lives | MEDIUM | Pie or donut chart via Swift Charts |
| Manual NAV / price override | API will sometimes be stale or unavailable | LOW | `navIsManual` flag; show a "manual" badge next to the value |
| "Refresh prices" button — pulls latest NAV for all MF holdings from mfapi.in | User expects an on-demand refresh | MEDIUM | URLSession; best-effort; never blocking; update `currentNAV` and `navLastUpdated` |
| Staleness label per holding ("as of DD Mon") | User needs to know how old the price is | LOW | Show `navLastUpdated` formatted; highlight if > 2 business days stale |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Account balances included in net worth total | Cash in bank is part of net worth | LOW | Direct from BankAccount.balance; requires Accounts feature |
| Net-worth-over-time chart (monthly snapshots) | See wealth trajectory, not just today's number | MEDIUM | Store a `NetWorthSnapshot` (date, totalValue: Decimal) on first-of-month or on-demand tap; render with LineMark in Swift Charts |
| Holdings grouped by fund house / broker | Easier to scan when there are 6–10 holdings | LOW | Section headers keyed on the first word of the name, or an explicit groupKey field |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| CAS import (PDF / email from CAMS or KFintech) | Auto-populates all MF holdings | PDF parsing is fragile across registrar formats; adds file picker + parser surface for marginal gain when manual entry takes 5 minutes | Manual entry; typical household portfolio is 3–8 funds |
| Broker account linking (Zerodha / Groww / Kuvera API) | Automatic sync | OAuth per broker, API key, fragile on policy change, no free tier for personal use | Manual unit updates when buying or selling |
| XIRR / IRR calculation | "True" return metric | Requires full per-lot transaction history (purchase date + amount per tranche); heavy model; non-trivial numerics | Show absolute gain% which is sufficient for a casual tracker |
| F&O, derivatives, options tracking | Some users trade these | Reo and his wife are SIP + buy-and-hold; adds model complexity with no use | Hard out of scope |
| Goal-based planning ("retire at 55", "college fund") | Aspirational and popular in Indian apps | Requires long-term projection models, inflation assumptions, SWR calculations | Net-worth trend chart is the simple proxy |
| Portfolio overlap analysis | Nice to know for MF investors | Requires full holdings-in-each-fund data (not available from NAV-only API) | Manual awareness; if two funds hold Reliance, they both show up in the list |
| SIP / lump-sum transaction log per holding for cost-basis tracking | Accurate cost basis when buying in tranches | New `HoldingTransaction` model, UI for purchase history, cost-basis recalculation — heavy for v1.1 | Single costBasis field manually maintained; revisit if needed |

### User Stories (testable)

- User can add a mutual fund holding with name, AMFI scheme code, units, and cost basis; current value appears immediately using the last cached NAV.
- User taps "Refresh Prices"; the app fetches the latest NAV from mfapi.in for all mutual fund holdings and updates `currentNAV` and `navLastUpdated`.
- If a price fetch fails (no network), the holding shows the last known NAV with a "stale — as of [date]" label; the UI does not block or show an error modal.
- User can manually override any holding's price; the override is shown with a "manual" badge until the next successful API fetch.
- Net worth total = sum of (holding.units × holding.currentNAV) + sum of BankAccount.balance.
- User can see a pie/donut chart of allocation by asset type.
- User can delete a holding; net worth total updates immediately.
- For NPS / FD holdings, `navIsManual` is always true and there is no "refresh" option shown.

---

## Feature Area 4: Notes Enhancement — Daily Routine

### What It Is

A special Note variant that is a "daily routine" — an ordered checklist that:
1. Has its checkbox completion state reset each day so it can be re-ticked.
2. Fires a local notification at a configured time each day.
3. Appears in the calendar view as a repeating daily event.

This also directly addresses the v1.1 stabilisation bug: `NoteBlock.isChecked`
persists forever today. Tuesday's ticked vitamins remain ticked on Wednesday.

### Per-Day Completion State: The Core Data Model Decision

**Root cause of the existing bug**: `NoteBlock.isChecked: Bool` is a stored,
permanent boolean. It has no concept of "which day was this checked on?"

**Option A — lastCheckedDate on NoteBlock (recommended for v1.1)**

Add a single field to NoteBlock:
```
var lastCheckedDate: Date? = nil    // UTC; nil = never checked / was unchecked
```

"Is this block checked today?" =
`Calendar.current.isDateInToday(lastCheckedDate ?? .distantPast)`

Check: set `lastCheckedDate = Date()`
Uncheck: set `lastCheckedDate = nil`

Pros: pure schema-additive change on existing NoteBlock; no new model; no join;
trivial query. Cons: no completion history (you cannot ask "how often did I do
this routine last week?").

**Option B — RoutineCompletion log model (for v2 if history is wanted)**

```
RoutineCompletion
  id: UUID
  noteBlock: NoteBlock         — FK to the checkbox block
  completedOnDate: Date        — Calendar.current.startOfDay(for: Date())
  createdAt: Date
```

"Is this block checked today?" = fetch `RoutineCompletion` where
`noteBlock == block && completedOnDate == today`.

Pros: full history; enables "did I do my routine this week?" view.
Cons: new @Model, new @Relationship, new schema version, more complex queries.

**Recommendation**: Use Option A for v1.1. The household wants the checklist
to reset; they are not tracking habit streaks. Option B is the natural upgrade
path if completion history is requested post-v1.1.

**Schema changes needed on Note** (both options):
```
var isDailyRoutine: Bool = false    // marks this note as a daily routine
var routineTime: Date? = nil        // time-of-day for the daily notification
```

The existing `NoteBlock.isChecked` boolean MUST be left in the schema for
CloudKit compatibility (no removals); for daily-routine notes it is ignored and
replaced by the `lastCheckedDate`-based derived state.

### Calendar and Notification Integration

The `isDailyRoutine` flag on a Note is all the calendar view needs to render a
repeating daily event. The `NotificationScheduler` already exists and supports
`.daily` recurrence — wire `routineTime` into it.

No new infrastructure is needed. The existing recurrence system is sufficient
for a daily-at-fixed-time schedule.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-day reset of checkbox completion state (the bug fix) | Without this the checklist is useless after day 1 | MEDIUM | Add `lastCheckedDate: Date?` to NoteBlock (SchemaV6 migration) |
| `isDailyRoutine: Bool` flag on Note | Distinguishes a routine note from a regular checklist note | LOW | Schema-additive; new field on Note in SchemaV6 |
| `routineTime: Date?` on Note | The time for the daily notification | LOW | Schema-additive; store UTC; display in device local time |
| Daily notification at the configured time | Surfaces the routine in the morning or evening | LOW | Reuse NotificationScheduler with `.daily` recurrence |
| Calendar view shows daily routine as a repeating event | User expects to see "Morning Routine" as a daily calendar block | LOW | CalendarAggregator already exists; add isDailyRoutine notes as all-day or timed events |
| Checkboxes appear unchecked on a new day | Core UX; user opens app Tuesday and sees a fresh list | LOW | Derived from `lastCheckedDate` comparison; no new logic beyond the date check |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Multiple routines (morning + evening) | The household plausibly has both | LOW | Already supported by having two separate `isDailyRoutine` Notes; just needs a filter |
| Reorder routine items via drag-and-drop | Lets user arrange items in execution order | LOW | `NoteBlock.order` already exists; drag-and-drop reorder UI using SwiftUI `.onMove` |
| Completion history (RoutineCompletion log model) | "Did I do my routine 5 out of 7 days this week?" | MEDIUM | Option B model above; defer to post-v1.1 unless the household explicitly asks |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Habit streak counter (don't break the chain) | Popular in habit apps | Gamification that distracts from the actual goal; the household wants a routine checklist, not a streak | Completion history view if ever requested |
| Routine template library | Quick-start for common routines | Endless curation; two specific users know exactly what they want | Build from scratch; it takes 2 minutes |
| "Skip today" with reason tracking | Habit apps do this for accountability | Unnecessary overhead for a private household tool | Just don't tick items; the day's log stays empty |
| Time tracking per routine item | How long did you spend brushing your teeth? | Overkill | Out of scope |
| Cross-device sync of daily completion state | Wife sees if Reo did his routine | No CloudKit in v1.1; requires sync infrastructure | Deferred to v2.0 |

### User Stories (testable)

- User marks a Note as "daily routine" and sets a reminder time (e.g. 07:00).
- On the next calendar day, all checkboxes in that routine appear unchecked regardless of what was ticked the previous day.
- User ticks items during the day; ticked items show as checked for today only.
- If the user re-opens the app after midnight, the routine is fresh again — no manual reset needed.
- The calendar view shows the daily routine as a repeating event at the configured time.
- A local notification fires at the configured time each day with the routine title.
- User can have two separate daily routines ("Morning" and "Evening") as two independent Notes; both appear in the calendar.

---

## Feature Dependencies

```
BankAccount (new @Model)
    ├──requires──> Expense.sourceAccount (exists in SchemaV5)
    └──enables──>  SelfTransferDetection
                       └──requires──> BankAccount (own-account signal)
                       └──requires──> Expense.transferStateRaw (new field, SchemaV6)
                       └──enables──>  transfer exclusion in all spend @Query predicates

AssetTracker (new @Model: Holding)
    ├──uses──>     BankAccount.balance (cash component of net worth)
    ├──requires──> Holding (new model, SchemaV6)
    ├──best-effort──> mfapi.in (network; mutual funds only)
    └──optionally──> NetWorthSnapshot (new model; needed for net-worth chart)

DailyRoutine
    ├──requires──> Note.isDailyRoutine, Note.routineTime (new fields, SchemaV6)
    ├──requires──> NoteBlock.lastCheckedDate (new field, SchemaV6)
    └──uses──>     NotificationScheduler (exists), CalendarAggregator (exists)
```

### Dependency Notes

- **SelfTransferDetection requires BankAccount**: The "both accounts are own accounts" signal is essential to limit false positives. Build Accounts first or build both in the same phase.
- **AssetTracker uses BankAccount.balance**: Cash component of net worth comes from BankAccount.balance automatically once Accounts is built. If Accounts is in the same phase, both feed the net-worth total together.
- **All new fields and models go in SchemaV6**: Accounts, Holding, transferStateRaw on Expense, isDailyRoutine + routineTime on Note, lastCheckedDate on NoteBlock — all additive, all optional/defaulted, all CloudKit-compatible.
- **DailyRoutine is independent**: No dependency on Accounts or Assets. Can be built in any order within v1.1. It is the stabilisation fix and could ship first.

---

## v1.1 MVP Definition

### Must Have (all four areas constitute the milestone)

- [ ] BankAccount model: add/edit/delete, manual balance, per-account monthly spend — Accounts
- [ ] Expense ↔ BankAccount linkage via sourceAccount — Accounts
- [ ] Self-transfer detection (signal scorer) + Transfer Inbox + confirm/dismiss — Self-Transfer
- [ ] `Expense.transferStateRaw` field; confirmed transfers excluded from all spend queries — Self-Transfer
- [ ] Holding model: add/edit/delete; current value = units × currentNAV; total net worth — Assets
- [ ] mfapi.in NAV fetch for mutual fund holdings (best-effort, never blocking) — Assets
- [ ] Manual price override with staleness label — Assets
- [ ] Asset allocation chart (pie/donut by type) — Assets
- [ ] Note.isDailyRoutine + routineTime; daily notification at configured time — Daily Routine
- [ ] NoteBlock.lastCheckedDate; per-day checkbox reset — Daily Routine (bug fix)
- [ ] Calendar view shows daily routine as repeating event — Daily Routine
- [ ] Stabilisation fixes: category ordering, sync/notes crash — Stability

### Add After v1.1 Validation

- [ ] Balance history snapshots → net-worth-over-time chart
- [ ] Routine completion history log (RoutineCompletion model)
- [ ] Retroactive transfer detection over all historical expenses (runs once on first v1.1 launch; display-only until user confirms)

### Future (v2+)

- [ ] CloudKit sync — account balances, holdings, routine completions across devices
- [ ] Holding transaction log (purchase tranches) for XIRR calculation
- [ ] CAS or broker import for holdings

---

## Feature Prioritization Matrix (v1.1)

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Daily routine per-day reset (bug fix) | HIGH | MEDIUM | P1 |
| BankAccount model + list view | HIGH | LOW | P1 |
| Self-transfer detection + confirm inbox | HIGH | MEDIUM | P1 |
| Expense.transferStateRaw + spend exclusion | HIGH | MEDIUM | P1 |
| Holding model + net worth total | HIGH | LOW | P1 |
| mfapi.in NAV refresh | MEDIUM | MEDIUM | P1 |
| Asset allocation chart | MEDIUM | MEDIUM | P1 |
| Calendar shows daily routine | MEDIUM | LOW | P1 |
| Daily routine notification | MEDIUM | LOW | P1 |
| Manual price override + staleness label | MEDIUM | LOW | P1 |
| Net-worth-over-time chart (monthly snapshots) | MEDIUM | MEDIUM | P2 |
| Retroactive transfer detection | LOW | LOW | P2 |
| Routine completion history (RoutineCompletion model) | LOW | MEDIUM | P3 |

---

## Sources

- YNAB transfer matching: [Manually Match Transactions](https://www.ynab.com/blog/matchmaker-matchmaker-make-me-a-match) — confirmed exact-amount-match requirement and the two-transaction rule for matching
- Self-transfer 7-day window: USPTO patent literature (financial transaction matching system, US6247000) — adapted to 3-day window for Indian NEFT/IMPS/UPI same-day-to-next-business-day settlement
- [mfapi.in documentation](https://www.mfapi.in/docs/) — confirmed no-auth, no-key, JSON, scheme search and latest NAV endpoints (verified 2026-06-08)
- India stock API fragility: [0xramm/Indian-Stock-Market-API](https://github.com/0xramm/Indian-Stock-Market-API) and [maanavshah/stock-market-india](https://github.com/maanavshah/stock-market-india) — both unofficial Yahoo Finance wrappers; no uptime guarantee
- Indian portfolio trackers surveyed for minimum viable features: [arthavi.com](https://arthavi.com), [INDmoney](https://www.indmoney.com/features/track-all-investments), [MProfit](https://www.mprofit.in)
- Per-day reset model: [Habitica](https://habitica.com) Habits / Dailies / To-Dos separation as the canonical pattern (corroborated by App Store app descriptions for Habitify, Routinery, Daily); adapted to SwiftData
- Existing codebase: SchemaV5.swift (Expense.sourceAccount, NoteBlock.isChecked structure), SchemaV4.swift (Note, NoteBlock model fields)

---

---

## v1.2 Feature Research — Neumorphic Redesign (2026-06-20)

### v1.2 Scoping Principle

v1.2 is primarily a **visual milestone** on top of a feature-complete app. The four new surfaces (design system, analytics screen, spend donut, AI insight card) are judged against: "does this make the app feel like something you want to open every morning?"

This document does NOT re-research any v1.0/v1.1 feature. All existing functionality (expense tracking, budgets, notes, accounts, assets) is already shipped; v1.2 only reskins it and adds three net-new UI surfaces plus one new screen.

Design authority: `design/design_handoff_myhome_neumorphic/` — the HTML/React prototype is the pixel-faithful reference. All token values, shadow formulas, and layout decisions in this research are drawn directly from that handoff.

---

## Feature Area 5: Neumorphic Design System

### What It Is

A cohesive Soft UI look applied to every screen in the app. Neumorphism = surfaces share the background color and gain depth purely from two opposing shadows (light from top-left, dark at bottom-right). The handoff pins a dark charcoal canvas (`#1C1C23`) with a canary-yellow accent (`#FFD60A`) as the sole saturated color. No translucency, no blur, no glassmorphism.

The design system is a **prerequisite** for all other v1.2 surfaces — it must be built first because analytics, donut, and AI card all use its shadow tokens, radii, and color palette.

### Core Token Set (from handoff, verbatim)

| Token | Value | SwiftUI Usage |
|-------|-------|---------------|
| Canvas bg | `#1C1C23` | `.background` on root view |
| Raised surface | `#1F1F27` | Default Card fill |
| Raised surface (strong) | `#22222C` | Hero card, tab bar, sheets |
| Elevated control | `#262630` | Segmented picker active fill |
| Recessed fill | `#15151B` | Progress tracks, text inputs |
| Accent yellow | `#FFD60A` | Active tab, CTAs, Analytics tile |
| Accent soft | `rgba(255,214,10,0.16)` | Active-tab pill background |
| Positive | `#34E29B` | Income, positive net, up arrows |
| Negative | `#FF6B6B` | Spend, negative, over-budget |
| Primary label | `#ECEDF4` | All body text |
| Secondary label | `rgba(220,223,238,0.56)` | Subtitles, captions |

Shadow pair (the heart of the style):
- **Raised card**: `shadow(-6,-6,14, white@3.5%) + shadow(7,7,18, black@55%)`
- **Floating element**: `shadow(-9,-9,22, white@4%) + shadow(11,11,28, black@62%)`
- **Recessed well**: `inset shadow(2,2,5,black@50%) + inset shadow(-2,-2,5,white@3.5%)`
- **Pressed/active state**: swap to recessed shadow

In SwiftUI these map to `.shadow(color: .white.opacity(0.035), radius: 14, x: -6, y: -6)` + `.shadow(color: .black.opacity(0.55), radius: 18, x: 7, y: 7)` applied via a custom `ViewModifier`.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `NeuSurface` ViewModifier encoding all three shadow states (raised/recessed/floating) | Every card needs this; without it there is no Soft UI | LOW | One ViewModifier with an enum parameter; applied as `.neuRaised()`, `.neuRecessed()`, `.neuFloat()` |
| Design token constants as Swift enum or struct | Hardcoded hex in every view is fragile; tokens make theme-wide changes possible | LOW | `NeuTokens.canvas`, `NeuTokens.accent`, etc.; all Color values |
| Shadow pair on every card surface | The shadows ARE the style — missing them makes the app look flat-charcoal, not Soft UI | LOW | Apply via `NeuSurface` modifier; never use system `.card` or `.regularMaterial` |
| 26px card radius throughout | Under-rounded cards break the Soft UI illusion; the handoff is explicit on this | LOW | `NeuTokens.cardRadius = 26`; capsule bars use `.infinity` |
| Floating capsule tab bar (62px tall, radius 34px, yellow active pill) | The handoff defines the tab bar as a floating element with float-shadow; stock SwiftUI `.tabBar` does not match | MEDIUM | Custom `TabBar` view that replaces `.tabViewStyle` entirely; manage tab selection in app state |
| Active tab: yellow icon + label + soft yellow pill background | Tab active state is the primary accent usage; missing = accent has no anchor | LOW | Conditional color/background on each tab item |
| Rolling money readouts (odometer count-up on mount/change, ~780ms easeOutCubic) | The handoff explicitly defines this as a motion primitive; static numbers feel dead in this style | MEDIUM | `RollingNumberView` using `TimelineView` or manual animation loop; apply to all `₹` hero amounts |
| Pressed/active feedback: opacity dim to 0.45 + recessed shadow swap | Neumorphic controls must "press in" visually when tapped | LOW | `.pressedStyle()` modifier using `DragGesture(minimumDistance:0)` to detect press |
| Restyle all six existing screens (Overview, Activity, Budgets, Notes, Settings, + Accounts, Assets, Transfer Inbox) | The app looks inconsistent if unrestyled screens sit behind a redesigned Overview | HIGH | This is the high-complexity item; each screen needs a reskin pass |
| Category color palette (11 colors) from handoff | Charts, bars, and donut segments all use these specific colors; deviation looks wrong | LOW | `groceries: #2DD4BF, dining: #FB923C, fuel: #F472B6, utilities: #7DD3FC, rent: #818CF8, shopping: #E879F9, health: #A78BFA, subscriptions: #22D3EE, entertainment: #C084FC, other: #94A3B8` |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Inner rim highlight on raised cards (`inset 1px 1px 1px rgba(255,255,255,0.045)`) | Adds the final edge-lit look that makes surfaces feel genuinely embossed | LOW | Add to `NeuSurface` modifier; one extra `.shadow` call |
| Spring animation on tab highlight slide (`cubic-bezier(.34,1.32,.42,1)`) | The snappy elastic slide makes tab switching feel premium | LOW | SwiftUI `.animation(.spring(response:0.35, dampingFraction:0.7))` on the highlight offset |
| Yellow-accent glowing icon tile for Analytics entry button (solid `#FFD60A` fill, near-black icon) | The Analytics tile stands out from all other cards, creating a clear visual hierarchy | LOW | `RoundedRectangle` filled with accent; icon in `#1A1404` for contrast |
| Positive/Negative pill next to net cash flow hero number | Semantic color chip that conveys direction at a glance without reading the number | LOW | Conditional `--pos`/`--neg` tinted capsule |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Light mode support | System default | Neumorphism in dark charcoal requires near-identical surface and background tones — the style fundamentally breaks in light mode where shadows need to invert completely and the look becomes "dirty beige" | Pinned dark mode only; the design handoff is explicit that this is a dark-themed system |
| Multiple theme variants / skins | The prototype supports 6 skins | The handoff says "implement only the Neomorphism style"; shipping multiple themes multiplies QA surface and dilutes identity | One theme, well executed |
| Glassmorphism blur or translucency | Popular and visually similar | The handoff is explicit: "No translucency, no blur" — Soft UI and Glass are distinct styles | Solid opaque surfaces with the dual-shadow system |
| Gradient fills on card backgrounds | Looks rich | Breaks the Soft UI contract: surfaces must be the same color family as the canvas, not gradients | Reserve gradients for the budget bar fill and chart lines only |
| System `.background` and `.card` ShapeStyles | Easiest approach | These adopt tint colors in dark mode and don't match the exact charcoal tokens | Hard-code `Color(hex: NeuTokens.raisedSurface)` via the NeuSurface modifier |

### Existing Data Dependencies

The design system has NO data dependencies — it is pure UI restyling. Every view just gets new colors, shadows, and radii applied on top of its existing data bindings.

---

## Feature Area 6: "Where It's Going" Spend Donut

### What It Is

A ring donut chart on the Overview screen showing the current month's expenses broken down by category. Each slice is one category's color from the palette. The center shows a "SPENT" eyebrow and the total spend as a rolling number. A legend below (or beside) shows the top 4 categories with their colors and amounts. Tapping a slice filters the Activity list — this is the drill-down interaction.

This surface replaces the existing spend-by-category bar chart (Swift Charts `BarMark`) on Overview with a more visually compact and premium ring representation, while keeping category drill-through.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Ring donut from current month's expenses grouped by category | Core feature; without segments the ring is meaningless | LOW | Group `Expense` by `category` for current calendar month; filter out `transferStateRaw == "confirmed"` |
| Each category segment gets its color from the category palette | Color encodes category identity throughout the app | LOW | Map `category.id` to `CAT_COLORS` palette |
| Center label: "SPENT" eyebrow + rolling total spend amount | Users need the absolute total visible, not just proportions | LOW | Overlay `ZStack` center on the SVG ring |
| Top-4 category legend (colored dot, name, amount) | Context for what each color means; without this the ring is ambiguous | LOW | Sort descending by amount; show top 4; "Others" roll-up if more than 4 |
| Gap between segments (visual separation) | Segments without gaps blur together in neumorphic dark context | LOW | Use `strokeDasharray` gap or SwiftUI `SectorMark.angularInset` |
| Animate segments growing in on appear (0 → full arc, ~900ms spring) | Static ring feels dead in the Soft UI context | LOW | `stroke-dasharray` transition from 0 → target length; or SwiftUI `trim(from:to:)` animated |
| Segment glow (`drop-shadow` in the category color) | Adds depth and makes segments legible against dark canvas | LOW | SwiftUI `.shadow(color: segmentColor.opacity(0.5), radius: 5)` on `SectorMark` or custom SVG layer |
| Empty state: plain circle track with "No expenses this month" | If there are no expenses the ring must still render gracefully | LOW | Show the recessed ring track with a center message |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Tap-to-filter: tap a segment → Activity screen pre-filtered to that category | Turns the donut from decoration into a navigation shortcut | MEDIUM | Pass a `selectedCategory` binding; Activity screen already supports category filter |
| "Others" roll-up segment for categories beyond the top 4 | Prevents the ring from having 10 tiny slices | LOW | Sum all categories ranked 5+ into a grey "Others" segment |
| Rolling number in center animates when month changes | Motion connects the chart to the live data | LOW | Reuse the `RollingNumberView` component from the design system |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Exploding/exploded segments on tap | Some pie charts "pop" a slice outward | Breaks the neumorphic flush surface aesthetic; the ring is embedded in a card, not floating | Tap highlights the segment by brightening its glow and shows a tooltip chip |
| Full-screen donut or dedicated Donut tab | More room = more data | Overview is the right home; a dedicated tab wastes navigation hierarchy for a glance metric | Keep it on Overview; Analytics screen provides the deeper breakdown |
| 3D or isometric donut | Trendy in some finance apps | Clashes with the flat-Soft-UI system; impossible to render legibly in dark charcoal | Flat ring only |
| Percentage labels on each segment | Some chart libraries default to this | Segments are too narrow for readable text at small chart sizes; and the legend already gives amounts | Show percentage in tap-tooltip only |

### Existing Data Dependencies

| Data | Source | Status |
|------|--------|--------|
| `Expense.amount` grouped by `Expense.category` for current month | SwiftData `@Query` with month predicate | Exists |
| `Expense.transferStateRaw` for exclusion of confirmed transfers | `Expense` model (SchemaV6) | Added in v1.1 |
| Category color palette | Static constant in code (design tokens) | New in v1.2 |
| Total spend (sum of category amounts) | Derived from the same query | Exists |

---

## Feature Area 7: Dedicated Analytics Screen

### What It Is

A full-screen overlay (not a tab) opened from the Analytics card on Overview. It contains: time-range tabs (Week / Month / Year), a total-spend headline with a delta chip (vs prior period), a smooth area chart showing spend over time, an AI Insight card, and a by-category horizontal bar list. The design handoff's `analytics.jsx` is the exact reference.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Time-range tab switcher: Week / Month / Year | Without time-range control the chart is locked to one view; this is the primary interaction | LOW | Segmented control using neumorphic recessed track + raised yellow pill for active state |
| Total spend headline for the selected range | Anchor number that all other content in the screen explains | LOW | Sum of `Expense.amount` for the range, excluding confirmed transfers |
| Delta chip: ▲/▼ % vs prior period, colored green if down / coral if up | "Is this better or worse than last period?" is the most actionable question on this screen | MEDIUM | Compute prior-period sum; calculate `(current - prior) / prior * 100`; green chip for negative delta (less spend = good) |
| "vs last week/month/year" label next to delta chip | Without this, "8.4%" is ambiguous — better or worse? | LOW | Static label changes with the range selection |
| Smooth area chart (Catmull-Rom curve, left-to-right draw animation) | A chart that draws itself on appear is expected in a premium finance UI | MEDIUM | Swift Charts `AreaMark` + `LineMark` with `.interpolationMethod(.catmullRom)`; animate via `chartXScale` expansion or a `trim` modifier |
| Area chart fill gradient (coral at peaks → transparent at baseline) | Depth cue for a spending area chart | LOW | Swift Charts `.foregroundStyle(.linearGradient(...))` on the `AreaMark` |
| Peak marker dot on the highest value | Draws the eye to the worst spending period | LOW | Overlay a `PointMark` at the max-value x-axis position |
| X-axis labels (M/T/W/T/F/S/S for week; W1–W5 for month; J–D for year) | Required for chart readability | LOW | Swift Charts `AxisMark` on `.chartXAxis` |
| Staggered by-category horizontal bars (icon chip + name + amount + colored fill bar) | Category breakdown is the second most important content on this screen | MEDIUM | `ForEach` over categories sorted by spend descending; each row has an icon tile, label, amount, and a recessed-track + colored-fill progress bar |
| Stagger animation on category bar grow-in (each bar delayed by ~60ms) | Makes the list feel organized rather than all-at-once | LOW | `animation(.spring(...).delay(Double(index) * 0.06))` on bar width |
| Tap-to-show tooltip on category bar (amount + % of spend) | Progressive disclosure of the percentage detail | LOW | Toggle a boolean on tap; show a chip above the bar |
| "Back" / close button (circular soft control) | Screen opens as a push/overlay; user must be able to close it | LOW | Circular neumorphic button with chevron.left; yellow accent icon |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Scanning dot travelling along the area chart line (continuous loop) | Draws attention to the chart's most recent data point and makes the screen feel live | MEDIUM | `animateMotion` along the path (SVG) or a custom overlay dot that rides the chart line using `chartOverlay` + `GeometryReader` |
| "Spending trend" card label with period indicator (e.g. "June 2026") | Contextualizes the chart so the user knows what period they're looking at | LOW | `Text` label above the chart inside the raised card |
| Color-coded peak x-axis label (matches the coral negative color) | Highlights the worst day/week visually | LOW | Conditional foreground color on the peak axis label |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Custom date range picker (from/to dates) | Power user request | Adds a picker UI, date validation, edge cases; the three fixed ranges cover 95% of what the household will use | Week / Month / Year is sufficient; add custom range only if explicitly requested post-ship |
| Export to CSV / PDF | "Save my analytics" | Out of scope for a local private tool; adds file picker, formatting, share sheet | The data lives in the app; no export needed |
| Comparison mode (two periods side by side) | Some analytics apps offer this | Doubles the query complexity and chart rendering; disproportionate complexity for a 2-person household | The delta chip covers the comparison need adequately |
| Line chart instead of area chart | Simpler to implement | The area fill provides the visual weight that makes spending highs feel visceral — important for a "where is my money going?" screen | Area chart with gradient fill |
| Bar chart instead of area chart for the trend | Bar charts are clearer for discrete periods | Week and Month views have 5–7 data points which suits a smooth area curve; bars at this density look cluttered on a phone | Area for the trend; horizontal bars for the category breakdown |

### Existing Data Dependencies

| Data | Source | Status |
|------|--------|--------|
| `Expense.amount` + `Expense.date` for range queries | SwiftData `@Query` with date predicate | Exists |
| `Expense.category` for grouping | `Expense.category: String` | Exists |
| Prior-period expenses for delta computation | Same model, different date range | Exists (query logic is new) |
| Category color palette | Design tokens (v1.2 new) | New in v1.2 |
| Category icon (SF Symbol name) | Category model or static mapping | Exists |

---

## Feature Area 8: On-Device AI Insight Card

### What It Is

A card on the Analytics screen that displays a single natural-language sentence about the user's spending for the selected time range. Example: "Dining is up 34% this week — three weekend orders drove most of it. Skipping one keeps you under budget." The text is generated by Apple's FoundationModels framework (the on-device ~3B parameter model powering Apple Intelligence) using structured spending data as context.

The card has a violet left-edge glow, a "breathing orb" animation, "AI INSIGHT" eyebrow, sparkles icon, and typewriter text reveal. These are decoration — the core feature is the insight text itself.

### Capability Ground Truth (HIGH confidence — verified against WWDC25 session 286)

The on-device model is a ~3B parameter LLM running on A17 Pro / M1+ chips with Apple Intelligence enabled. It is optimized for:
- Content summarization and generation from supplied context
- Structured output (guided generation into Swift types)
- Short-to-medium text tasks broken into discrete pieces

It is NOT designed for:
- World knowledge or current events (does not know market context)
- Complex multi-step reasoning (e.g., financial forecasting)
- Long-context analysis (keep prompts short; use structured data, not raw text)

Availability gating is required before every session:
```swift
switch SystemLanguageModel.default.availability {
case .available: // proceed
case .unavailable(let reason): // show static fallback
}
```

Unavailability reasons: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. The card must gracefully degrade in all three cases.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Single natural-language insight sentence for the selected time range | The reason for the card's existence; a card that always says "No insight available" is useless | MEDIUM | Prompt the model with structured spending summary; request a 1–2 sentence output |
| Availability check before every generation; graceful fallback when unavailable | Devices without Apple Intelligence (pre-A17 Pro, or AI disabled) must not show an error modal | LOW | Show a static "Insights available on Apple Intelligence-enabled devices" message in the card shell |
| Insight refreshes when time-range tab changes | The insight must correspond to the currently selected period (Week/Month/Year) | LOW | Trigger a new generation whenever `range` binding changes; cancel the previous in-flight task |
| Typewriter text reveal (character-by-character, ~26ms per char) | Matches the streaming nature of model output; signals to the user that this is generated, not a static string | LOW | Stream from `LanguageModelSession.respond(to:)` using `AsyncThrowingStream`; update a `@State var shownText: String` progressively |
| Violet card accent (left edge glow + violet wash) distinguishes the AI card from financial data cards | AI-generated content must be visually distinct from data-derived content | LOW | Hard-code the violet styling; this is not a design token variation, it is a semantic signal |
| "AI INSIGHT" eyebrow + sparkles icon | Labels the card as AI-generated, setting correct expectations | LOW | Static label; SF Symbol `sparkles` |
| Breathing orb animation (pulsing circle) shows the model is thinking / alive | Standard loading affordance for AI content | LOW | SwiftUI scale animation loop while generating; stop when text is complete |
| Loading state while model generates | Generation takes 2–5 seconds; a blank card with no feedback feels broken | LOW | Show the breathing orb alone, no text, until first characters appear |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Range-aware insight: Week insight names specific days, Month insight names specific weeks, Year insight names the worst month | Specificity makes insights feel personal rather than generic | MEDIUM | Include range-appropriate data in the prompt (day-of-week spend for Week, week totals for Month, month totals for Year) |
| Actionable suggestion in the insight ("Skipping one keeps you under budget") | Converts observation into behavior change; the most useful thing the card can say | MEDIUM | Include budget data in the prompt so the model can reference the gap between current spend and budget limit |
| Fastest-growing category observation ("your fastest-growing category since March") | Year-range insight can reference prior months from the same data window | MEDIUM | Include month-by-month category totals in the Year prompt; let the model identify the trend |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Cloud LLM fallback (Claude / GPT) when on-device is unavailable | More capable model; always available | Finance data leaving the device is a hard no for a private household tool; also adds API cost and network dependency | Static "Insights available on supported devices" message. The device gate is not a bug; it is by design. |
| Multiple insight cards or a feed of insights | More insights = more value | The on-device model is a device-scale model; long outputs degrade quality; a single focused sentence is more trustworthy than a paragraph of hallucinations | One insight card, one sentence, refreshed per range change |
| Persistent insight history (save past insights to SwiftData) | "What did it say last month?" | Generated text is ephemeral and context-dependent; saving it creates a historical artifact that may become misleading as data changes | Regenerate on demand; no persistence |
| Manual "regenerate" button | Some AI UIs offer this | Exposes the model's non-determinism; if users see different outputs for the same data they lose trust | Generate once per range per session; if the user changes the range and comes back, it regenerates naturally |
| Fine-tuned or custom adapters | Better domain accuracy | Out of scope; FoundationModels adapters are for Apple's built-in use cases (content tagging, etc.); custom training is not exposed | Well-engineered prompt with structured spending data is sufficient for 1–2 sentence observations |
| Insight accuracy disclaimer / caveat text | Legal / trust concern | Adds visual noise to a card that is already trust-sensitive due to the violet styling | The violet styling and "AI INSIGHT" label already set appropriate expectations; a legal disclaimer is overkill for a private household app |

### Prompt Engineering Strategy (MEDIUM confidence)

The FoundationModels model works best with structured, factual input rather than conversational context. For a spending insight, the prompt should supply:

```
Context (for Week range):
- Total spend this week: ₹8,420
- Prior week total: ₹8,980 (6.2% less this week)
- Top categories: Groceries ₹2,380, Dining ₹1,920, Fuel ₹1,450
- Budget limit: ₹35,000/month (₹8,750/week pro-rata)
- User's currency: INR

Task: Write one to two sentences summarizing the most notable spending pattern 
and, if applicable, one actionable suggestion. Be specific. Do not use generic 
advice. Do not mention investments, savings rates, or advice outside the data provided.
```

Keep the entire prompt under 500 tokens. The model is not designed for long-context reasoning; short, structured prompts produce better outputs than narrative context.

**Guided generation** (structured output) is preferable over free text for reliability:

```swift
@Generable
struct SpendingInsight {
    var observation: String   // what happened
    var suggestion: String?   // optional actionable tip
}
```

Concatenate `observation + " " + (suggestion ?? "")` for display. This prevents the model from generating multi-paragraph output or going off-topic.

### Existing Data Dependencies

| Data | Source | Status |
|------|--------|--------|
| Weekly/monthly/yearly expense totals by category | SwiftData `@Query` grouped by category + date range | Exists (new grouping logic needed) |
| Prior-period totals for delta comparison | Same model, prior date range | New query logic (shared with Analytics screen) |
| Monthly budget limits per category | `Budget` model | Exists |
| `SystemLanguageModel` framework | FoundationModels (iOS 26, A17 Pro+) | New dependency |

---

## v1.2 Feature Dependencies

```
NeurophicDesignSystem (no data deps — pure UI)
    └──required-by──> ALL other v1.2 surfaces
                       (AnalyticsScreen, SpendDonut, AIInsightCard all use NeuSurface,
                        NeuTokens, RollingNumberView, capsule tab bar)

SpendDonut (Overview screen addition)
    ├──requires──> Expense.amount + Expense.category (exists)
    ├──requires──> transferStateRaw exclusion (SchemaV6, v1.1)
    └──requires──> Category color palette (NeuTokens, v1.2)

AnalyticsScreen (new full-screen overlay)
    ├──requires──> Expense date-range queries with category grouping (new query logic)
    ├──requires──> Prior-period queries for delta chip (new query logic)
    ├──requires──> Category color palette (NeuTokens, v1.2)
    └──enhances──> SpendDonut (tap-to-filter navigates here)

AIInsightCard (within AnalyticsScreen)
    ├──requires──> AnalyticsScreen (card lives inside it)
    ├──requires──> Aggregated spending data from AnalyticsScreen queries
    ├──requires──> Budget limit data (Budget model, exists)
    └──requires──> FoundationModels framework (iOS 26, Apple Intelligence)
```

### Dependency Notes

- **Design system first**: NeuSurface, NeuTokens, RollingNumberView, and the capsule tab bar must be built before any screen reskin can begin. The reskin pass then applies uniformly to all screens.
- **AnalyticsScreen query logic is shared with AIInsightCard**: Build the spending-aggregation query (by-category, by-period, prior-period) once in a `SpendingAnalyticsViewModel`; both the chart and the AI prompt consume it.
- **SpendDonut and AnalyticsScreen are independent after the design system is ready**: They can be built in parallel if needed.
- **AIInsightCard requires iOS 26 and Apple Intelligence**: The build target minimum can stay iOS 17; the card must availability-gate at runtime. Do not use `#available` on the card view itself — use the `SystemLanguageModel.default.availability` check inside the view model.

---

## v1.2 MVP Definition

### Must Have (the milestone is complete when all are done)

- [ ] `NeuSurface` ViewModifier with three states (raised / recessed / float) — Design System
- [ ] `NeuTokens` color/shadow constants — Design System
- [ ] `RollingNumberView` (odometer count-up) — Design System
- [ ] Custom floating capsule tab bar with yellow active pill — Design System
- [ ] Reskin Overview screen with neumorphic surfaces — Reskin
- [ ] Reskin Activity, Budgets, Notes, Settings screens — Reskin
- [ ] Reskin Accounts, Assets, Transfer Inbox screens — Reskin
- [ ] "Where it's going" spend donut on Overview (segments + center total + legend) — Donut
- [ ] Donut segment grow-in animation on appear — Donut
- [ ] Analytics screen (full-screen overlay from Overview card) — Analytics
- [ ] Time-range tabs (Week/Month/Year) with sliding active pill — Analytics
- [ ] Total spend headline + delta chip (vs prior period) — Analytics
- [ ] Smooth area chart (Catmull-Rom, left-to-right draw) with peak marker — Analytics
- [ ] By-category horizontal bars with stagger animation + tap tooltip — Analytics
- [ ] AI Insight card with availability gate + typewriter reveal + graceful fallback — AI

### Add After v1.2 Validation

- [ ] Tap-to-filter from donut segment → Activity pre-filtered to category
- [ ] Scanning dot animation along area chart line
- [ ] Range-aware insight specificity tuning (budget gap in suggestion)

### Future (v2+)

- [ ] Custom date-range picker on Analytics
- [ ] Year-over-year insight with multi-year data

---

## v1.2 Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| NeuSurface / NeuTokens design system | HIGH (enables everything) | LOW | P1 |
| RollingNumberView | HIGH (hero UX) | MEDIUM | P1 |
| Capsule tab bar | HIGH (visible on every screen) | MEDIUM | P1 |
| Screen reskin — Overview | HIGH | MEDIUM | P1 |
| Screen reskin — remaining screens | HIGH | HIGH | P1 |
| Spend donut on Overview | HIGH | MEDIUM | P1 |
| Analytics screen — time range + headline + delta | HIGH | MEDIUM | P1 |
| Analytics screen — area chart | HIGH | MEDIUM | P1 |
| Analytics screen — category bars | HIGH | LOW | P1 |
| AI Insight card (basic — availability gate + insight) | MEDIUM | MEDIUM | P1 |
| Donut tap-to-filter | MEDIUM | MEDIUM | P2 |
| Area chart scanning dot | LOW | MEDIUM | P2 |
| Actionable AI suggestion with budget context | MEDIUM | LOW | P2 |

---

## Sources

- Design handoff: `design/design_handoff_myhome_neumorphic/README.md` — canonical token values, shadow formulas, screen layouts, motion specs (verified 2026-06-20)
- Design prototype source: `design/design_handoff_myhome_neumorphic/src/analytics.jsx`, `src/home.jsx`, `src/charts.jsx` — exact component behavior and data structures
- [Apple WWDC25 session 286 "Meet the Foundation Models framework"](https://developer.apple.com/videos/play/wwdc2025/286/) — capabilities, limitations, availability enum, hardware requirements (HIGH confidence)
- [AppCoda — Getting Started with Foundation Models in iOS 26](https://www.appcoda.com/foundation-models/) — availability gating patterns, graceful degradation (MEDIUM confidence)
- [Swift Charts donut chart — swiftwithmajid](https://swiftwithmajid.com/2023/09/26/mastering-charts-in-swiftui-pie-and-donut-charts/) — `SectorMark` + `innerRadius` for donut, iOS 17 requirement (HIGH confidence)
- [SwiftUI neumorphism — Hacking with Swift](https://www.hackingwithswift.com/articles/213/how-to-build-neumorphic-designs-with-swiftui) — dual-shadow ViewModifier pattern (MEDIUM confidence)
- [Fintech UX best practices — eleken.co](https://www.eleken.co/blog-posts/fintech-ux-best-practices) — progressive disclosure, contextual insights vs raw data (MEDIUM confidence)

---

---

## v1.0 Feature Research (archived — do not re-litigate)

The section below is the original v1.0 research (2026-05-28). It is preserved
for reference because some sections (India-specific features, anti-features,
competitor analysis) remain relevant. v1.0 features are all shipped and
validated; see PROJECT.md Validated section.

---

## Scoping Principle (v1.0)

This is a 2-person household tool, not a market product. Every feature is judged against one question: **"would this make Reo + wife reach for the app instead of Apple Notes + a spreadsheet on day 30?"** Anything that doesn't pass that bar — no matter how standard in YNAB/Mint/Walnut — is an anti-feature here.

PROJECT.md already excludes: Android, SMS reading, cross-Apple-ID sharing in v1, OCR, recurring bills, investments, multi-currency UI, web/macOS, multi-household, watchOS, widgets-as-MVP. This document does not re-litigate any of those — it categorizes the remaining surface area.

---

## Feature Landscape — Expense Tracker (v1.0, all shipped)

### Table Stakes (shipped)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Gmail OAuth + background poll for bank emails | Core value prop — "I never have to log a transaction" | HIGH | iOS BackgroundTasks framework; tokens in Keychain; per-bank parser templates. The ONE feature that decides app survival. |
| Per-bank email parsers (HDFC, ICICI, SBI, Axis, Kotak at minimum) | Each bank has its own format; one regex doesn't fit all | HIGH | Templated extractors with confidence score. Low-confidence → review inbox. |
| Manual expense entry (amount, date, category, note) | SMS-only banks, cash, parser failures all need a fallback | LOW | Must be 4-tap-max: open → amount keypad → category → save. |
| Review/inbox for low-confidence parses | Auto-ingestion is never 100% — user must confirm ambiguous ones | MEDIUM | One-tap accept; tap-to-edit fields; swipe-to-discard. Drives parser improvements over time. |
| Predefined category list at first launch | Empty-category onboarding is friction; Indian users have predictable categories | LOW | Ship with: Groceries, Dining, Fuel, Utilities, Rent, Transport, Shopping, Health, Entertainment, UPI Transfer, ATM, Misc. |
| Custom tags (single tag default, multi-tag schema) | Categories alone don't capture "Trip to Goa" or "Diwali shopping" | LOW (schema) / MEDIUM (UI for multi-tag) | Schema as future-proof per PROJECT.md decisions. UI starts single-tag. |
| Per-category monthly budget | Stated requirement; without it, expenses are just a log not a tool | MEDIUM | Default month = calendar month. Resets on 1st. |
| Budget progress visualization (per-category bar) | The "are we OK this month?" glance | LOW | Bar + percentage + ₹ remaining. Color shift at 80% / 100%. |
| Month view grouped by category | The primary "how did we do this month?" surface | MEDIUM | Sectioned list. Tap category → drilldown to transactions. |
| Edit / delete an expense | Auto-ingested transactions are sometimes wrong | LOW | Hard delete in v1. |
| Duplicate detection on ingestion | Same transaction can arrive via email twice | MEDIUM | Dedup key: amount + merchant-substring + date within ±1 day. |
| ₹ display with Indian comma grouping (1,00,000 not 100,000) | Wrong formatting screams "not built for India" | LOW | `NumberFormatter` with `Locale(identifier: "en_IN")`. |
| Face ID app lock (toggle in settings) | Financial data; PROJECT.md mandates | LOW | `LocalAuthentication` framework. |

---

## India-Specific Features (v1.0 context, remains relevant)

### Table Stakes (India)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Indian numbering: ₹1,00,000 (lakh) not ₹100,000 | Wrong format = "this app isn't built for me" | LOW | `NumberFormatter` with `Locale(identifier: "en_IN")` handles it. |
| Per-bank email templates: HDFC, ICICI, SBI, Axis, Kotak | These 5 cover ~80% of urban Indian households' cards | HIGH | Templated extractors with confidence score. |
| UPI transaction parsing | UPI is the dominant transaction type in India | HIGH | Extract VPA as merchant. |
| Recognize "credit" / "refund" / "reversal" emails | Refunds treated as expenses doubles the spend figure | MEDIUM | Parser flags direction; store as negative or with a direction field. |
| Indian category defaults | Generic lists miss UPI, ATM, Recharge, Maid, Auto/Cab | LOW | Shipped defaults cover these. |

### Anti-Features (India, v1.0)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-currency UI (USD, AED, etc. for travel) | International travel common from India | PROJECT.md says no for v1; schema-ready is enough | Note travel expenses with a tag. |
| Investment / mutual-fund / SIP tracking | Indian users often want this in one place | **Reversed in v1.1 — now in scope** | See Asset Tracker above. |
| Tax-section labeling (80C, 80D, etc.) | Indian-tax appeal | Annual not daily; spreadsheet fine once a year | Skip. |
| Direct UPI app integration ("pay from inside this app") | Convenience | Massive PCI/RBI compliance burden | Skip permanently. |

---

*Feature research for: My Home iOS app*
*v1.0 original research: 2026-05-28*
*v1.1 update: 2026-06-08*
*v1.2 update: 2026-06-20*
