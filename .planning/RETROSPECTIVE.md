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

## Milestone: v1.3 — Private Sync & Kitchen

**Shipped:** 2026-07-22
**Phases:** 5 (18–22) | **Plans:** 22
**Schema:** SchemaV9 → V11 | **Tests at close:** 697 green (Phase 19 sweep)

*(v1.1 and v1.2 retrospective sections were never written — a process gap; their lessons live in their milestone archives.)*

### What Was Built
- Private P2P household sync — a pure, transport-agnostic merge engine (syncID identity, last-writer-wins on `updatedAt`, tombstones/`DeletionLog`, Decimal-as-string, version-stamped snapshots) reused verbatim across two free transports: AirDrop `.myhomesnap` exchange and encrypted MultipeerConnectivity over home WiFi.
- A trustworthy sync surface + first-run "set up from your other phone" bootstrap that provably never clobbers local edits.
- Kitchen — pantry stock, per-item low-stock thresholds, an auto-restocking shopping list, all synced; on-device FoundationModels pantry icons chosen from a closed category set with a keyword-table fallback.
- Overview filtering — account subset × custom date range, reusing the confirmed-self-transfer exclusion.

### What Worked
- **One tested merge engine, two transports:** building the pure LWW+tombstone core in Phase 18 (13 GREEN unit tests, golden round-trip idempotence) meant Phase 19's Multipeer transport and the AirDrop path both composed it without re-implementing merge logic.
- **Additive CloudKit-ready schema discipline held again:** SchemaV9→V10→V11 each an additive superset, all typealiases + the production container flipped atomically (the STAB-08 footgun protocol), proven by fixture migration tests before any UI.
- **Protocol seams for untestable system APIs** (`SyncTransport`, `FakeSyncTransport`) let the coordinator be proven end-to-end on in-memory stores before hardware.
- **Reusing the Phase-16 on-device model stack** for pantry icons kept Phase 22 cheap — closed `@Generable` enum → Swift-verified symbol removed the "fake SF Symbol draws nothing" class of bug structurally.

### What Was Inefficient
- **Human-verification debt kept accumulating:** Phase 20's kitchen verification reached milestone close still `human_needed`, and older v1.1-era verification/UAT gaps rode along again — the same per-phase-vs-close drift flagged in v1.0.
- **A seeded simulator on the LAN can pollute the real phones' Kitchen** via auto-sync (no confirm, connects to any same-service peer) — a sharp footgun discovered during UAT, now guarded by never joining auto-sync in a `-seedSampleData` build, but the underlying "trusts any LAN peer" gap is deferred to v1.4 (#43).
- **AI insight quality:** the on-device insight miscounts investments as spend — surfaced in real use, deferred to v1.4 (#30/#36).

### Patterns Established
- Transport-agnostic sync: a pure snapshot/merge core + a thin `SyncTransport` seam; identity via app-level `syncID`, deletes via tombstones, conflicts via vantage-independent LWW tiebreak.
- Bootstrap-vs-merge gating: a pure advisor decides "genuinely empty store" before a one-shot full-copy seed; everything else goes through never-clobber LWW.
- Derived-not-stored UI state: pantry icons and the restock shopping section are computed live, never persisted or synced.

### Key Lessons
1. **Sync's crux is merge safety, not transport** — investing the first phase entirely in a tested, transport-independent merge engine paid off across both transports and the bootstrap flow.
2. **Auto-connecting P2P needs an allowlist from day one** — "connect to any same-service peer" is convenient in a two-phone demo and dangerous the moment a third device (even a seeded simulator) is on the LAN. Trust should have been scoped in v1.3, not deferred.
3. **Clear human-verification per phase** — the v1.0 lesson recurred; carrying manual passes to milestone close keeps happening and should be gated at phase boundaries.

### Cost Observations
- Model mix: Opus/Sonnet quality profile (GSD model profile = quality)
- Notable: wave-based parallel execution again kept phases at 3–5 plans; the pure-core-first ordering minimized rework.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 7 | 26 | Established GSD discuss→plan→execute→verify loop with Wave-0 TDD scaffolds |
| v1.1 | 6 | 26 | (retro not written) — finance hub; auto-detect-then-confirm pattern |
| v1.2 | 5 | 28 | (retro not written) — neumorphic design system; on-device FoundationModels introduced |
| v1.3 | 5 | 22 | Transport-agnostic sync core; phase-branch + PR flow; GitHub tracker as backlog |

### Cumulative Quality

| Milestone | Stack | LOC | Schema Version |
|-----------|-------|-----|----------------|
| v1.0 | Swift 6.2 / SwiftUI / SwiftData | ~16,000 | SchemaV4 |
| v1.3 | Swift 6.2 / SwiftUI / SwiftData | — | SchemaV11 |

### Top Lessons (Verified Across Milestones)

1. **Update requirement/plan checkboxes and human-verification at phase close, not milestone close** — the drift flagged in v1.0 recurred in v1.3; it is the single most consistent process gap.
2. **Isolate the riskiest sub-system in its own phase, pure core first** — the v1.0 Gmail split and the v1.3 sync-merge-engine-first ordering both de-risked the milestone.
