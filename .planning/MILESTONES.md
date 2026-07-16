# Milestones

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
