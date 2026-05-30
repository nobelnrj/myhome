# Requirements: My Home

**Defined:** 2026-05-28
**Core Value:** Everything our household needs in one place, with the expense tracker so automated that I never have to think about logging a transaction.

## v1 Requirements

Requirements for initial release. Each maps to a roadmap phase. Manual expense entry comes before Gmail ingestion (load-bearing sequencing decision — see research/SUMMARY.md).

### Foundation

- [x] **FND-01**: App targets iOS 17+ and uses the Swift 6.2 / SwiftUI / SwiftData stack (no UIKit, no Core Data)
- [x] **FND-02**: Bundle ID, CloudKit container ID, and App Group ID are decided on day one and never changed (CloudKit-ready even though v1 runs local-only)
- [x] **FND-03**: Every `@Model` type follows the 8 CloudKit-readiness rules — UUID PK, all fields optional or defaulted, no `@Attribute(.unique)`, optional + inverse-declared relationships, no enums stored directly, dates in UTC, money as `Decimal`, no Codable-only blobs for queryable data
- [x] **FND-04**: `PrivacyInfo.xcprivacy` declares required-reason APIs (UserDefaults CA92.1, FileTimestamp C617.1) with `NSPrivacyTracking: false`
- [x] **FND-05**: `VersionedSchema` + `SchemaMigrationPlan` scaffolded from v1.0 even with only one schema version
- [x] **FND-06**: Test target uses Swift Testing with in-memory `ModelContainer(isStoredInMemoryOnly: true)` for fixtures; XCTest reserved for UI tests only
- [x] **FND-07**: All currency displayed with `Locale(identifier: "en_IN")` formatting (`₹1,00,000.00`, not `₹100,000.00`); all dates stored UTC, displayed in user locale

### Security

- [ ] **SEC-01**: User can require Face ID to open the app; toggle in Settings
- [ ] **SEC-02**: Face ID falls back to device passcode via `LAPolicy.deviceOwnerAuthentication`; every `LAError` case is handled explicitly (`.biometryNotAvailable`, `.biometryNotEnrolled`, `.biometryLockout`, `.userFallback`, `.userCancel`, `.appCancel`, `.systemCancel`)
- [ ] **SEC-03**: Gmail OAuth refresh token is stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (never `WhenUnlocked`, never `biometryCurrentSet`)

### Expense Tracker (manual)

- [x] **EXP-01**: User can add a manual expense in ≤4 taps (open → amount keypad → category → save)
- [x] **EXP-02**: User can edit any expense they created
- [x] **EXP-03**: User can delete any expense they created
- [x] **EXP-04**: App ships with an India-tuned predefined category list (Groceries, Dining, Fuel, Utilities, Rent, Auto/Cab, Shopping, Health/Pharmacy, Entertainment, Recharge/DTH, Maid/Help, UPI to Person, ATM, Misc)
- [x] **EXP-05**: User can add, rename, and delete custom categories
- [x] **EXP-06**: User can attach one tag to an expense; schema supports multiple tags per expense for future UI
- [x] **EXP-07**: User can set a monthly budget per category (calendar month default)
- [x] **EXP-08**: Per-category budget progress is shown as a ₹-remaining + % bar with color shift at 80% and 100%
- [ ] **EXP-09**: Month view shows expenses grouped by category with tap-through to the transaction list
- [ ] **EXP-10**: User can view a spend-by-category chart for the current month (Swift Charts)
- [ ] **EXP-11**: User can view a spend-over-time chart across configurable date ranges (Swift Charts)

### Gmail Ingestion

- [ ] **ING-01**: User can sign in to Gmail via `ASWebAuthenticationSession` + PKCE (no Google SDK), scope = `gmail.readonly` only
- [ ] **ING-02**: First OAuth grant performs an initial backfill bounded to `newer_than:30d`
- [ ] **ING-03**: User can trigger ingestion on demand via "Sync now" in Settings
- [ ] **ING-04**: `BGAppRefreshTask` is registered and runs ingestion opportunistically when iOS schedules it (best-effort, never the primary path)
- [ ] **ING-05**: An always-visible "Last synced at …" timestamp appears in Settings
- [ ] **ING-06**: v1 ships with two bank parsers (defaults: HDFC + ICICI; final pick confirmed at Phase 7 discuss)
- [ ] **ING-07**: Each parser performs whole-template fingerprint matching separate from value extraction (no single regex per bank)
- [ ] **ING-08**: Parsers reject OTP, promotional, and verification emails via sender + subject pre-filters
- [ ] **ING-09**: Parsers detect reversal / refund emails (`reversed`, `refund`, `credited back`, `reversal of`) and create negative-amount entries, not duplicates
- [ ] **ING-10**: Raw email body (or hash + first 500 chars) is stored against every ingested expense for parser replay
- [ ] **ING-11**: Every ingested expense records `parserID` and `parserVersion` for drift forensics
- [ ] **ING-12**: Parse confidence ≥ 0.85 auto-saves the expense; below threshold routes to the Review Inbox
- [ ] **ING-13**: User can review Review Inbox entries one-tap-accept, tap-to-edit, or swipe-to-discard
- [ ] **ING-14**: Ingestion deduplicates against existing expenses using (amount + merchant-substring + date ±1 day); duplicates flag in inbox, never silent merge
- [ ] **ING-15**: A merchant-normalization seed table (~20–30 common Indian merchants: "AMAZON IN BLR" → "Amazon", "ZOMATO ONL BANGAL" → "Zomato", etc.) is applied at parse time
- [ ] **ING-16**: When the Gmail refresh token expires (Testing-mode OAuth = every 7 days), the app shows a clear "Reconnect Gmail" CTA

