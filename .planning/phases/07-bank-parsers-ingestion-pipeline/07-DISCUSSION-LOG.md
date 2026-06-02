# Phase 7: Bank Parsers & Ingestion Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 7-bank-parsers-ingestion-pipeline
**Areas discussed:** Target banks, Review Inbox surface, New-expense feedback, Forensics & merchant data, Duplicate handling, Accounts (user-raised)

---

## Target banks

| Option | Description | Selected |
|--------|-------------|----------|
| HDFC + ICICI | Roadmap defaults; common Indian retail combo | ✓ |
| One bank for v1 | Ship one rock-solid parser first | |
| Different banks | Axis/SBI/Kotak/Amex etc. | |

**User's choice:** HDFC + ICICI

### Alert types (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Credit card spends | Card-swipe/online alert format | ✓ |
| Debit / account debits | Savings-account debit alerts | ✓ |
| UPI transactions | Bank-emailed UPI debits | ✓ |
| Whatever arrives — you decide | Let the 50+ collected emails drive templates | ✓ |

**User's choice:** All four — cover card + debit + UPI, but let the real corpus drive which templates get written.

---

## Review Inbox surface

| Option | Description | Selected |
|--------|-------------|----------|
| Badge on Expenses tab | Count badge → "Needs Review" section atop expense list | ✓ |
| Card on Overview | "X transactions need review" card on Home | |
| Dedicated Inbox tab | Own tab in TabView | |
| You decide | Leave placement to UI spec | |

**User's choice:** Badge on Expenses tab

### Discard behavior (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Remember as ignored | Record message-ID as dismissed; never re-surface | ✓ |
| Just remove this time | Can reappear on future sync | |

**User's choice:** Remember as ignored (message-ID tracking)

### Row detail (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Parsed fields | Amount, merchant, category, date, source — editable inline | ✓ |
| Why it's low-confidence | Short reason text | |
| Raw email snippet | Peek at original text | |

**User's choice:** Parsed fields only

---

## New-expense feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Subtle 'auto' marker | Appears in list with a small badge/icon | ✓ |
| Marker + 'new since last open' count | Marker plus lightweight count | |
| Nothing — just appear | Blend in silently | |

**User's choice:** Subtle 'auto' marker

### Auto category (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Uncategorized | Land Uncategorized; assign later | |
| Best-guess from merchant | Static merchant→category seed hint | ✓ |

**User's choice:** Best-guess from merchant (static seed hint; falls back to Uncategorized when no hint)

---

## Forensics & merchant data

### Raw storage (ING-10)

| Option | Description | Selected |
|--------|-------------|----------|
| Full raw body | Complete email body stored locally | ✓ |
| Hash + first 500 chars | Lighter footprint | |

**User's choice:** Full raw body (local-only, Face-ID gated)

### Merchant seed (ING-15)

| Option | Description | Selected |
|--------|-------------|----------|
| Claude seeds, hardcoded v1 | ~20–30 Indian merchants shipped in code | ✓ |
| Claude seeds + user-editable | Surfaced in Settings | |
| You'll provide the list | User hands over exact merchants | |

**User's choice:** Claude seeds, hardcoded v1

---

## Duplicate handling (user-added area)

| Option | Description | Selected |
|--------|-------------|----------|
| In inbox, shows the match | "Possible duplicate of <existing>" side-by-side | ✓ |
| In inbox, plain flag | Just a "possible duplicate" tag | |
| Auto-discard duplicates | Silently drop (contradicts ING-14) | |

**User's choice:** In inbox, shows the match — discard or accept

---

## Accounts (user-raised during wrap-up)

User observed expenses involve a bank account that isn't surfaced, and suggested managing
accounts + balances in Settings. Split into in-scope (parsed source label) vs scope creep
(account entities + balance tracking — explicitly Out of Scope in PROJECT.md).

| Option | Description | Selected |
|--------|-------------|----------|
| Store + show source label | Persist parsed card/account string, display it; schema multi-account-ready | ✓ |
| Just store, don't show yet | Capture in data, no UI | |
| Keep account out entirely | Parser reads card digits only for dedup | |

**User's choice:** Store + show source label

---

## Claude's Discretion

- Confidence-scoring mechanics (how 0.85 is computed)
- Reversal/refund matching UX (ING-09 locks negative-entry behavior)
- BGAppRefreshTask cadence (iOS-scheduled; must be device-verified overnight)
- Exact SchemaV4 model shape (new Expense fields vs separate ReviewItem model)
- Visual treatment of Review Inbox / "auto" marker / source label (UI-SPEC)

## Deferred Ideas

- Account management + balance tracking (own future phase; balance is Out of Scope)
- User-editable merchant seed (v2)
- Per-merchant learned category memory (v2)
- Inbox/budget push notifications (v2)
- More bank parsers beyond HDFC + ICICI (v2)
