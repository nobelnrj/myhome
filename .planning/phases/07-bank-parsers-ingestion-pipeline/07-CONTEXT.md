# Phase 7: Bank Parsers & Ingestion Pipeline - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Turn the raw bank emails fetched by Phase 6's Gmail client into expenses — the zero-touch
ingestion pipeline. Per-bank parsers fingerprint email templates and extract values,
confidence triage auto-saves the certain ones and routes the rest to a Review Inbox,
duplicates are flagged, raw emails are kept for forensics, and a best-effort background
sync runs opportunistically.

**In scope (ING-04, ING-06–ING-15):**

1. **Parsers (ING-06/07/08/09)** — Two banks: **HDFC + ICICI**. Whole-template fingerprint
   matching separate from value extraction; sender+subject pre-filters reject OTP /
   promotional / verification emails; reversal/refund detection creates negative entries.
2. **Confidence triage (ING-12/13)** — ≥ 0.85 auto-saves; below threshold routes to a
   Review Inbox with one-tap-accept / tap-to-edit / swipe-to-discard.
3. **Dedup (ING-14)** — (amount + merchant-substring + date ±1 day) flags possible
   duplicates into the inbox; never silent-merges.
4. **Forensics (ING-10/11)** — Every ingested expense stores the **full raw email body**,
   `parserID`, and `parserVersion` for replay/drift forensics.
5. **Merchant normalization (ING-15)** — A hardcoded ~20–30 Indian-merchant seed table
   ("AMAZON IN BLR" → "Amazon") applied at parse time, with an optional category hint.
6. **Background sync (ING-04)** — `BGAppRefreshTask` registered, best-effort; "Sync now"
   (Phase 6) remains the reliable primary path.

**Carried over from Phase 6 UAT:**
- **UAT-6-05** — populate `GmailSyncController.connectedEmail` via Gmail `users.getProfile`
  (`emailAddress`) so Settings shows "Connected as: <email>". Deferred from Phase 6 because
  the Gmail API layer was stubbed there.

**Out of scope (deferred):**
- Account entities, account-management UI in Settings, and account-balance tracking
  (balance is explicitly Out of Scope in PROJECT.md — expense tracker, not a finance suite).
- More than two bank parsers; per-merchant *learned* category memory (v2).
- Inbox/budget push notifications (deferred to v2).
- User-editable merchant seed table (v1 is hardcoded).

</domain>

<decisions>
## Implementation Decisions

### Target Banks — ING-06 (discussed)
- **D7-01 (Banks):** v1 ships **HDFC + ICICI** parsers (confirms the roadmap default).
- **D7-02 (Alert types):** Target **credit-card spends, account/debit alerts, and UPI**
  transaction emails — but **let the real email corpus drive** which templates get written.
  Don't pre-build for formats that don't actually arrive.
- **D7-03 (Data-collection prerequisite):** Collect **50+ real anonymized emails per bank**
  BEFORE building/calibrating parsers (carried blocker from STATE.md). The 0.85 confidence
  threshold needs real-data calibration after the first week of use.

### Review Inbox — ING-12/13 (discussed)
- **D7-04 (Surface):** Review Inbox lives as a **count badge on the Expenses tab** opening a
  **"Needs Review" section at the top of the expense list** — no new tab, keeps everything
  expense-related in one place.
- **D7-05 (Row content):** Each review row shows the **parsed fields only** (amount,
  normalized merchant, suggested category, date, source label) — editable inline. No
  low-confidence-reason text, no raw-email snippet in the row (keep it clean).
- **D7-06 (Triage actions):** one-tap-accept, tap-to-edit, swipe-to-discard (per ING-13).
- **D7-07 (Discard = remembered):** Swipe-to-discard **records the email's message-ID as
  dismissed** so the next sync never re-surfaces it. Requires dismissed-message-ID tracking.

### Auto-save Feedback — ING-12 (discussed)
- **D7-08 (Source marker):** High-confidence auto-saved expenses appear in the list like any
  other, with a **subtle "auto" marker** (e.g. an envelope glyph) distinguishing them from
  manual entries. No notifications (deferred to v2), no interruption. Implies a `source`
  distinction on the expense (manual vs ingested — derivable from presence of `parserID`).
