# Roadmap: My Home

## Overview

My Home is a single-user (v1) iOS app for a two-person Indian household, built as a Swift learning vehicle on the Swift 6.2 / SwiftUI / SwiftData stack, iOS 17+. The journey starts by locking the one-way-door decisions (bundle/CloudKit/App-Group IDs, privacy manifest, CloudKit-ready schema discipline) and proving the SwiftData spine with manual expense entry — the irreducible fallback that de-risks everything downstream. From there it closes the manual-expense loop (categories, tags, budgets), ships the independent Notes feature, then the motivating Overview + Charts surface, then the Face ID gate that makes financial data feel trusted. Only after that proven, self-contained spine exists does it tackle the riskiest sub-system: Gmail OAuth in isolation, then the bank-email ingestion pipeline (parsers → coordinator → Review Inbox → background tasks). The load-bearing sequencing rule throughout: **manual entry before Gmail ingestion**. All schema is CloudKit-ready from day one so post-v1 sync is a configuration flip, not a rewrite.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation & Manual Expense Spine** - Lock one-way-door IDs, CloudKit-ready SwiftData schema, and manual expense CRUD end-to-end (completed 2026-05-29)
- [x] **Phase 2: Categories, Tags & Budgets** - Close the manual-expense loop with categories, single-tag, per-category budgets, and month view (completed 2026-05-30)
- [ ] **Phase 3: Notes & Checklists** - Independent note keeper with inline checklists, pin, search, and auto-save
- [ ] **Phase 4: Overview & Charts** - Motivating home surface: spend-vs-budget, top categories, pinned note, and Swift Charts
- [ ] **Phase 5: Face ID Gate & Settings** - Biometric app lock with passcode fallback and a Settings shell for managing the household
- [ ] **Phase 6: Gmail Sign-In & Client** - Prove Gmail OAuth + readonly fetch in isolation with secure Keychain token storage
- [ ] **Phase 7: Bank Parsers & Ingestion Pipeline** - Zero-touch expense ingestion: parsers, confidence triage, Review Inbox, dedup, and background sync

## Phase Details

### Phase 1: Foundation & Manual Expense Spine

**Goal**: A user can add, edit, and delete a manual expense end-to-end on a CloudKit-ready SwiftData spine, with all immutable lock-in decisions made on day one.
**Depends on**: Nothing (first phase)
**Requirements**: FND-01, FND-02, FND-03, FND-04, FND-05, FND-06, FND-07, EXP-01, EXP-02, EXP-03
**Success Criteria** (what must be TRUE):

  1. User can add a manual expense in ≤4 taps (open → amount keypad → category → save) and see it appear in a list
  2. User can edit and delete any expense they created
  3. Currency renders in en-IN format (₹1,00,000.00) and money is stored as Decimal; dates stored UTC
  4. Every @Model type passes a reflection-based test asserting all properties are optional/defaulted with no @Attribute(.unique), and the VersionedSchema migration plan loads a bundled v1 store successfully
  5. App targets iOS 17+ on Swift 6.2 / SwiftUI / SwiftData with PrivacyInfo.xcprivacy declaring required-reason APIs and NSPrivacyTracking false

**Plans**: 4 plans

Plans:

- [x] 01-01-PLAN.md — Xcode bootstrap, locked IDs (D-09), strict concurrency, PrivacyInfo manifest, Swift Testing target with failing stubs (FND-01/02/04/06)
- [x] 01-02-PLAN.md — Expense @Model + VersionedSchema v1 + MigrationPlan + ModelContainer factory + en-IN/UTC formatting (FND-03/05/06/07)
- [x] 01-03-PLAN.md — Expense List + Add (custom keypad) + Edit screens, manual CRUD end-to-end (EXP-01/02/03)
- [x] 01-04-PLAN.md — Seed store + migration-load test green; full suite verified (FND-05)

### Phase 2: Categories, Tags & Budgets

**Goal**: A user can categorize and tag expenses, set per-category monthly budgets, and watch budget progress — making the manual tracker usable end-to-end with no backend.
**Depends on**: Phase 1
**Requirements**: EXP-04, EXP-05, EXP-06, EXP-07, EXP-08, EXP-09
**Success Criteria** (what must be TRUE):

  1. App ships with the India-tuned predefined category list and the user can add, rename, and delete custom categories
  2. User can attach one tag to an expense (schema already supports multiple for future UI)
  3. User can set a monthly budget per category and see a ₹-remaining + % progress bar that shifts color at 80% and 100%
  4. User can view the current month's expenses grouped by category and tap through to the transaction list