### Notes

- [ ] **NOT-01**: User can create a note with title and free-form body
- [ ] **NOT-02**: User can embed inline checklist items (checkbox rows) anywhere in a note's body
- [ ] **NOT-03**: Notes list shows pinned notes first, then most-recent-first
- [ ] **NOT-04**: User can pin and unpin notes
- [ ] **NOT-05**: Notes auto-save while editing (debounced ~500ms); no explicit save button
- [ ] **NOT-06**: User can search across note title and body via `.searchable`

### Overview

- [ ] **OVR-01**: Overview screen shows current-month total spend vs. total monthly budget as a single bar
- [ ] **OVR-02**: Overview screen shows the top 3 spend categories this month with absolute ₹ amounts
- [ ] **OVR-03**: Overview screen surfaces the most-recent pinned note (or latest checklist) as a card
- [ ] **OVR-04**: Overview screen exposes a quick-add expense `+` action

### Settings

- [ ] **SET-01**: User can toggle Face ID lock on / off
- [ ] **SET-02**: User can manage categories (add, rename, delete)
- [ ] **SET-03**: User can manage per-category monthly budgets
- [ ] **SET-04**: User can sign out of Gmail and reconnect
- [ ] **SET-05**: Settings shows last-synced timestamp and a manual "Sync now" button

## v2 Requirements

Acknowledged but deferred. Tracked for future roadmaps. Most are gated either on the $99/yr Apple Developer Program upgrade or on real v1 usage data.

### Sync & Sharing (post $99/yr upgrade)

- **SYNC-01**: CloudKit private DB mirroring across the user's own devices
- **SYNC-02**: CloudKit shared zone with wife's Apple ID via `CKShare` (the v2 trigger by definition)
- **SYNC-03**: TestFlight distribution for wife's phone

### Expense Tracker — v1.x learnings

- **EXP-V2-01**: Per-merchant category memory — auto-suggest after 2+ user corrections (highest-ROI P2)
- **EXP-V2-02**: Additional bank parsers beyond HDFC + ICICI (SBI, Axis, Kotak, etc.) on demand
- **EXP-V2-03**: Today's spend tile on overview
- **EXP-V2-04**: Vs-prior-month comparison delta
- **EXP-V2-05**: Recurring / subscription expense detection
- **EXP-V2-06**: Credit-card billing-cycle-aware view (alongside calendar-month)
- **EXP-V2-07**: Receipt photo OCR

### Notes — v1.x learnings

- **NOT-V2-01**: Share Sheet receive into a new note
- **NOT-V2-02**: Spotlight indexing for notes and transactions (single shared service)

### Notifications

- **NTF-V2-01**: Opt-in notification when a category budget crosses 80% or 100%
- **NTF-V2-02**: Opt-in notification when items pile up in the Review Inbox

### Apple-ecosystem surfaces (post-$99-upgrade)

- **WGT-V2-01**: Home Screen widget — current-month spend-vs-budget glance
- **WGT-V2-02**: Lock Screen widget — pinned-note glance
- **INT-V2-01**: App Intents / Siri shortcut — "Hey Siri, add ₹500 cash expense"
- **WCH-V2-01**: watchOS app — read-only mirror of overview surface; complications

### Polish

- **POL-V2-01**: Haptics pass on save, delete, budget threshold cross

## Out of Scope

Explicitly excluded. Documented to prevent scope creep. Anti-features from research/FEATURES.md live here with reasoning.

