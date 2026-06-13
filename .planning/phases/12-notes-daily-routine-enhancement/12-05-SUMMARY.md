# 12-05 Summary — Phase Exit Gate

**Plan:** 12-05 (Phase 12 exit gate)
**Status:** Task 1 complete (with documented deviation); Task 2 = human UAT checkpoint (pending)
**Date:** 2026-06-13

## Task 1 — Build & test gate

### Clean full build — PASS
`xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`
→ **BUILD SUCCEEDED**. Every new Phase-12 `.swift` file is compiled into its target
(explicit-file-refs landmine cleared). pbxproj registration verified — 4 entries each for:
SchemaV9.swift, RoutineCompletion.swift, StreakCalculator.swift,
RoutineNotificationService.swift, RoutineDetailView.swift, and the five new test files.

### Phase-12 automated tests — PASS (28/28 in isolation)
- SchemaV9MigrationTests 2/2 · StreakCalculatorTests 8/8 · RoutineNotificationServiceTests 8/8
  (incl. `exactlyOnePendingRequest` D-05) · NoteReorderTests 1/1 · RoutineCalendarTests 5/5
  (incl. dot-badge invariance D-02).

### Regression fixes (committed `9d4ec62`)
The 12-01 SchemaV9 typealias flip + AppMigrationPlan-now-terminates-at-V9 silently broke every
migration-fixture test (loadIssueModelContainer / CoreData 134100). Repaired:
- `MigrationTests`, `SchemaV6MigrationTests`, `SchemaV7MigrationTests` — migrate-to-current target
  bumped `SchemaV8` → `SchemaV9`.
- `SchemaV8MigrationTests` — pinned to the V8 endpoint via the trimmed `MigrationTestsPlanV8` +
  explicit `SchemaV8.*` types.
All migration suites now pass in isolation. No product code changed.

### DEVIATION — combined full suite not green (accepted)
The **combined** `xcodebuild test` over all suites in one process hits a non-deterministic
SwiftData multi-`ModelContainer` cast crash (`Failed to cast model SchemaV9.Note/NoteBlock to
Note/NoteBlock`). Root cause: SwiftData's known behaviour when multiple containers for the same
models exist in one process; exposed by Phase 12 adding the 9th versioned schema. **Not a product
defect** — production runs one container; every suite passes in isolation; clean build.
Per user decision (2026-06-13, "Accept + file follow-up"), Phase 12 is accepted as
feature-complete and the harness issue is filed at
`.planning/todos/pending/test-isolation-swiftdata-multicontainer.md`.

## Task 2 — Human UAT (pending)
`12-HUMAN-UAT.md` prepared with the four manual-only behaviors (D-05 single notification,
NOTE-04 reorder persistence, NOTE-01 every-day surfacing + no dot inflation, NOTE-05
cross-midnight streak retention). Awaiting human verification on the simulator.

## Requirements
NOTE-01, NOTE-03, NOTE-04, NOTE-05 — implemented + automated-tested in isolation; runtime
behaviors pending human UAT.