- **D7-09 (Auto category):** Auto-saved expenses get a **best-guess category from the
  merchant seed** (e.g. Zomato→Dining, HPCL→Fuel). This is a *static* seed hint — distinct
  from the v2 *learned* per-merchant memory. When the seed has no hint, fall back to
  Uncategorized.

### Forensics & Merchant Data — ING-10/11/15 (discussed)
- **D7-10 (Raw storage):** Store the **full raw email body** against each ingested expense
  (chosen over hash+500-chars). Local-only (App Group store, no cloud in v1), Face-ID gated.
  Maximum fidelity for replaying/improving parsers.
- **D7-11 (Parser metadata):** Store `parserID` and `parserVersion` on every ingested
  expense (ING-11).
- **D7-12 (Merchant seed):** A **Claude-curated, hardcoded ~20–30 Indian-merchant** seed
  table shipped in code (Amazon, Zomato, Swiggy, HPCL, Uber, etc.), mapping raw string →
  { normalized display name, optional category hint }. **Not user-editable in v1**; refined
  in code as misses are spotted.

### Duplicate Handling — ING-14 (discussed)
- **D7-13 (Dup detection):** Locked by ING-14 — match on (amount + merchant-substring +
  date ±1 day).
- **D7-14 (Dup UX):** A flagged duplicate **lands in the Review Inbox marked "Possible
  duplicate of <existing expense>", shown side-by-side.** User swipes-discard (it's a dup)
  or accepts (genuinely separate, e.g. two coffees the same day). Never silent-merge.

### Account / Source Label — schema-forward (discussed)
- **D7-15 (Source label):** Persist the **parsed card/account string** (e.g. "HDFC ••1234",
  "a/c XX5678") on each ingested expense and **display it on the expense row/detail.**
  No Account entity, no management UI, no balance tracking — schema stays multi-account-ready.
  Full account management + balance is deferred to a v2 phase (see Deferred).

### Schema — new in this phase
- **D7-16 (SchemaV4 migration):** Phase 7 needs a **SchemaV4** that additively extends the
  `Expense` `@Model` with the ingestion/forensics fields: raw email body, `parserID`,
  `parserVersion`, source/account label, and an ingestion-state distinction (auto-saved vs
  needs-review vs possible-duplicate). Plus dismissed-message-ID tracking. Must obey the
  CloudKit-ready rules (all optional/defaulted, no `@Attribute(.unique)`) and chain the
  existing `AppMigrationPlan` V3→V4. *(Exact model shape — new fields on Expense vs a
  separate ReviewItem/PendingExpense `@Model` — left to research/planner.)*

### Claude's Discretion (research / planner / UI-SPEC)
- **Confidence-scoring mechanics:** how the 0.85 score is computed (template-fingerprint
  match strength + field-extraction completeness) — researcher/planner.
- **Reversal/refund UX:** ING-09 locks "create negative-amount entry, not duplicate" — exact
  matching of a reversal to its original (or standalone negative) left to planner.
- **BGAppRefreshTask cadence:** iOS-scheduled, best-effort; must be **verified on a real
  device unplugged overnight** (simulator triggering is not representative — carried blocker).
- **Review Inbox / "auto" marker / source-label exact visual treatment** — UI-SPEC.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirement & roadmap sources
- `.planning/REQUIREMENTS.md` — ING-04, ING-06 through ING-15 (full text + acceptance);
  ING-05/16 (Phase 6, complete) for context.
- `.planning/ROADMAP.md` §"Phase 7: Bank Parsers & Ingestion Pipeline" — goal, 5 success
  criteria, the UAT-6-05 carry-over note.
- `.planning/PROJECT.md` — Core value (ingestion reliability is the make-or-break feature),
  ingestion architecture (v1), Out of Scope (account-balance tracking, SMS, extra parsers),
  security posture (Face ID, no telemetry), developer context (Reo new to Swift).
- `.planning/STATE.md` §Blockers/Concerns — Phase 7 entries: collect 50+ real emails per
  bank; BGAppRefreshTask must be device-verified overnight.

