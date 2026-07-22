# Milestones

## v1.3 Private Sync & Kitchen (Shipped: 2026-07-22)

**Phases completed:** 5 phases (18–22), 22 plans

**Delivered:** Free private P2P sync between the two phones (AirDrop + MultipeerConnectivity over a tested, transport-agnostic LWW/tombstone merge engine, with bootstrap), a synced Kitchen (pantry + auto-restocking shopping list, on-device pantry icons), and account × date-range Overview filtering — no cloud, schema stays CloudKit-ready (SchemaV9→V11). Requirements 15/15 complete.

**Known deferred items at close:** 5 (see STATE.md → Deferred Items; all mirrored in GitHub tracker #24/#25/#26). Two security gaps queued first for v1.4: Face ID review fixes (#31), auto-sync LAN-peer allowlist (#43).

**Key accomplishments:**

- Authored SchemaV10 as an additive superset of SchemaV9 that stamps every one of the 11 persisted models with `syncID: UUID` + `updatedAt: Date`, introduced the `DeletionLog` tombstone @Model, wired a `v9ToV10` migration stage whose `didMigrate` backfills per-row distinct syncIDs (defeating the SwiftData constant-default footgun), flipped all 12 typealiases + the production container to V10 atomically (STAB-08), and proved it with fixture migration tests.
- A pure, Foundation-only `SyncSnapshot` (version-stamped, Decimal-as-String, canonical-deterministic JSON via `SnapshotCodec`) plus a two-function `SyncMergePolicy` (LWW with a vantage-independent canonical-bytes tiebreak and no-resurrection tombstones) — the byte-for-byte transport contract Phase 19 reuses, locked down by 13 GREEN pure-unit tests.
- Transport-agnostic SYNC-02 merge engine: deterministic full-store export and a tombstones-first, fetch-then-upsert-on-syncID importer with field-level LWW, two-pass relationship wiring, and min-uuidString identity adoption — golden round-trip proven idempotent on in-memory containers.
- Wired the sync model into live writes: every syncable delete now routes through `ModelContext.deleteSynced` (tombstone-then-delete, cascade-tombstoning Note blocks), and user edits stamp `updatedAt` via `touch()` so the Plan-03 LWW engine resolves on honest human clocks instead of migration backfill.
- Device-to-device `.myhomesnap` exchange: an exported custom UTType makes AirDrop/Files carry snapshots with no entitlement, exported from Settings via the share sheet and imported through onOpenURL/.fileImporter into a decode-then-confirm merge sheet backed by the Phase-18 engine.
- Encrypted MultipeerConnectivity P2P transport behind a `SyncTransport` protocol seam — SyncEnvelope wire format carrying Phase-18 snapshot bytes, a deterministic invite tie-break killing the MC dual-connect race, and Swift-6-clean off-main delegate hops.
- @MainActor @Observable `SyncCoordinator` that drives the 19-01 transport seam — connect-triggered symmetric snapshot exchange, `isMerging` echo-loop suppression, capped-backoff retry, and manual `syncNow` — reusing the Phase-18 merge engine verbatim and proven end-to-end with a paired `FakeSyncTransport` on in-memory SchemaV10 stores.
- A neumorphic Sync screen — reachable from Settings — that shows live status, connected-peer name, relative last-synced time, and last merge stats, with a 'Sync Now' CTA wired to SyncCoordinator.syncNow(); all display logic lives in the pure, unit-tested SyncStatusPresentation mapper.
- A first-run "Set up from your other phone" sheet that seeds a fresh install with a full copy of the other phone's data over the EXISTING Phase-18 snapshot exchange — a pure BootstrapAdvisor gates the one-shot prompt on genuine store-emptiness, and a loopback test pins the never-clobber guarantee (a non-empty store merges via LWW, never wipes).
- One automated regression sweep proving the full sync stack holds together — 697 tests green in a single run (transport → coordinator → presentation → bootstrap → Phase-18 merge engine, plus dark byte-identity), every phase-wide regression gate re-asserted, and a light+dark simulator review set of the new Sync surface and bootstrap sheet — with the single unavoidable end-of-phase two-phone hardware sign-off flagged as the one remaining gate.
- Authored SchemaV11 as an additive superset of SchemaV10 that copies all 12 existing classes verbatim and adds `PantryItem` and `ShoppingListItem` — both carrying `syncID`/`updatedAt` and conforming to `SyncStamped` from birth so they flow through the Phase 18 sync engine with no backfill — wired the `v10ToV11` migration stage, flipped all 14 typealiases + 13 conformances + the production container atomically (STAB-08), and proved it with fixture migration tests.
- Wired PantryItem/ShoppingListItem into the Phase 18 merge engine end-to-end — full-fidelity DTOs, `SyncEntityKind` cases, `currentSchemaVersion` bumped 10→11 in lockstep with SchemaV11, exporter/importer support for tombstones, normalized-name adoption and LWW, and `SyncScope.production` widened to notes+kitchen — proven by 10 new `KitchenSyncTests` while every financial kind stays provably off the wire.
- Built the pantry half of the Kitchen surface to the user's binding mockups — a neumorphic Running-low/Stocked list with derived icon tiles, LOW/OUT badges, 44pt −/+ steppers, and a unit-chip edit sheet — all stock state derived through a single tested `KitchenLogic`, every delete tombstoned via `deleteSynced(kind: .pantryItem)`, and the surface reachable from day one through a pushed Overview entry that leaves the 5-tab bar and `-startTab` indices untouched.
- Shipped the shopping half of the Kitchen to the user's binding mockups — a `Pantry | Shopping` segmented host whose RESTOCK section is computed live from pantry state and never written to disk, where one tap restocks the pantry by `restockQuantity` and the row leaves the list, alongside manually-added EXTRAS that sync, check off without touching the pantry, and are deleted only through tombstoned `deleteSynced(kind: .shoppingListItem)`.
- Phase 20 gates green: 652 tests in 90 suites passed with `-parallel-testing-enabled NO` and zero failures, all five structural invariants hold on the integrated tree, the kitchen surface is captured in both themes, and the one inconsistency the phase carried — a bootstrap advisor that still thought a kitchen-only phone was a fresh install — was closed rather than deferred.

---

## v1.2 Neumorphic Redesign (Shipped: 2026-07-13)

**Phases completed:** 5 phases (13-17), 28 plans
**Timeline:** 2026-06-20 → 2026-07-13 (~23 days)
**Code:** 188 commits since v1.1
**Requirements:** 28/29 v1.2 requirements complete (DS-03 floating tab bar intentionally reverted to native)

**Delivered:** Transformed My Home from a stock-SwiftUI app into a polished, cohesive neumorphic (Soft UI) product with light + dark theming — a single-source design system, every screen restyled with zero regressions, a "where it's going" spend donut on Overview, a dedicated Analytics screen, and an on-device AI Insight card. Zero new dependencies, iOS 17 floor, no schema change, local-only.

**Key accomplishments:**

- **Phase 13 — Design System Foundation:** Single-source `DesignTokens` (charcoal palette, canary-yellow accent, dual light/dark shadows, 26px radii, spacing scale), reusable `NeuSurface` raised/recessed/floating modifier family, `RollingMoneyText` numeric-transition readout, and accessibility infrastructure (WCAG 1.4.11, Dynamic Type, Reduce Motion).
- **Phase 14 — Restyle Existing Screens + Overview Donut:** All nine screen groups restyled to the neumorphic look with no regressions and full pbxproj registration; added the "where it's going" spend donut (SectorMark, top-4 + Others, rolling center total, self-transfer exclusion) with tap-to-filter into Activity.
- **Phase 15 — Analytics Screen:** New push-in Analytics screen with week/month/year range tabs, spending-trend `AreaMark` (IST-correct bucketing), by-category `BarMark`, and inverted-color period delta chips — all fed by a single pure/testable `AnalyticsAggregator` producing a reusable `SpendSummary`.
- **Phase 16 — AI Insight Card:** On-device natural-language spending insight via Apple FoundationModels (iOS 26), two-layer availability gating (silent absence where unsupported), `@Generable` guided generation, numeric-integrity verification (model never invents figures), and a streaming typewriter that honors Reduce Motion.
- **Phase 17 — Light Mode Support (promoted from backlog):** Full adaptive palette, reworked neumorphic shadow directions/opacities for a light canvas, non-glow treatment for the particle orb + activity rings, System/Light/Dark theme setting — with a byte-identical dark-rendering guarantee (DarkBitIdentityTests).

**Known deferred items at close:** DS-03 floating tab bar reverted to native (design decision). Retroactive doc debt: phases 13–14 have no VERIFICATION.md; Nyquist VALIDATION gaps on phases 14/15/16. No functional blockers — integration/E2E verified empirically by building and running on two physical devices. See `.planning/v1.2-MILESTONE-AUDIT.md`.

---

## v1.1 Accounts, Assets & Household Polish (Shipped: 2026-06-20)

**Phases completed:** 6 phases (8-12, incl. inserted 11.1), 26 plans
**Timeline:** 2026-06-03 → 2026-06-20 (~17 days)
**Code:** ~118 Swift files in the app target; 200 commits since v1.0 (365 files changed, +49k/-26.8k LOC across app + planning)
**Requirements:** 32/32 v1.1 requirements complete

**Delivered:** Grew My Home from an automated expense tracker into a light household finance + ops hub — account-aware spend with self-transfer detection, a net-worth Asset Tracker (manual holdings + free AMFI MF NAV + allocation/trend charts), SIP automation with NPS NAV auto-refresh, a Notes daily-routine enhancement (calendar surfacing, timed notifications, drag-reorder, streak/history), and a stability/UX cleanup pass. Local-only, free-data-only, manual override always available.

**Key accomplishments:**

- **Phase 8 — Stabilization:** Fixed two production crash vectors (Notes calendar tombstone access; Gmail sync Category-after-await + per-loop save), locked category insertion order, and scaffolded the RoutineResetService.
- **Phase 9 — SchemaV6 & Accounts Management:** Additive V5→V6 migration (Account + Asset models, Expense/Note fields) with backfill fixture test; full Accounts CRUD with live baseline-±-transactions balances, per-account spend, archive, and per-day routine reset (IST).
- **Phase 10 — Self-Transfer Detection:** Deterministic 5-signal scorer + Transfer Inbox confirm/reject; confirmed transfers excluded from all spend/budget/charts and applied as balance-moves (net worth unchanged); manual mark/unmark on any expense.
- **Phase 11 — Asset Tracker:** MF/stock/NPS holdings CRUD, best-effort AMFI NAV auto-refresh with staleness badges, net worth = holdings + account balances with per-holding gain/loss, allocation donut, and net-worth trend snapshots.
- **Phase 11.1 — SIP Automation & NPS NAV (INSERTED):** Recurring SIP unit accrual service plus best-effort NPS NAV auto-refresh, reversing the v1.1 NPS-auto-fetch deferral once the manual flow was proven.
- **Phase 12 — Notes & Daily Routine Enhancement:** SchemaV9 RoutineCompletion model; routine notes surface on every calendar day, optional once-per-day timed notification (no duplicate stacking), drag-reorder of checklist items, and a forgiving streak + per-day completion history.

**Known deferred items at close:** 8 open artifacts acknowledged as deferred — see STATE.md → Deferred Items (1 partial Phase 09 UAT, 2 human-needed verifications, 1 stale multi-Gmail quick task, 1 test-infra todo). Code is implemented; the verification items are outstanding manual on-device passes.

---

## v1.0 MVP (Shipped: 2026-06-03)

**Phases completed:** 7 phases, 26 plans, 43 tasks
**Timeline:** 2026-05-28 → 2026-06-03 (~6 days)
**Code:** ~16,000 LOC Swift across 106 files, 209 commits
**Requirements:** 56/56 v1 requirements complete

**Delivered:** A single-user iOS household app for a two-person Indian household — automated bank-email expense ingestion plus manual entry, categories/tags/budgets, a notes + reminders hub, an overview dashboard with charts, and a Face ID gate — all on a CloudKit-ready SwiftData schema.

**Key accomplishments:**

- **Phase 1 — Foundation & Manual Expense Spine:** Locked one-way-door IDs (bundle/CloudKit/App-Group), CloudKit-ready SwiftData schema with VersionedSchema + migration plan proven against a bundled store, en-IN currency / UTC dates, and manual expense CRUD end-to-end via a custom decimal keypad.
- **Phase 2 — Categories, Tags & Budgets:** SchemaV2 with a 14-category India-tuned seed, single-tag-with-multi-tag-ready schema, per-category monthly budgets with threshold-colored progress bars, and a month view grouped by category.
- **Phase 3 — Notes & Reminders hub:** Block-style notes (interleaved text + inline checklists), pin/search/auto-save, plus a full reminders system — recurrence, end rules, local notifications with Complete/Snooze/deep-link actions, and a calendar view.
- **Phase 4 — Overview & Charts:** Default home dashboard with spend-vs-budget bar, top-3 categories, pinned-note card, and Swift Charts (spend-by-category + spend-over-time with range control).
- **Phase 5 — Face ID Gate & Settings:** Biometric app lock with full LAError handling and passcode fallback, plus a Settings shell for category/budget/lock management.
- **Phase 6 — Gmail Sign-In & Client:** Read-only Gmail OAuth via ASWebAuthenticationSession + PKCE (no Google SDK), refresh token in Keychain (`AfterFirstUnlockThisDeviceOnly`), 30-day backfill, "Sync now", last-synced timestamp, and reconnect CTA.
- **Phase 7 — Bank Parsers & Ingestion Pipeline:** HDFC + ICICI whole-template parsers, 0.85-confidence triage (auto-save / Review Inbox), merchant normalization, dedup, reversal/refund handling, parser provenance + raw-body storage, and a best-effort BGAppRefreshTask — calibrated against a live inbox.

**Known deferred items at close:** 4 open human-verification artifacts (2 partial UAT, 2 human-needed verifications) acknowledged as deferred — see STATE.md → Deferred Items. Code is implemented; these are outstanding manual on-device passes.

---