**Plans**: 5 plans
**UI hint**: yes
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — SchemaV2 + Category @Model + additive Expense relationship + V1->V2 migration + idempotent 14-category seed + model test suite (EXP-04/05/06/07)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — BudgetCalculator + BudgetProgressData pure budget math (thresholds, aggregation, uncategorized bucket) — TDD (EXP-08/09)
- [x] 02-03-PLAN.md — Optional category picker in Add/Edit expense + reusable CategoryPickerView (EXP-06)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-04-PLAN.md — Budget viz/edit components: BudgetProgressView, BudgetCategoryCard, EditBudgetSheet, month-year helper (EXP-07/08)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-05-PLAN.md — Budgets surface: month pager + cards + uncategorized + tap-through + ManageCategories + TabView shell (EXP-05/08/09)

### Phase 3: Notes & Checklists

**Goal**: A user can capture block-style notes (interleaved text paragraphs + inline checklist rows), pin the important ones, and find anything by search — AND turn any note or checklist row into a scheduled reminder (all-day or timed, optionally recurring) with local notifications and a calendar view. Phase 3 is the household's note + reminder hub, fully decoupled from expenses.
**Depends on**: Phase 1
**Requirements**: NOT-01, NOT-02, NOT-03, NOT-04, NOT-05, NOT-06, NOT-07, NOT-08, NOT-09, NOT-10
**Success Criteria** (what must be TRUE):

  1. User can create a note with a required title and a block body of interleaved text paragraphs and inline checkbox rows; edits auto-save (debounced ~500ms) with no save button
  2. The notes list shows a Daily Routine section (daily-recurring notes) first, then manually-pinned notes, then the rest most-recent-first; user can pin/unpin and search title + body
  3. User can attach a reminder to a whole note or any checkbox row — all-day or timed, with optional advance lead-time — and set recurrence (none / daily / weekly-with-weekdays / monthly / yearly) with an end rule (never / on date / after N)
  4. Reminders fire local notifications (permission requested on first reminder) that deep-link into the note and offer Complete/Snooze actions
  5. A Calendar view inside the Notes tab shows per-day reminder counts; tapping a day opens that day's reminders with a completion progress

**Plans**: 6 plans
**UI hint**: yes

Plans:

**Wave 0** — failing-test scaffold (Nyquist gate)
- [x] 03-01-PLAN.md — Wave 0 test infra: all Note/scheduler/recurrence/calendar test stubs + NotificationCenterPort/SpyCenter seam + bundled MyHomeV2Seed.store (NOT-01..06)

**Wave 1** — data layer
- [x] 03-02-PLAN.md — SchemaV3 + Note/NoteBlock @Models + reminder value types + v2ToV3 migration + typealias/container flip (NOT-01/02)

**Wave 2** — notification core
- [x] 03-03-PLAN.md — NotificationScheduler (pure buildRequests) + NotificationCenterPort + recurrence/after-N/64-cap (TDD; SC-R1..R3)

**Wave 3** — pure UI helpers
- [x] 03-04-PLAN.md — NoteListOrganizer (Daily Routine→Pinned→Other) + NoteSearchFilter + CalendarAggregator (TDD; NOT-03/04/06, SC-R4/R5)

**Wave 4** — note-keeper UI
- [ ] 03-05-PLAN.md — Notes tab + sectioned searchable list + block editor + debounced auto-save + discard-on-empty-title (NOT-01..06; UAT checkpoint)

**Wave 5** — reminders hub + integration
- [ ] 03-06-PLAN.md — ReminderEditView + LazyVGrid Calendar + live notifications (permission/Complete/Snooze/deep-link/reschedule) (SC-R1..R5; UAT checkpoint)

### Phase 4: Overview & Charts

