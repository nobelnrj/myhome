# Phase 8: Stabilization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-08
**Phase:** 8-Stabilization
**Areas discussed:** Day-agenda delete UX, Gmail sync error handling, Regression tests, RoutineResetService stub

---

## Day-agenda delete behavior (STAB-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Row vanishes live, sheet stays | Deleted item's row disappears immediately; sheet stays open with remaining reminders; empty state if it becomes empty | ✓ |
| Auto-dismiss if now empty | Row vanishes; sheet auto-dismisses to calendar if it was the last reminder | |
| Just don't crash | Minimal guard; don't engineer live-update; stale row may linger until reopen | |

**User's choice:** Row vanishes live, sheet stays
**Notes:** Most seamless; preserves the existing live-binding design, just guards tombstoned access.

---

## Gmail sync error handling (STAB-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Skip bad message, continue | Log and skip the failing message, keep processing, batch-save at end | ✓ |
| Abort whole batch | Stop on first error and discard the batch | |

**User's choice:** Skip bad message, continue
**Notes:** One malformed email must never block the inbox; matches existing per-message resilience.

---

## Regression tests

| Option | Description | Selected |
|--------|-------------|----------|
| Add Swift Testing regression tests | Tests reproducing both crash vectors so they can't silently return | ✓ |
| Manual verification only | Fix + verify on-device; no new automated tests | |

**User's choice:** Add Swift Testing regression tests

---

## RoutineResetService stub (STAB-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Logged scaffold | Full scenePhase .active → resetIfNeeded() call path + "would reset" log; no model writes | ✓ |
| Pure no-op | Wired but empty method body | |

**User's choice:** Logged scaffold
**Notes:** De-risks the Phase 9 wiring now so Phase 9 only fills the body.

---

## Claude's Discretion

- Exact tombstone-detection mechanism (isDeleted check vs. validity probe vs. try/guard).
- Test harness shape (in-memory ModelContainer, fixture builders).

## Deferred Ideas

None — discussion stayed within phase scope.
