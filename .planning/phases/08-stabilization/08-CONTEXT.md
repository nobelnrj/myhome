# Phase 8: Stabilization - Context

**Gathered:** 2026-06-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the live v1.0 app crash-free and correct two known defects, with **no schema changes**:

1. **STAB-01** — Notes calendar / day-agenda no longer crashes when a note or block is deleted while open (guard `DayAgendaView` / `AgendaReminderItem` against tombstoned `@Model` references).
2. **STAB-02** — Gmail sync runs to completion regardless of inbox size: re-fetch `Category` references by `PersistentIdentifier` after each `await`; call `ctx.save()` **once** after the full batch, not inside the per-message loop.
3. **STAB-03** — Adding a new custom category appends it to the **bottom** of the list (`max(existing.sortOrder) + 1`), not the top.
4. **STAB-04** — Ship a `RoutineResetService` skeleton wired to `RootView.onChange(of: scenePhase)` on `.active`. No-op this phase (no schema field yet); Phase 9 fills the body once `NoteBlock.lastCheckedDate` exists.

**Out of scope:** Any schema migration (that is Phase 9 / SchemaV6), the actual routine-reset logic, accounts/assets/transfer work.

</domain>

<decisions>
## Implementation Decisions

### STAB-01 — Day-agenda delete crash behavior
- **D-01:** Beyond not crashing, the deleted item's row **vanishes live and the sheet stays open** showing the remaining reminders. If the day becomes empty, fall back to the existing `ContentUnavailableView` "No Reminders" empty state. Do **not** auto-dismiss the sheet.
- **D-02:** Preserve the existing live-binding design (D3: agenda binds live to `Note`/`NoteBlock`, never snapshots). The fix is to guard `@Model` property access against tombstoned/deleted objects in `AgendaReminderItem`'s computed properties and `remindersOnDay` — e.g. skip targets whose backing model `isDeleted` (or otherwise invalid) so the `ForEach`/computed accessors never touch a faulted, deleted object.

### STAB-02 — Gmail sync error handling
- **D-03:** On a per-message parse failure **or** a category re-fetch failure after the batch-save refactor, **skip the bad message and continue** processing the rest, then perform the single batched `ctx.save()` at the end. One malformed email must never block the whole inbox. This matches the existing per-message resilience in `syncAccount`.
- **D-04:** `Category` references must be re-resolved by `PersistentIdentifier` after each `await` suspension point (the captured object may be invalidated across the suspension). The single batched save moves out of the per-message loop.

### STAB-03 — Category insertion order
- **D-05:** New custom categories use `max(existing.sortOrder) + 1` insertion. Note: `ManageCategoriesView.addCategory` (MyHomeApp/Features/Budgets/ManageCategoriesView.swift:191-193) **already** does this. Research must locate the *actual* offending add path (likely an inline quick-add elsewhere, a seed path, or a `sortOrder` default of 0 colliding at the top) before assuming a fix is needed in `ManageCategoriesView`.

### STAB-04 — RoutineResetService stub
- **D-06:** Ship a **logged scaffold**, not a bare no-op. The stub must establish the full call path — `RootView` `scenePhase` `.active` → `RoutineResetService.resetIfNeeded()` — and log a "would reset" message (IST `startOfToday` comparison can be sketched), but perform **no model writes** this phase. Phase 9 fills the body once `NoteBlock.lastCheckedDate` lands. This de-risks the wiring now so Phase 9 only adds logic.
- **D-07:** Wire the service alongside the existing `scenePhase` observers in `RootView` (`LockController.scenePhaseChanged`, `gmailSyncController.scenePhaseChanged`). Follow the established `@MainActor` / `Task`-wrapping pitfall guidance already present in `RootView.body`.

### Testing
- **D-08:** Add **Swift Testing regression tests** that lock in both crash fixes: (a) delete-a-note/block-while-day-agenda-open, and (b) Gmail sync across an `await` suspension with category re-fetch + batched save. These must fail against the pre-fix behavior and pass after, so the crashes can't silently regress.

### Claude's Discretion
- Exact tombstone-detection mechanism (`isDeleted` check vs. `modelContext`-based validity probe vs. try/guard) — researcher/planner picks the SwiftData-idiomatic approach for iOS 17+.
- Test harness shape (in-memory `ModelContainer`, fixture builders) — follow existing Swift Testing patterns in the repo.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap & requirements
- `.planning/ROADMAP.md` §"Phase 8: Stabilization" — goal + 4 success criteria (the binding contract for this phase)
- `.planning/REQUIREMENTS.md` STAB-01 … STAB-04 — requirement text and the STAB-04/NOTE-02 split note
- `.planning/ROADMAP.md` §"Cross-Phase Notes" — STAB-04 ships skeleton only; full reset is Phase 9 (requires `NoteBlock.lastCheckedDate`)

### Crash-vector source (read before fixing)
- `MyHomeApp/Features/Notes/CalendarView.swift` — `AgendaReminderItem` (live-model wrapper, lines ~224-270), `DayAgendaView.remindersOnDay` (~295-319), `toggleCompletion` (~407) — the STAB-01 crash surface
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — `syncAccount` (~421-535): per-message loop, `Category` fetch (~480-488), `ctx.save()` currently inside loop (~533) — the STAB-02 crash surface
- `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` §`addCategory` (~175-194) — STAB-03 reference implementation (already correct; find the real offender)
- `MyHomeApp/RootView.swift` §`.onChange(of: scenePhase)` (~106-114) — where `RoutineResetService` wires in

### No new external specs
- No new ADRs/specs introduced this phase — requirements fully captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RootView.scenePhase` observer block (RootView.swift:106-114) — already hosts `LockController` and `gmailSyncController` scene-phase hooks; `RoutineResetService` slots in here.
- `ContentUnavailableView` "No Reminders" empty state (CalendarView.swift:324-329) — reuse as the empty fallback when a day's last reminder is deleted (D-01).
- `ManageCategoriesView.addCategory` `max(sortOrder)+1` pattern (line 191-193) — canonical sort-insertion pattern to replicate wherever the STAB-03 bug actually lives.

### Established Patterns
- Calendar agenda binds **live** to `@Model` (D3 decision) — the cause of the STAB-01 crash and a constraint: the fix must keep live binding, just guard tombstoned access. Do not switch to snapshots.
- `scenePhase` handlers wrap async work in `Task` and use `@MainActor` (RootView + LockController) — `RoutineResetService` must follow this for Swift 6 strict concurrency.
- Gmail sync already tolerates per-message failures; D-03 extends that to the post-`await` category re-fetch.

### Integration Points
- `RootView` ← new `RoutineResetService` (owned/injected like `gmailSyncController`).
- `GmailSyncController.syncAccount` save refactor — single batched `ctx.save()` after the message loop; verify no downstream reader assumes incremental persistence mid-sync.

</code_context>

<specifics>
## Specific Ideas

- iOS 17+ deployment target; build/run on iPhone 17 simulator, Xcode 26.5, scheme `MyHome`.
- IST (`Asia/Kolkata`) is the household timezone — the routine-reset "start of today" comparison must be IST-based when Phase 9 implements it; the Phase 8 scaffold should sketch this so the seam is correct.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Routine-reset logic, `NoteBlock.lastCheckedDate`, and accounts/transfer work are already roadmapped to Phases 9-12.)

</deferred>

---

*Phase: 8-Stabilization*
*Context gathered: 2026-06-08*