**Goal**: A user opens the app and immediately sees how the household is doing this month — spend vs. budget, top categories, the pinned note — plus spend charts that sell the app's value.
**Depends on**: Phase 2, Phase 3
**Requirements**: OVR-01, OVR-02, OVR-03, OVR-04, EXP-10, EXP-11
**Success Criteria** (what must be TRUE):

  1. Overview shows current-month total spend vs. total monthly budget as a single bar and the top 3 spend categories with absolute ₹ amounts
  2. Overview surfaces the most-recent pinned note (or latest checklist) as a card and exposes a quick-add expense + action
  3. User can view a spend-by-category chart for the current month (Swift Charts)
  4. User can view a spend-over-time chart across configurable date ranges (Swift Charts)

**Plans**: TBD
**UI hint**: yes

Plans:

- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Face ID Gate & Settings

**Goal**: A user can require Face ID to open the app and manage their household (categories, budgets, lock toggle) from a Settings shell — making the financial data feel trusted before any external data flows in.
**Depends on**: Phase 2, Phase 4
**Requirements**: SEC-01, SEC-02, SET-01, SET-02, SET-03
**Success Criteria** (what must be TRUE):

  1. User can toggle a Face ID lock on/off in Settings; when on, the app requires authentication to open
  2. Face ID falls back to device passcode via LAPolicy.deviceOwnerAuthentication, and every LAError case is handled explicitly without locking the user out
  3. User can manage categories (add, rename, delete) and per-category monthly budgets from Settings

**Plans**: TBD
**UI hint**: yes

Plans:

- [ ] 05-01: TBD
- [ ] 05-02: TBD

### Phase 6: Gmail Sign-In & Client

**Goal**: A user can sign in to Gmail with read-only scope, trigger a fetch, and see when the app last synced — proving the riskiest network/auth sub-system in isolation with a secure token in Keychain.
**Depends on**: Phase 5
**Requirements**: ING-01, ING-02, ING-03, ING-05, ING-16, SEC-03, SET-04, SET-05
**Success Criteria** (what must be TRUE):

  1. User can sign in to Gmail via ASWebAuthenticationSession + PKCE (gmail.readonly only) and the refresh token is stored in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  2. First OAuth grant performs an initial backfill bounded to newer_than:30d; the user can trigger "Sync now" on demand from Settings
  3. Settings shows an always-visible "Last synced at …" timestamp and lets the user sign out and reconnect Gmail
  4. When the refresh token expires, the app shows a clear "Reconnect Gmail" CTA

**Plans**: TBD
**UI hint**: yes

Plans:

- [ ] 06-01: TBD
- [ ] 06-02: TBD

### Phase 7: Bank Parsers & Ingestion Pipeline

**Goal**: A user's bank-email transactions flow in zero-touch — high-confidence parses auto-save, low-confidence ones land in a Review Inbox for one-tap fixes, duplicates are flagged, and background sync runs best-effort.
**Depends on**: Phase 6
**Requirements**: ING-04, ING-06, ING-07, ING-08, ING-09, ING-10, ING-11, ING-12, ING-13, ING-14, ING-15
**Success Criteria** (what must be TRUE):

  1. v1 ships with two bank parsers that fingerprint the whole template separately from value extraction, reject OTP/promotional/verification emails, and detect reversals/refunds as negative entries
  2. Parses with confidence ≥ 0.85 auto-save; below threshold route to a Review Inbox where the user can one-tap-accept, tap-to-edit, or swipe-to-discard
  3. Ingestion deduplicates against existing expenses (amount + merchant-substring + date ±1 day) and flags duplicates in the inbox rather than silently merging
  4. A merchant-normalization seed table cleans raw merchant strings (e.g. "AMAZON IN BLR" → "Amazon"), and every ingested expense stores raw email body, parserID, and parserVersion for replay/forensics
  5. BGAppRefreshTask is registered and runs ingestion opportunistically as a best-effort path (never the primary path; "Sync now" remains the reliable path)

**Plans**: TBD

Plans:

- [ ] 07-01: TBD
- [ ] 07-02: TBD
- [ ] 07-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Manual Expense Spine | 4/4 | Complete    | 2026-05-29 |
| 2. Categories, Tags & Budgets | 5/5 | Complete   | 2026-05-30 |
| 3. Notes & Checklists | 4/6 | In Progress|  |
| 4. Overview & Charts | 0/TBD | Not started | - |
| 5. Face ID Gate & Settings | 0/TBD | Not started | - |
| 6. Gmail Sign-In & Client | 0/TBD | Not started | - |
| 7. Bank Parsers & Ingestion Pipeline | 0/TBD | Not started | - |
