# Phase 9: SchemaV6 & Accounts Management - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-09
**Phase:** 9-SchemaV6 & Accounts Management
**Areas discussed:** Migration backfill, Accounts placement, Balance semantics, Routine reset scope

---

## Migration backfill

### How existing expenses get linked to accounts at migration

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-create from sourceLabel | Create one Account per distinct sourceLabel, set accountID; nil-label stays Unassigned | |
| Migrate nil, assign later | accountID=nil for all; create/assign accounts manually afterward | |
| Auto-create + review | Auto-create from sourceLabel AND surface in editable review list to rename/merge/delete before lock-in | ✓ |

**User's choice:** Auto-create + review
**Notes:** Grouping key is `sourceLabel` (human bank name), not `sourceAccount` (Gmail mailbox / dedup key).

### Account type for auto-created accounts

| Option | Description | Selected |
|--------|-------------|----------|
| Infer 'CC'→credit, else savings | Heuristic on label text; user fixes in review | ✓ |
| Default all to savings | All start savings; set real type in review | |
| Require type in review | No type until review forces a pick | |

**User's choice:** Infer 'CC'/'credit'/'card' → credit card, else savings

### Manual expense account-field behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Optional picker, remembers last | Optional, defaults to last-used; blank = Unassigned | ✓ |
| Optional, no default | Optional, always starts empty | |
| Required picker | Must pick an account to save | |

**User's choice:** Optional picker, remembers last-used

### Gmail-ingested new expense attribution

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-match by sourceLabel | Match account by sourceLabel; no match → Unassigned | ✓ |
| Always Unassigned | All ingested expenses land Unassigned | |
| You decide | Planner picks | |

**User's choice:** Auto-match by sourceLabel

---

## Accounts placement

### Navigation placement

| Option | Description | Selected |
|--------|-------------|----------|
| New top-level tab | Dedicated Accounts tab | |
| Section under Overview | Card/section inside Overview dashboard | |
| Under Settings | Managed from Settings | ✓ |

**User's choice:** Under Settings

### Per-account spend entry

| Option | Description | Selected |
|--------|-------------|----------|
| Drill-in from account card | Account detail with filtered transactions | |
| Account filter on expense list | Filter/segment on existing expense list | |
| Both | Detail drill-in AND expense-list filter | ✓ |

**User's choice:** Both

### Per-account detail entry point (given management is under Settings)

| Option | Description | Selected |
|--------|-------------|----------|
| Settings list + expense filter | Settings account list opens detail; expense list also gets account filter | ✓ |
| Settings CRUD only, spend via filter | Settings is pure CRUD; spend only via expense filter | |
| You decide | Planner picks | |

**User's choice:** Settings list + expense filter

### Archive behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Hidden from pickers, history stays | Out of pickers; transactions remain; collapsed Archived section | ✓ |
| Hidden everywhere except history | Gone from list and pickers; only via old transactions | |
| You decide | Planner picks | |

**User's choice:** Hidden from pickers, history stays (collapsed Archived section)

---

## Balance semantics

### Credit-card sign convention

| Option | Description | Selected |
|--------|-------------|----------|
| CC as negative (owed) | Savings positive, CC negative; net worth = simple sum | ✓ |
| CC as positive outstanding | CC shown as positive liability; net-worth special-cases CC | |
| You decide | Planner picks | |

**User's choice:** Credit card shown as negative (amount owed)

### Opening-balance baseline entry

| Option | Description | Selected |
|--------|-------------|----------|
| Amount + date picker, defaults today | Baseline amount + as-of date (default today); balance = baseline ± txns since | ✓ |
| Amount only, anchored at creation | Just an amount; as-of = creation date | |
| You decide | Planner picks | |

**User's choice:** Amount + as-of date picker, defaulting to today

---

## Routine reset scope

### How V6 knows which blocks to reset

| Option | Description | Selected |
|--------|-------------|----------|
| Add isDailyRoutine to V6 now | Note.isDailyRoutine flag; reset only flagged notes; Phase 12 flips the flag | ✓ |
| Reset ALL checklist blocks | Reset every checklist daily (risky for ordinary lists) | |
| You decide | Planner picks | |

**User's choice:** Add `isDailyRoutine` to SchemaV6 now

### Reset mechanism at data-model level

| Option | Description | Selected |
|--------|-------------|----------|
| lastCheckedDate per block, reset on stale | Per-block UTC date-key | |
| Routine-level reset marker | Note.routineLastResetDate; reset all blocks when stale vs IST startOfToday | ✓ |
| You decide | Planner picks | |

**User's choice:** Note-level `routineLastResetDate` marker
**Notes:** Slight divergence from success-criterion 5 wording (which also names per-block `lastCheckedDate`). Note-level marker satisfies the observable reset; per-block date logging deferred to Phase 12 streak/history (NOTE-05). Flagged for planner in CONTEXT.md specifics.

---

## Claude's Discretion

- Account color/icon picker UX — follow existing ManageCategoriesView pattern.
- Asset model field shape — V6 scaffold only; refined in Phase 11.
- Transfer-scaffold fields on Expense — minimal so Phase 10 needs no further migration.
- `didMigrate` throw/rollback error-handling — must verify vs FB13812722 before writing.
- V5→V6 fixture test harness shape — follow existing Swift Testing / in-memory ModelContainer patterns.

## Deferred Ideas

None — discussion stayed within phase scope.
