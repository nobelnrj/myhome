# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-06-03
**Phases:** 7 | **Plans:** 26 | **Tasks:** 43
**Timeline:** 2026-05-28 → 2026-06-03 (~6 days) | **Commits:** 209 | **Code:** ~16,000 LOC Swift / 106 files

### What Was Built
- Manual + automated (Gmail bank-email) expense tracking on a CloudKit-ready SwiftData spine
- Categories, single-tag (multi-tag-ready), per-category budgets with threshold-colored progress
- Notes + reminders hub: block notes, inline checklists, recurrence, local notifications, calendar
- Overview dashboard with Swift Charts (spend-by-category + spend-over-time)
- Face ID gate with full LAError handling + Settings shell
- Gmail OAuth (PKCE, no SDK) → HDFC/ICICI parsers → confidence triage → Review Inbox → dedup → BGAppRefreshTask

### What Worked
- **Load-bearing sequencing held:** manual expense entry before Gmail ingestion validated the schema/UI/budget loop before staking the project on the riskiest sub-system. Folding one-way-door lock-ins (bundle/CloudKit/App-Group IDs, privacy manifest) into Phase 1 meant no later rewrites.
- **Isolating Gmail OAuth (Phase 6) before the pipeline (Phase 7)** de-risked auth/network independently; Phase 7 wiring was mostly composition.
- **Wave-0 RED scaffold → pure-helper GREEN** TDD pattern (BudgetCalculator, ConfidenceScorer, DedupChecker, MerchantNormalizer, NotificationScheduler) produced testable cores without a device.
- **CloudKit-readiness rules enforced from day one** kept every schema bump (V1→V4) additive and migration-tested against bundled stores.

### What Was Inefficient
- **Checkbox/status drift:** at milestone close, 7 ING requirements and Phase 6's 06-04 plan were still marked incomplete despite being shipped — markers lagged execution and had to be reconciled during close.
- **Phase 7 confidence threshold (0.85) shipped uncalibrated**, carried as a known item pending a real week of inbox data.
- **Human-verification artifacts accumulated:** 2 partial UATs + 2 human-needed verifications reached close still open (acceptable — manual on-device passes — but they piled up rather than being cleared per-phase).

### Patterns Established
- Protocol-port seams for untestable system APIs (`NotificationCenterPort`, `BiometricAuthPort`, Gmail/Keychain ports) with spy conformers for unit tests.
- VersionedSchema nesting + `typealias` flip for clean view imports across schema versions.
- Whole-template fingerprint matching separated from value extraction in bank parsers (no single mega-regex per bank).

### Key Lessons
1. **Update requirement/plan checkboxes at phase close, not milestone close** — drift makes the milestone audit noisy and erodes trust in the tracking.
2. **Isolate the riskiest sub-system in its own phase** — the Phase 6/7 split paid off; repeat for future high-risk integrations.
3. **Calibration-dependent thresholds need an explicit follow-up gate** — don't let "tune after real data" live only in a summary; track it as an open item.

### Cost Observations
- Model mix: primarily Opus for planning/execution (single-developer GSD workflow)
- Sessions: multi-session across ~6 days
- Notable: heavy use of wave-based parallel plan execution kept phases compact (2-6 plans each)

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 7 | 26 | Established GSD discuss→plan→execute→verify loop with Wave-0 TDD scaffolds |

### Cumulative Quality

| Milestone | Stack | LOC | Schema Version |
|-----------|-------|-----|----------------|
| v1.0 | Swift 6.2 / SwiftUI / SwiftData | ~16,000 | SchemaV4 |

### Top Lessons (Verified Across Milestones)

1. (Awaiting v1.1 to cross-validate.)