| Feature | Reason |
|---------|--------|
| Android / cross-platform | Both users on iPhone; cross-platform doubles work for zero benefit |
| SMS reading on iOS | iOS does not expose SMS to third-party apps; email-based ingestion replaces it |
| Open-Banking / Plaid / TrueLayer | Cost, complexity, weaker India coverage versus free Gmail-based ingestion |
| Multi-currency display / FX conversion | Schema accommodates it; UI does not. Adds complexity for no current need |
| Web / macOS clients | iOS-only is a deliberate constraint to keep scope small |
| Multi-household / sharing with people other than wife | App is built for one specific household forever |
| Investments, net worth, account-balance tracking | This is an expense tracker, not personal-finance suite |
| Split transactions | 2-user household, both edit everything — split modeling adds no value |
| Reconciliation workflow (mark-as-cleared) | Designed for non-bookkeepers; no value-add for daily use |
| Rules engine for ingestion | Per-merchant category memory (EXP-V2-01) is the simpler answer |
| Envelope / zero-based budgeting modes | Single budget model serves the household; complexity not justified |
| Onboarding wizard | Two users will set up their own thing; wizard is friction not value |
| Per-transaction push notifications | The bank's own app already does this — duplication is noise |
| Weekly / monthly PDF reports | Charts cover the need; PDF is enterprise-app theater |
| Savings goals | Out of charter (expense tracker, not personal-finance suite) |
| Multi-user spend attribution | Both-edit-everything means attribution is friction not insight |
| Crypto / stocks | Out of charter |
| Voice-memo expense entry | App Intents covers the voice path in v2 |
| Gamification / streaks | Inappropriate for a household-finance app |
| In-app ads / paywalls / Pro tier | Not a product, built for one household |
| Telemetry / analytics / crash reporting | Privacy + zero third-party dependencies in v1 |
| Notes: rich text / markdown | Plain text + checklists covers the household need; rich text adds editing complexity |
| Notes: folders | Pinning + search covers organization for two users |
| Notes: separate tag system | Pin + search is enough; tags duplicate that surface |
| Notes: image / audio attachments | Storage + CloudKit costs; out of v1 scope |
| Notes: real-time collaboration | Eventual-consistency CloudKit is sufficient; real-time is not the use case |
| Notes: drawing canvas | Use Apple Notes if you need that |
| Notes: per-note encryption | App-level Face ID gate covers the trust need |
| Notes: attached reminders | Use Apple Reminders if you need that |

## Traceability

Each v1 requirement maps to exactly one phase. Filled by the roadmapper when ROADMAP.md was created.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | Phase 1 | Complete |
| FND-02 | Phase 1 | Complete |
| FND-03 | Phase 1 | Complete |
| FND-04 | Phase 1 | Complete |
| FND-05 | Phase 1 | Complete |
| FND-06 | Phase 1 | Complete |
| FND-07 | Phase 1 | Complete |
| SEC-01 | Phase 5 | Pending |
| SEC-02 | Phase 5 | Pending |
| SEC-03 | Phase 6 | Pending |
| EXP-01 | Phase 1 | Complete |
| EXP-02 | Phase 1 | Complete |
| EXP-03 | Phase 1 | Complete |
| EXP-04 | Phase 2 | Complete |
| EXP-05 | Phase 2 | Complete |
| EXP-06 | Phase 2 | Complete |
| EXP-07 | Phase 2 | Complete |
| EXP-08 | Phase 2 | Complete |
| EXP-09 | Phase 2 | Pending |
| EXP-10 | Phase 4 | Pending |
| EXP-11 | Phase 4 | Pending |
| ING-01 | Phase 6 | Pending |
| ING-02 | Phase 6 | Pending |
| ING-03 | Phase 6 | Pending |
| ING-04 | Phase 7 | Pending |
| ING-05 | Phase 6 | Pending |
| ING-06 | Phase 7 | Pending |
| ING-07 | Phase 7 | Pending |
| ING-08 | Phase 7 | Pending |
| ING-09 | Phase 7 | Pending |
| ING-10 | Phase 7 | Pending |
| ING-11 | Phase 7 | Pending |
| ING-12 | Phase 7 | Pending |
| ING-13 | Phase 7 | Pending |
| ING-14 | Phase 7 | Pending |
| ING-15 | Phase 7 | Pending |
| ING-16 | Phase 6 | Pending |
| NOT-01 | Phase 3 | Pending |
| NOT-02 | Phase 3 | Pending |
| NOT-03 | Phase 3 | Pending |
| NOT-04 | Phase 3 | Pending |
| NOT-05 | Phase 3 | Pending |
| NOT-06 | Phase 3 | Pending |
| OVR-01 | Phase 4 | Pending |
| OVR-02 | Phase 4 | Pending |
| OVR-03 | Phase 4 | Pending |
| OVR-04 | Phase 4 | Pending |
| SET-01 | Phase 5 | Pending |
| SET-02 | Phase 5 | Pending |
| SET-03 | Phase 5 | Pending |
| SET-04 | Phase 6 | Pending |
| SET-05 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 52 total
- Mapped to phases: 52
- Unmapped: 0 ✓

**Per-phase distribution:**
- Phase 1 (Foundation & Manual Expense Spine): 10 — FND-01..07, EXP-01, EXP-02, EXP-03
- Phase 2 (Categories, Tags & Budgets): 6 — EXP-04..09
- Phase 3 (Notes & Checklists): 6 — NOT-01..06
- Phase 4 (Overview & Charts): 6 — OVR-01..04, EXP-10, EXP-11
- Phase 5 (Face ID Gate & Settings): 5 — SEC-01, SEC-02, SET-01, SET-02, SET-03
- Phase 6 (Gmail Sign-In & Client): 8 — ING-01, ING-02, ING-03, ING-05, ING-16, SEC-03, SET-04, SET-05
- Phase 7 (Bank Parsers & Ingestion Pipeline): 11 — ING-04, ING-06..15

---
*Requirements defined: 2026-05-28*
*Last updated: 2026-05-29 — traceability mapped to roadmap (52/52)*