### Phase 6 (direct dependency)
- `.planning/phases/06-gmail-sign-in-client/06-CONTEXT.md` — OAuth, token lifecycle, sync
  metadata in UserDefaults, the URLSession/OAuth port seam Phase 7 reuses for fetch + parse.
- `.planning/phases/06-gmail-sign-in-client/06-UAT.md` §Gaps — UAT-6-05 (connected-email)
  detail.
- `.planning/phases/06-gmail-sign-in-client/06-SECURITY.md` — OAuth/token threat mitigations
  to keep intact when adding background fetch.

### Implementation references
- **Gmail API**: `users.messages.list` / `users.messages.get` (raw email retrieval with `q`
  filter), `users.getProfile` (emailAddress for UAT-6-05).
- **Apple BackgroundTasks**: `BGAppRefreshTask` registration + scheduling (Info.plist
  `BGTaskSchedulerPermittedIdentifiers`; on-device-only triggering).
- **SwiftData**: `VersionedSchema` + `SchemaMigrationPlan` (V3→V4 additive migration).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — owns sync state + "Sync now";
  Phase 7 extends it to run fetched emails through the parser pipeline. Also where
  UAT-6-05 `connectedEmail` (via `users.getProfile`) gets populated.
- `MyHomeApp/Gmail/GmailAuthPort.swift` + `MyHomeTests/Support/SpyGmailAuth.swift` —
  protocol-port seam (mirrors `NotificationCenterPort`). Reuse the same pattern for an
  email-fetch port so parsers are unit-testable without the network.
- `MyHomeApp/Persistence/Schema/SchemaV3.swift` + `MigrationPlan.swift` — `Expense`
  `@Model` and the chained migration plan; Phase 7 adds SchemaV4 here.
- App Group UserDefaults (Phase 1/6) — sync metadata + dismissed-message-IDs can live here.

### Established Patterns
- Pure-logic + protocol-seam TDD (NotificationScheduler `buildRequests`, BudgetCalculator)
  — parsers and confidence scoring should be pure, table-tested functions over fixture
  emails, with the network behind a port.
- CloudKit-ready `@Model` rules (all optional/defaulted, no `@Attribute(.unique)`,
  VersionedSchema migration) — SchemaV4 must comply.
- `@Observable` controller pattern (LockController, GmailSyncController) for sync/inbox state.

### Integration Points
- Expenses tab / expense list (Phase 1/2) — gains the "Needs Review" badge + section and the
  "auto" source marker; source label shown on rows/detail.
- `AppMigrationPlan` — chain V3→V4.
- BackgroundTasks registration in the app entry point / scene setup.

</code_context>

<specifics>
## Specific Ideas

- Real-data-first: parsers are written against a corpus of 50+ anonymized real HDFC/ICICI
  emails, not invented formats. Template fingerprint is matched separately from value
  extraction (ING-07) so a format drift fails the fingerprint loudly rather than silently
  mis-parsing.
- "Sync now" stays the trusted path; background fetch is a bonus that must never be relied on.
- Full raw email retention is an intentional debug-heavy choice for a private 2-user app —
  acceptable because storage is local-only and Face-ID gated.

</specifics>

<deferred>
## Deferred Ideas

- **Account management + balance tracking** — Accounts as first-class entities managed in
  Settings, with balances. Balance tracking is explicitly Out of Scope in PROJECT.md
  (expense tracker ≠ finance suite). Phase 7 only stores/shows a parsed source *label*.
  → its own future phase (gated on real need).
- **User-editable merchant seed** — surfacing the normalization table in Settings to
  add/fix mappings without a rebuild. → v2 (premature for 2-user app).
- **Per-merchant learned category memory** — auto-categorize based on past choices.
  → v2 (PROJECT.md deferred list).
- **Inbox / budget push notifications** — alert when new expenses arrive or need review.
  → v2 (notifications deferred).
- **More bank parsers (beyond HDFC + ICICI)** → v2.

None of these were acted on; all preserved for the roadmap backlog.

</deferred>

---

*Phase: 7-bank-parsers-ingestion-pipeline*
*Context gathered: 2026-06-02*
