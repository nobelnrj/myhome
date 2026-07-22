# Requirements — Milestone v1.3: Private Sync & Kitchen

**Milestone goal:** Let both phones share household data privately for free (no cloud, no $99 Apple Developer account), add a kitchen inventory + shopping list, and make the Overview filterable by account and date — turning My Home into a genuinely shared two-person hub.

**Constraints carried from v1.0/v1.1/v1.2:** local-only + now peer-to-peer (still no cloud/CloudKit — that remains the paid trigger), zero recurring cost, no paid third-party services/SDKs, no analytics/telemetry, free public data only with manual override always available, CloudKit-ready SwiftData schema (additive, no `.unique`, optional/defaulted), iOS 17 deployment floor, zero new paid dependencies.

**v1.3-specific ground rules (from the two 2026 deep-research reports):**
- **CloudKit / iCloud / Push are paid-only** and stay out of scope. Sync uses `MultipeerConnectivity` + AirDrop, which need **no entitlement** on a free Personal Team — only Info.plist privacy keys (`NSLocalNetworkUsageDescription`, `NSBonjourServices`).
- **Sync is foreground-only P2P.** No background sync (MC sessions die ~1s after backgrounding; Push is paid-only). Acceptable for a two-person household sharing home WiFi.
- **Merge safety is the crux:** the schema has no `.unique` constraints, so identity must be an app-level `syncID: UUID`; conflict resolution is last-writer-wins on `updatedAt`; deletes need tombstones or they resurrect; `Decimal` must be string-encoded (never JSON-Double); the payload must carry a schema version and refuse mismatched imports (the V4/V5 typealias incident is the precedent).
- **Raw store-file copy is bootstrap/backup only** — never an ongoing sync mechanism (it clobbers the receiver's local edits).
- The **7-day provisioning expiry is handled outside the app** by `scripts/auto-deploy.sh` (launchd) — it is NOT a milestone requirement.

---

## v1.3 Requirements

### Private P2P Sync (SYNC)

<!-- The merge engine is the transport-agnostic core; both transports reuse it. Ships FIRST. -->

- [x] **SYNC-01**: Every syncable `@Model` carries a stable `syncID: UUID = UUID()` and an `updatedAt: Date` stamped on every save (both additive/defaulted → still CloudKit-ready), and a `DeletionLog` model records `{syncID, deletedAt}` so a record deleted on one phone does not resurrect when the other phone's snapshot arrives.
- [x] **SYNC-02**: A pure, unit-tested merge engine imports a Codable snapshot via fetch-then-upsert keyed on `syncID` (no duplicates), resolves conflicts by last-writer-wins on `updatedAt` with a deterministic tiebreak, applies tombstoned deletes before upserts, wires relationships in a two-pass (create-then-link) order, string-encodes all `Decimal` values, and stamps + verifies a schema version — refusing imports from a mismatched schema. A golden round-trip test (export→import→export is idempotent) is a required exit criterion.
- [x] **SYNC-03**: User can export a data snapshot and send it to the other phone via the system share sheet / **AirDrop**; the receiving phone opens it via `onOpenURL`/document import and merges it through the SYNC-02 engine — fully device-to-device, no third party.
- [x] **SYNC-04**: When both phones have the app foregrounded on the same network, data **auto-syncs over MultipeerConnectivity** (encrypted P2P via `MCSession` with `.required` encryption; `NSLocalNetworkUsageDescription` + `NSBonjourServices` declared), with a manual "Sync now" action as an always-works fallback.
- [x] **SYNC-05**: A first-time "bootstrap this phone" flow can seed the second install with a full copy of the first phone's data; the sync surface shows last-synced time, current status, and a clear affordance — and never silently loses local edits.

### Kitchen Inventory (KTCH)

<!-- New household surface. CRUD over SwiftData, neumorphic, synced via the SYNC engine. -->

- [x] **KTCH-01**: User can track pantry stock — add/edit items with a quantity and unit, and mark an item as used (decrement) or restocked (increment).
- [x] **KTCH-02**: User can set a per-item low-stock threshold; items at or below their threshold are visually flagged as low/out of stock.
- [x] **KTCH-03**: A shopping list auto-populates from low/out-of-stock items; the user can check an item off while shopping, which restocks it (updates the pantry quantity); manually-added shopping items are also supported.
- [x] **KTCH-04**: Kitchen is a first-class neumorphic surface in the app (styled to the v1.2 design system, light + dark) and all kitchen models are registered as syncable so they flow through the SYNC engine.

### Pantry Icon Intelligence (ICON)

<!-- Added 2026-07-21 after Phase 20 UAT: the keyword table returns the neutral bag fallback for
     anything it has not seen ("kitchen tissue", "fabric softener"). Uses the SAME on-device
     FoundationModels stack as the AI insight card (Phase 16) — no network, no cost, no new
     synced state. -->

- [x] **ICON-01**: A pantry item's icon and tile colour are chosen by the on-device model from its name, so unseen names ("kitchen tissue", "fabric softener", "dish scrubber") get a meaningful icon instead of the neutral fallback.
- [x] **ICON-02**: The model cannot produce an invalid SF Symbol — it selects a category from a closed set, and Swift maps each category to a symbol verified to render.
- [x] **ICON-03**: Classification is device-local and never persisted on PantryItem or synced; when the on-device model is unavailable the keyword table + neutral fallback still render immediately, and icon resolution never blocks the pantry list from drawing.

### Overview Filtering (OVF)

<!-- Extends the existing Overview (OVR-01..06). Reuses expense queries + confirmed-transfer exclusion. -->

- [x] **OVF-01**: User can filter the Overview (net cash flow hero, spend donut, and totals) to a single account or a chosen subset of accounts; unfiltered (all accounts) remains the default.
- [x] **OVF-02**: The account filter is combinable with a custom date range, and all Overview figures recompute correctly for the account × date-range selection (reusing the existing confirmed-self-transfer exclusion).
- [ ] **OVF-03**: The active filter is clearly shown and can be cleared in one tap; every Overview figure respects the filter consistently (no stale/unfiltered value left behind).

---

## Out of Scope (explicit exclusions)

- **CloudKit / iCloud / Push / real background sync** — paid-only; remains the future paid-upgrade trigger. Schema stays CloudKit-ready but no cloud sync in v1.3.
- **Sync when the two phones are apart / not on the same network** — would require a cloud relay (third-party or paid); v1.3 sync is on-device P2P only.
- **Third-party sync backends (Firebase/Supabase/Appwrite)** — put household finance data on someone else's cloud; conflicts with the core privacy stance.
- **Raw SwiftData store-file copy as ongoing sync** — clobbers the receiver's edits; used only for one-time bootstrap/backup.
- **7-day expiry handling inside the app** — solved by external tooling (`scripts/auto-deploy.sh`), not app code.
- **Deepen finance** (bill reminders, recurring-expense detection, spending goals, exports/reports) — deferred to v1.4.
- **Smarter AI** (Overview insight, follow-up questions, multi-month trend narratives) — deferred to v1.4.
- **Barcode scanning / external food databases for the kitchen** — nice-to-have; manual entry only for v1.3.

## Future Requirements (deferred, not this milestone)

- Deepen finance: bill/subscription reminders, recurring-expense auto-detection, spending goals, CSV/PDF export. (v1.4)
- Smarter AI: AI Insight surfaced on Overview, follow-up questions, multi-month trend narratives. (v1.4)
- Kitchen: barcode scan + food database lookup, expiry-date tracking with reminders, recipe/meal planning.
- Sync: automatic sync-when-apart via a privacy-preserving relay (e.g. Tailscale-tunneled P2P), only if "sync outside the house" ever becomes a real need.

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| SYNC-01 | Phase 18 | Complete |
| SYNC-02 | Phase 18 | Complete |
| SYNC-03 | Phase 18 | Complete |
| SYNC-04 | Phase 19 | Complete |
| SYNC-05 | Phase 19 | Complete |
| KTCH-01 | Phase 20 | Complete |
| KTCH-02 | Phase 20 | Complete |
| KTCH-03 | Phase 20 | Complete |
| KTCH-04 | Phase 20 | Complete |
| ICON-01 | Phase 22 | Complete |
| ICON-02 | Phase 22 | Complete |
| ICON-03 | Phase 22 | Complete |
| OVF-01 | Phase 21 | Complete |
| OVF-02 | Phase 21 | Complete |
| OVF-03 | Phase 21 | Pending |
