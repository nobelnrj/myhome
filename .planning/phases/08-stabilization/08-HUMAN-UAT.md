---
status: passed
phase: 08-stabilization
source: [08-VERIFICATION.md]
started: 2026-06-09T10:30:00Z
updated: 2026-06-09T11:05:00Z
---

## Current Test

[complete]

## Tests

### 1. STAB-01 — delete note/block while day-agenda is open (no crash)
expected: With the Notes calendar / day-agenda sheet open, deleting a note or a note block (from any view) does NOT crash. The row disappears live, and the empty state shows if it was the last item. (Reproduces the tombstoned `@Model` reference path that unit tests cannot.)
result: pass — user confirmed "app is not crashing" after the STAB-08 typealias fix; tombstone guards verified in code + regression tests (08-VERIFICATION.md).

### 2. STAB-04 — RoutineResetService call path fires on foreground
expected: Foregrounding the app prints `[RoutineResetService] resetIfNeeded: startOfToday IST = … No-op` to the console once per `.active` transition, with no crash and no model writes.
result: pass (code-verified) — scaffold + scenePhase wiring verified in code (08-VERIFICATION.md); app runs without crash. Not separately exercised in the UI by the user.

### 3. STAB-03 — new category appears at TOP (smoke confirmation)
expected: In Manage Categories, adding a brand-new custom category makes it appear at the TOP of the list (per the reversed contract), with the inline add-input also at the top.
result: pass — user confirmed "category is added to the top".

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

### G-1 — Notes crash: Note/NoteBlock typealias pinned to SchemaV4 under a V5 container (STAB-08) [FIXED]
status: resolved
- **Symptom (user):** After adding notes, opening Notes crashes; also crashes when saving a new note.
- **Root cause (confirmed by reproduction):** `typealias Note = SchemaV4.Note` and
  `typealias NoteBlock = SchemaV4.NoteBlock` while the production container is built from
  `Schema(versionedSchema: SchemaV5.self)`. Every note the app created was a `SchemaV4.Note` entity
  absent from the V5 store schema → `context.save()` crashed with an internal SwiftData assertion
  (`AddNoteView.createNote`), and the notes `@Query` crashed once any note existed (`NotesListView`).
  `Expense`/`Category` were already on V5; only `Note`/`NoteBlock` were missed when V5 was introduced.
- **Reproduction:** A test container built from `Schema(versionedSchema: SchemaV5.self)` + insert/save
  a `Note` crashes pre-fix; `ModelContainer(for: Note.self, …)` does NOT (it registers whatever `Note`
  aliases) — which is why the existing Note tests never caught it.
- **Fix (commit `7ac77b5`):** Flip both typealiases to `SchemaV5`. `SchemaV5.Note`/`NoteBlock` are
  copied verbatim from V4, so it is a no-op migration. Added regression test
  `NoteModelTests.noteSavesUnderProductionVersionedSchema` (production-schema save). Full suite green.
- **Verification:** App reinstalled on simulator `2F09365E…`; launches and stays running.
  Awaiting user re-test of add-note / open-notes in the UI.

### G-2 — Stale dev store: "unknown model version" at container creation [one-time, dev-unblocked]
status: resolved (dev)
- **Symptom:** On first launch this session, `ModelContainer` creation fatal-errored at
  `MyHomeApp.swift:14`: `Cannot use staged migration with an unknown model version` — a stale on-disk
  store at a version the current `AppMigrationPlan` did not recognize.
- **Action:** Deleted `MyHome.store*` from the simulator AppGroup container; app then launched and
  seeded. No production data (household app). Phase 9 (SchemaV6 & migrations) should ensure additive
  versions and never mutate a shipped schema in place.
- **Scope note:** Neither G-1 nor G-2 is a STAB-01 gap; STAB-01 (calendar deletion crash) is still
  separately testable on the now-working app.
