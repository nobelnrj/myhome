---
phase: 9
slug: schemav6-accounts-management
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-09
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 26.5) |
| **Config file** | none — existing `MyHomeTests` target |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/MigrationTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~60–120 seconds (full); ~30s (migration only) |

---

## Sampling Rate

- **After every task commit:** Run quick command (migration tests) when migration/schema files touched
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

> Filled by the planner per task. Each schema/migration/balance task maps to a Swift Testing case;
> UI-only tasks map to manual verification (see below).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | ACCT-08 / STAB-04 | — | lossless V5→V6 backfill; idempotent didMigrate | unit | quick command | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/MigrationTests.swift` — extend with `MigrationTestsPlanV5` helper + V5→V6 fixture test (success criterion 4)
- [ ] Seed-a-real-V5-store fixture (temp-file `ModelContainer` under `SchemaV5`, re-opened under `AppMigrationPlan`)

*Existing infrastructure (MigrationTests V3→V5 pattern, lines ~105–173) covers the harness shape; the V5→V6 case extends it.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Account CRUD + archive UX (hide from pickers, keep history) | ACCT-01/02/03/07 | SwiftUI navigation/visual state | Settings > Accounts: add/edit/delete/archive; confirm archived account leaves pickers but transactions remain |
| Live balance updates without refresh | ACCT-04/05 | Reactive @Query observation visible only at runtime | Set baseline + as-of date; add an attributed expense; confirm balance changes with no manual refresh |
| Per-account spend (both entry points) | ACCT-06 | Navigation + filter UX | Tap account detail; apply account filter on expense list |
| Daily routine reset each IST morning | STAB-04 / NOTE-02 | scenePhase + date-boundary behavior | Flag a note isDailyRoutine, check items, advance day / re-activate; confirm unchecked once per day |
| First-launch migration review list (rename/merge/delete auto-created accounts) | ACCT-01 / D-02 | One-time post-migration UX | Migrate a V5 store with multiple sourceLabels; confirm editable review surfaces |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
