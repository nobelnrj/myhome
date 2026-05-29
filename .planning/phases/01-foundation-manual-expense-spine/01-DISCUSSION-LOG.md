# Phase 1: Foundation & Manual Expense Spine - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 1-foundation-manual-expense-spine
**Areas discussed:** Amount & date entry

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| One-way-door identifiers | Bundle / CloudKit / App Group IDs (FND-02), immutable | |
| Expense schema fields | What a v1 expense captures beyond amount + date | |
| Category in Phase 1 flow | How category works before the Phase 2 category system | |
| Amount & date entry | Date default, time component, sign, decimal behavior | ✓ |

**User's choice:** Amount & date entry only. The other three were delegated to Claude's discretion.

---

## Amount & Date Entry

### Transaction date behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Default to now, editable | Pre-fills current date/time; date picker to backdate | ✓ |
| Always pick a date | Forces a date choice every time | |

**User's choice:** Default to now, editable.

### Time-of-day component
| Option | Description | Selected |
|--------|-------------|----------|
| Date + time (UTC) | Full timestamp UTC, display local; future-proofs ordering + bank emails | ✓ |
| Date only | Calendar day only | |

**User's choice:** Date + time (UTC).

### Negative amounts in v1
| Option | Description | Selected |
|--------|-------------|----------|
| Positive-only in v1 UI | Manual entry positive only; schema still holds negatives | |
| Allow negative now | Users can type negative amounts manually in v1 | ✓ |

**User's choice:** Allow negative now.

### Decimal / paise handling
| Option | Description | Selected |
|--------|-------------|----------|
| Decimal keypad, paise optional | Standard pad; whole rupees fine, paise when needed | ✓ |
| Cents-style auto-decimal | Digits fill from the right (49950 → ₹499.50) | |

**User's choice:** Decimal keypad, paise optional.

---

## Claude's Discretion

- **Expense schema fields** — decided: id/amount/currencyCode/date/note/createdAt/updatedAt per CloudKit-readiness rules (D-05/D-06).
- **Category in Phase 1 flow** — decided: picker deferred to Phase 2; Phase 1 add flow is amount → save; schema kept forward-compatible for an additive Phase 2 migration (D-07/D-08).
- **One-way-door identifiers** — proposed defaults `com.reojacob.myhome` / `iCloud.com.reojacob.myhome` / `group.com.reojacob.myhome`, iOS 17.0 min (D-09). **Flagged for user confirmation before project creation — these are immutable.**
- Project structure, test-fixture pattern, en-IN formatter choice, ModelContainer wiring, and screen visual layout (UI-SPEC owns the latter).

## Deferred Ideas

- Category picker + India-tuned list + custom CRUD → Phase 2.
- Normalized merchant field, raw email body, parserID/parserVersion → Phase 7.
- Multi-currency display / FX → out of scope (schema carries currencyCode, UI INR-only).
- Tags, budgets, month grouping → Phase 2.
