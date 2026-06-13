# Test-infra: SwiftData multi-ModelContainer cast crash in combined test suite

**Filed:** 2026-06-13 (during Phase 12 execution)
**Severity:** medium (test-infrastructure; not a product defect)
**Area:** MyHomeTests — model/migration/notes suites

## Symptom

Running the **combined** full suite in one process
(`xcodebuild test -scheme MyHome ...` over all suites) crashes non-deterministically:

```
SwiftData/ModelContext.swift:712: Fatal error: Failed to cast model
MyHome.SchemaV9.Note (or .NoteBlock) for PersistentIdentifier(... /Note/p1 ...) to Note.
```

The object's type and the cast target are the same type (`SchemaV9.Note` == typealias `Note`),
so the failure is the well-known SwiftData behaviour where **multiple `ModelContainer`s for the
same models instantiated in one process** produce distinct managed-object subclasses and a
`PersistentIdentifier` minted by one container fails to cast inside another.

## Evidence it is harness-only, not a product bug

- Clean `xcodebuild build` SUCCEEDS.
- Every suite passes **in isolation** (e.g. `-only-testing:MyHomeTests/NoteModelTests` alone… up to the point a 2nd container is created within the suite).
- Non-deterministic: at least one full run reported "156 tests passed" in the Swift Testing summary before the process exited non-zero.
- Production instantiates exactly ONE `ModelContainer` (SchemaV9) — this crash cannot occur in the app.
- Exposed (not caused in a product sense) by Phase 12 adding the 9th versioned schema + the `RoutineCompletion` model, which tipped the existing multi-container test pattern over.

First crashing test observed: `NoteModelTests / noteSavesUnderProductionVersionedSchema — STAB-08` (after 4 prior container-creating tests in the same suite).

## Suggested fix (separate task)

Refactor how the model/notes/migration test suites build containers so at most one live
`ModelContainer` exists per process at a time. Options:
- Share a single in-memory `ModelContainer` across tests in a suite (and across suites where
  feasible) instead of building a fresh container per test.
- Ensure deterministic teardown/release of each test's container before the next is created.
- Or split the migration/model suites into a separate test plan that runs in its own process.

Acceptance: `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`
exits 0 with all suites green in a single combined run.

## Phase 12 disposition

Phase 12 accepted as feature-complete (build clean, all suites green in isolation, four real
migration-fixture regressions fixed in commit `9d4ec62`). This harness issue deferred per user
decision on 2026-06-13.
