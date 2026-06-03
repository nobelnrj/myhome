# Milestones

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
