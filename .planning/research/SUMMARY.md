# Project Research Summary

**Project:** My Home — personal household-ops iOS app (expense tracker + note keeper)
**Domain:** iOS-only native app for a two-person Indian household; SwiftUI + SwiftData; Gmail-based bank email ingestion; CloudKit-ready; Face ID-gated
**Researched:** 2026-05-28
**Confidence:** HIGH overall — HIGH on Apple stack/architecture/pitfalls, MEDIUM on Gmail SDK choice and Indian-bank email parser specifics

> **Source caveat (preserve through roadmap):** Three of the four researchers (STACK / ARCHITECTURE / PITFALLS / FEATURES) had WebSearch denied. Apple-platform recommendations rely on documented APIs through iOS 17/18/26 era and are HIGH confidence. Items flagged **VERIFY** in this summary or in the source docs must be re-checked against current Apple / Google documentation at implementation time — they were correct as of training data but are exactly the surface area where Apple iterates fastest.

---

## Executive Summary

Build a native iOS 17+ app in **Swift 6.2 / SwiftUI / SwiftData** with a CloudKit-ready model graph from day one, Gmail-based bank email ingestion as the core differentiator, and a deliberately small modular footprint (one app target + two SPM packages: `BankParsers`, `GmailClient`). Persistence uses SwiftData with `@Query` directly in views and small `actor` "stores" for multi-model writes — **no repository pattern, no MVVM-per-screen, no Clean Architecture cake**. Each domain concept is its own `@Model` type with shared concerns expressed as Swift protocols — never a `HouseholdItem` superclass with a payload blob. Bank parsers live behind a `ParserRegistry` strategy interface so each new bank is one file + one registry line. CloudKit sync is wired in by config, not code, once the $99/yr Apple Developer Program is justified — the schema discipline (UUID PKs, all fields optional+defaulted, no `.unique`, inverse-required relationships) makes the migration a flag flip rather than a rewrite.

The single load-bearing decision is to **build manual entry FIRST and Gmail ingestion SECOND**. Manual entry validates the schema, the SwiftUI patterns, and the formatting/Face ID/budget loop end-to-end without staking the project on the riskiest sub-system. It also guarantees the irreducible fallback exists when (not if) bank email templates drift. Gmail ingestion is then layered onto a proven spine: `GmailClient` package, then `BankParsers` package, then `IngestionCoordinator`, then `BackgroundTasks` — in that exact order, with foreground "Run ingestion now" buttons before any background scheduling. The Review Inbox is the linchpin: confidence-gated parses route here for one-tap fixes, which protects user trust on day one and produces the training data for the per-merchant category memory in v1.x.

The biggest risks are not technical: **(a)** locking in the bundle ID + iCloud container ID + App Group store URL on day zero (renaming any of them later orphans every record on device and in CloudKit, with no in-place rename path); **(b)** designing the UX around the fact that `BGAppRefreshTask` is opportunistic and free Apple Developer accounts have no APNs — on-launch fetch must be the primary path, background is best-effort; **(c)** building per-(bank, template) parsers with **fingerprint + confidence gates**, never a single regex per bank, so template drift fails loudly into the Review Inbox instead of silently saving garbage; and **(d)** declaring the Privacy Manifest and Swift 6 strict concurrency from Phase 0, because both are far cheaper to wire in early than to retrofit at TestFlight time or after a concurrency-induced corruption bug.

---

## Key Findings

### Recommended Stack

The Apple-blessed greenfield stack of mid-2026, with one third-party path for Gmail OAuth and zero recurring cost. See `/Users/reo/My Projects/my-home/.planning/research/STACK.md` for the full deliberation.

**Core technologies (HIGH confidence):**

- **Swift 6.2 / Xcode 26 / iOS 17.0 minimum** — Approachable Concurrency mode is the friendliest path for a Swift-newcomer; iOS 17 floor unlocks `@Observable`, SwiftData, modern Charts. Do **not** target iOS 16; you lose SwiftData entirely.
- **SwiftUI throughout** — no UIKit needed; drop to `UIViewRepresentable` only if a missing control forces it (none expected here).
- **SwiftData with `ModelConfiguration(cloudKitDatabase: .none)` for v1**, flipping to `.automatic` (or `.private("iCloud.com.<domain>.myhome")`) post-paid-account. Treat every `@Model` field as if it had to become a `CKRecord` field — this is a *day-zero schema discipline*, not a later refactor.
- **Swift Testing for unit + integration tests; XCTest only for `XCUIApplication` UI tests** — Swift Testing ships in the toolchain (no SPM dep); `@Test` / `#expect`, parameterized, parallel-by-default, async-native.
- **Swift Charts** — first-party, no third-party charting library is competitive on iOS 17+.
- **LocalAuthentication + Keychain Services** — only correct choice on Apple platforms.
- **BackgroundTasks (`BGAppRefreshTask`)** — for inbox polling; design around best-effort behavior.
- **Observation framework (`@Observable`)** — replaces `ObservableObject`/`@Published`/`@StateObject` entirely; do not mix old and new in the same module.
- **Swift Package Manager only** — CocoaPods is sunsetting; Carthage is niche.

**Gmail OAuth stack (MEDIUM confidence — open choice; see Conflicts section):**

- **Option A (recommended default): GoogleSignIn-iOS 9.x + GTMAppAuth 5.x + GTMSessionFetcher 5.x + `GoogleAPIClientForREST_Gmail` 5.x** — official Google libraries, all SPM-installable, Google handles the OAuth state machine + token refresh.
- **Option B (zero-third-party-deps escape hatch): `ASWebAuthenticationSession` + raw `URLSession` calls + your own PKCE + Keychain helper** — ~150 lines, no Google SDK weight, no future Google-SDK-reshuffle risk. PITFALLS.md recommends this stance more strongly because it forces explicit PKCE and avoids embedded-webview pitfalls automatically.

**Supporting libraries:**

- **swift-snapshot-testing (pointfreeco)** — optional; add once a view stabilizes (charts, monthly summary). Not needed day one.
- **Foundation `Regex` literals / `Regex { … }` builder** — for per-bank parsers. Never `NSRegularExpression` for new code.

**Explicitly deferred in v1 (do not install):**

- SwiftLint, swift-format, fastlane, CI of any kind, Firebase / Crashlytics / Sentry / any analytics. Defer to v1.1 if and only if friction shows up.

**What NOT to use, ever (HIGH confidence):**

UIKit-driven UI, Core Data as primary persistence, Realm, Firebase, Supabase, Plaid/TrueLayer, CocoaPods, Carthage, RxSwift / Combine for new code, `UserDefaults` for OAuth tokens, `NSRegularExpression` for parsers, `WKWebView` for OAuth (Google rejects it), `Timer`/silent-`URLSession` polling tricks for background, telemetry of any kind.

---

### Expected Features

The real competition is **Apple Notes + a Google Sheet**, not Walnut or CRED. Anything this app does worse than that combo will get it deleted within a month. The two things that combo cannot do — and therefore the only two differentiators worth fighting for — are **(a) zero-touch ingestion of bank transactions** and **(b) "₹X of ₹Y this month" budgeting without manual upkeep**. See `/Users/reo/My Projects/my-home/.planning/research/FEATURES.md` for the full landscape.

**Must have (P1 — table stakes for daily-use bar in v1):**

- Manual expense entry (4-tap-max: open → amount keypad → category → save) — works before Gmail, becomes fallback after
- Predefined categories tuned to India (Groceries, Dining, Fuel, Utilities, Rent, Auto/Cab, Shopping, Health/Pharmacy, Entertainment, Recharge/DTH, Maid/Help, UPI to Person, ATM, Misc) + custom add/edit/rename
- Per-category monthly budgets (calendar month default) with progress bar (₹ remaining + % + color shift at 80%/100%)
- Month view of expenses grouped by category; tap-through to transaction list
- Notes: title + free-form body + inline checklist items (one model, not two); list with pin + search
- Home overview: spend-vs-budget bar, top 3 categories, pinned-note card
- Face ID app lock (toggle in settings; passcode fallback non-negotiable — see Pitfall 11)
- INR Indian-locale formatting everywhere (`₹1,00,000.00` not `₹100,000.00`) — instant trust kill if wrong
- Dark mode + Dynamic Type from day one (free with SwiftUI semantic colors if you don't fight it)
- Gmail OAuth + at least 2 bank parsers (start with whichever 2 cover Reo's primary cards — likely HDFC + ICICI)
- Review Inbox for low-confidence / unknown parses — required because parsers WILL be wrong on day one
- Duplicate detection on ingestion (dedup key: amount + merchant-substring + date within ±1 day; flag in inbox, don't auto-merge)
- Merchant normalization seed table (~20–30 common Indian merchants: "AMAZON IN BLR" → "Amazon", "ZOMATO ONL BANGAL" → "Zomato", etc.)
- Spend-by-category + spend-over-time charts (Swift Charts)
- Settings: Face ID toggle, manage categories/budgets, Gmail sign-out, **always-visible "last synced" timestamp** (debugging lifeline)

**Should have (P2 — v1.x differentiators, add after daily use proves which matter):**

- Additional bank parsers (SBI, Axis, Kotak, + whichever cards wife uses)
- **Per-merchant category memory** (auto-suggest after 2+ corrections) — highest-ROI P2; compounds Review Inbox value into a daily friction reduction; pure lookup table, no ML
- Spotlight indexing for both transactions and notes (one shared `SpotlightIndexer` service)
- Today's spend tile on overview
- Vs-prior-month comparison delta
- Share Sheet receive into notes
- Notifications: budget threshold + Review-Inbox pending (opt-in; never per-transaction — Gmail itself already does that)
- Haptics polish pass

**Defer (P3 / v2+ — gated on the $99/yr decision or post-product-market-fit):**

- CloudKit sharing with wife's Apple ID (the v2 trigger event by definition)
- Home Screen + Lock Screen widgets (quick-add expense, pinned-note glance) — high-leverage but explicitly post-v1 per PROJECT.md
- App Intents / Siri shortcut ("Hey Siri, add ₹500 cash expense") — pairs with widgets
- watchOS app
- "Convert checked items to expense" bridge action — uniquely-household feature; needs both sub-systems mature
- Credit-card billing-cycle-aware view
- Recurring expense detection, receipt OCR — only if data justifies it

**Explicit anti-features (FEATURES.md re-litigates if a future phase suggests these — refuse):**

Split transactions, recurring-subscription tracker, multiple accounts UI with balances, reconciliation workflow, rules engine, envelope/zero-based budgeting modes, onboarding wizard, per-transaction notifications, weekly/monthly PDF reports, savings goals, multi-user spend attribution, crypto/stocks, currency-conversion UI, receipt-photo attachment, voice-memo entry, gamification/streaks, in-app ads/paywalls/Pro tier, telemetry. Notes: rich text/markdown, folders, separate-from-expense tags, image/audio attachments, versioning, real-time collaboration, drawing, templates, per-note encryption, attached reminders.

---

### Architecture Approach

Single app target + exactly two SPM packages. SwiftUI views consume SwiftData via `@Query` directly; small `actor` stores wrap `ModelContext` only when a write spans multiple models. Each domain concept gets its own `@Model` type — shared concerns are protocols, never inheritance. Bank parsers are a strategy-pattern plugin behind a `ParserRegistry`. The ingestion pipeline is one `actor` (`IngestionCoordinator`) orchestrating typed steps: fetch → parse → triage by confidence → persist → advance "last processed" marker. Widget (when it arrives) is a snapshot-JSON consumer, not a live SwiftData reader. See `/Users/reo/My Projects/my-home/.planning/research/ARCHITECTURE.md` for the full diagram and patterns.

**Major components:**

1. **App target (`MyHomeApp`)** — `@main App`, `ModelContainer` injection, BGTask registration, root `TabView` host with Face ID gate
2. **Presentation layer (per-feature folders, vertical slices)** — `Features/Overview`, `Features/Expenses`, `Features/Notes`, `Features/Inbox`, `Features/Settings`; SwiftUI views with `@Query` + `@State` + `@Environment(\.modelContext)`; `@Observable` view models only when a screen has 3+ async sources of truth or duplicates across two views
3. **Persistence layer (`Persistence/`)** — `ModelContainer+App.swift` factory; `Models/` folder of `@Model` types; `Stores/` folder of small `actor` wrappers (`ExpenseStore`, `NoteStore`) for multi-step writes
4. **`BankParsers` SPM package (pure Swift, zero Apple-framework deps)** — `BankParser` protocol, `ParserRegistry`, `ExpenseCandidate` DTO, per-bank concrete parsers (`HDFCParser`, `ICICIParser`, …); golden tests against real anonymized email fixtures
5. **`GmailClient` SPM package (network edge)** — `URLSession` + OAuth wrapper; `URLProtocol`-stub tests
6. **`IngestionCoordinator` (in app target)** — single `actor` owning the pipeline; BGTask handler is 5 lines that call `coordinator.runOnce()`
7. **Security helpers** — `FaceIDGate` (LocalAuthentication wrapper), `KeychainStore` (~30-line helper for OAuth refresh token)
8. **Widget Extension (post-v1)** — snapshot-JSON consumer reading from shared App Group container
9. **Watch App (post-v1)** — mirrors widget surface initially; read-only from shared store

**The 8 CloudKit-readiness model rules — apply to EVERY `@Model` from Phase 1 (preserve verbatim through roadmap):**

1. **Every model has a `id: UUID` you generate** — not just SwiftData's hidden persistent ID. CloudKit identifies records by name; your own UUID enables deterministic mapping.
2. **All non-relationship properties are optional or have defaults.** CloudKit treats every field as optional. A non-optional, no-default field refuses to migrate.
3. **No `@Attribute(.unique)` on anything you plan to sync.** CloudKit does not support uniqueness; SwiftData rejects unique attrs when CloudKit is enabled. Enforce uniqueness in code via lookup-then-insert. **VERIFY** at implementation time — this is one of the most common breakages.
4. **All relationships are optional and have inverses declared.** CloudKit requires bidirectional modeling; SwiftData's `@Relationship(inverse: \...)` does this. To-many relationships default to empty arrays; never make a relationship `let`.
5. **No `Codable`-only blob properties for things you might query later.** First-class fields only. Blobs (e.g. raw email HTML) only for genuinely opaque payloads, with `@Attribute(.externalStorage)` if > a few KB.
6. **No enums stored directly; store the raw value.** Save `categoryKind: String` (or `Int`); reconstruct in Swift. CloudKit round-trips primitives cleanly; custom enum coding is fragile under sync.
7. **Dates in UTC.** Never store local-time dates. Display layer formats with the user's locale.
8. **Money as `Decimal`, never `Double`.** Currency stored alongside as `String` (`"INR"`).

**Patterns to use (HIGH confidence):**

- `@Query` in views + actor stores for multi-model writes — **NOT** a repository pattern over SwiftData
- `@Observable` view models only when justified — default to stateful views with `@State` + `@Query`
- Strategy-pattern bank parsers behind `ParserRegistry`
- `IngestionCoordinator` as a single `actor` with typed steps
- Per-feature `@Model` types with shared concern protocols (`Timestamped`, `Pinnable`) — **NOT** `HouseholdItem` superclass with `kind` enum + payload blob
- App Group container URL from day one — even before any extension exists (zero cost, huge payoff)
- Widget = snapshot-JSON consumer (carve out the `SnapshotPublisher.republish()` no-op call site inside `ExpenseStore.save()` in Phase 1; implement file-write in the widget phase)

**Anti-patterns to refuse (verbatim — ARCHITECTURE.md lists 10):**

Over-modularization on day one, repository pattern over SwiftData, coordinator pattern for navigation (use `NavigationStack` + typed routes), DI container framework (Swinject/Factory), Clean Architecture five-layer cake, Combine where `async/await` suffices, `HouseholdItem` superclass, premature parser abstractions (write 2 parsers concrete before extracting), hand-rolled OAuth/token storage, mocking `ModelContext` (use in-memory `ModelContainer` instead).

---

### Critical Pitfalls

PITFALLS.md catalogs 20 pitfalls with severity, prevention phase, and recovery cost. The five most-likely-to-bite (verbatim from PITFALLS.md "Top 5"):

1. **SwiftData + CloudKit forces "everything optional, everything defaulted, no uniqueness, no `.deny` deletes"** — design schema this way from Phase 1 even though v1 is local-only. Retrofitting triggers destructive migration. Mitigation: the 8 model rules above; add a reflection-based test asserting every `@Model` property is optional/defaulted.

2. **Bundle ID + iCloud container ID + App Group ID are forever** — changing any of them orphans every record. Pick `com.<your-domain>.myhome` and `iCloud.com.<your-domain>.myhome` on day zero. NOT `.dev`, `.test`, `.local` suffixes. The CloudKit container won't actually be provisioned until paid, but the *naming must be locked*.

3. **`BGAppRefreshTask` will not run reliably enough to be the only path for new transactions** — iOS throttles aggressively; free-provisioned apps have effectively no usage signal at first. Mitigation: **on-launch fetch is the primary path; background is best-effort bonus**. Always expose a manual "Sync now" button and an always-visible "last synced" timestamp.

4. **Free Apple Developer account: no CloudKit container, no APNs push, no Sign in with Apple, no Associated Domains, App Groups work unreliably (and the App Group ID needs a Team prefix that changes when going paid)** — defer every paid-only capability to a clearly-labeled post-v1 phase. 7-day rebuild ritual is the *least* problem; capability orphaning is the real one. Budget one full afternoon for the paid-account migration when it happens.

5. **Gmail OAuth: no `client_secret` in the binary, use `ASWebAuthenticationSession` + PKCE, scope = `gmail.readonly` only, `gmail.readonly` is "restricted" so Google may show "unverified app" forever on a personal app (fine for two users), refresh tokens in Testing-mode OAuth clients expire every 7 days** — design the "reconnect Gmail" CTA from day one. Store refresh token with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (NOT `WhenUnlocked` — background tasks need it). NEVER `kSecAccessControlBiometryCurrentSet` on the Gmail token (re-enrolling Face ID would delete it).

**The next five most-impactful** (PITFALLS.md 6–10, condensed):

6. SwiftData migrations done badly silently wipe stores — scaffold `VersionedSchema` + `SchemaMigrationPlan` from v1.0 even with one version; bundle a v1 store file as a test resource and assert migration succeeds.
7. Indian bank email template drift — never one regex per bank; build **per-(bank, template) parsers with whole-template fingerprint + confidence score**; hard-exclude OTP / promotional emails; store raw email body for parser replay when templates change; auto-save only above confidence threshold, else Review Inbox.
8. SwiftUI state model confusion — all-in on `@Observable`, never mix with `ObservableObject`/`@StateObject`/`@Published`. `NavigationStack` paths are `Codable enum`s of UUIDs, never `@Model` objects.
9. Face ID + Keychain edge cases lock users out — use `LAPolicy.deviceOwnerAuthentication` (passcode fallback), handle every `LAError` case explicitly, two-tier secret storage (Gmail token = `AfterFirstUnlockThisDeviceOnly` no-biometric; app lock = UI gate only, not encryption).
10. Privacy Manifest (`PrivacyInfo.xcprivacy`) required-reason APIs (UserDefaults, FileTimestamp, SystemBootTime, DiskSpace) must be declared from Phase 0 — TestFlight rejects without it.

**Additional pitfalls flagged in PITFALLS.md** (review during relevant phases): SwiftData mirroring eventual-consistency UX (#2), `#Predicate` runtime crashes on non-stored properties (#3), Watch/Widget App Group sharing (#13), CloudKit `CKShare` mechanics across Apple IDs requires parent-reference in Phase 1 schema (#14), Swift Charts reactive-data stutter + accessibility (#15), TDD test-container hygiene (#16), Decimal vs Double / en-IN locale (#17), Swift 6 strict concurrency landmines (#18), NavigationStack/sheet bugs (#19), sim-vs-device divergence (#20).

---

## Implications for Roadmap

Research strongly suggests the following phase shape and ordering. The Architecture build-order and Pitfalls phase-mapping converge on this sequence — they do not conflict. Manual entry first, ingestion second is the single most important sequencing recommendation.

### Phase 0: Project Bootstrap & Foundational Lock-Ins

**Rationale:** Decisions made here are one-way doors. Skipping any of them costs days-to-weeks later. Pitfalls 5, 6, 10, 12, 18 all map here.

**Locks in (immutable for life of app):**

- Bundle ID: `com.<your-domain>.myhome` — pick a domain you actually own or commit to forever
- CloudKit container ID: `iCloud.com.<your-domain>.myhome` — add entitlement now even though container won't provision on free account
- App Group ID: `group.com.<your-domain>.myhome` — entitlement added; SwiftData store URL points at it from day one (Pitfall 13)
- Privacy Manifest (`PrivacyInfo.xcprivacy`) — declare `UserDefaults` (CA92.1), `FileTimestamp` (C617.1 for "last synced" display), `NSPrivacyTracking: false`, `NSPrivacyCollectedDataTypes: []` (Pitfall 12)
- Swift 6 strict concurrency enabled at "complete" level (Approachable Concurrency mode on for learner-friendliness) (Pitfall 18)
- Convention doc in README: `@Observable` only, never `ObservableObject`/`@StateObject`/`@Published`; SPM only; en-IN locale always; `Decimal` always for money; no `@Attribute(.unique)` ever
- Test scaffolding: helper for `ModelConfiguration(isStoredInMemoryOnly: true)`; Swift Testing for unit, XCTest reserved for UI (Pitfall 16)
- SwiftLint / fastlane / CI explicitly deferred to v1.1
- Document deferred paid-account capabilities (no Push, no CloudKit container provisioning, no SIWA, no Associated Domains) and the 7-day Xcode rebuild ritual (Pitfall 5)

**Avoids:** Pitfalls 5, 6, 10, 12, 18 by construction.

### Phase 1: SwiftData Spine + Manual Expense Entry ("Hello, SwiftData")

**Rationale:** ARCHITECTURE.md "Build Order" Phase 1 explicitly says this is the spine; until it works, nothing else can be tested visually. Manual entry is also the irreducible fallback that becomes the safety net when Gmail ingestion drifts. Phase 1 is also where every CloudKit-readiness rule is applied to every model.

**Delivers:**

- `Expense`, `Tag`, `Category`, `Account` `@Model` types — each obeys all 8 CloudKit-readiness rules verbatim
- `ModelContainer+App.swift` with App Group URL (`cloudKitDatabase: .none` for v1)
- `VersionedSchema` + `SchemaMigrationPlan` scaffolding from v1.0 (even with only one version) (Pitfall 7)
- `ExpensesListView` with `@Query` results
- `ExpenseEditView` for manual add/edit (Decimal everywhere; en-IN currency formatting)
- `PreviewSampleData.swift` with in-memory `ModelContainer` and fixtures
- Reflection-based test asserting every `@Model` property is optional/defaulted (Pitfall 1)
- Integration test: load bundled v1 store, run migration plan, assert success (Pitfall 7)

**Implements:** Architecture components 1, 2, 3 (App target, Presentation, Persistence). All 8 model rules. Parent-reference relationship pattern for future CloudKit sharing (Pitfall 14) — every shareable child has an optional `Household?` reference even though `Household` is a placeholder in v1.

**Avoids:** Pitfalls 1, 3, 7, 13, 14, 17 by construction.

### Phase 2: Categories, Tags, Budget Visualization

**Rationale:** Closes the manual-expense loop. App is usable end-to-end without any backend.

**Delivers:** Category-tag-picker UI; `BudgetProgressView`; pure-Swift `BudgetCalculator` (testable without SwiftData); India-tuned default category seed list; ₹X-of-₹Y bar with color shift at 80%/100%.

**Avoids:** Premature parser abstractions (Architecture Anti-Pattern 8) by deferring all parser work.

### Phase 3: Notes + Checklists

**Rationale:** Independent of expenses; ships the second core feature without coupling. Cheap win that proves "schema additivity" — adding `Note` and `ChecklistItem` did not touch any `Expense` code.

**Delivers:** `Note`, `ChecklistItem` `@Model` types (8 rules applied); list with auto-save (debounced 500ms), pin toggle, search via `.searchable`; inline checklist rows mixed with body text.

**Avoids:** `HouseholdItem` superclass temptation (Architecture Anti-Pattern 7) — proves per-feature models are the right call.

### Phase 4: Home Overview Screen + Charts

**Rationale:** Sells the app to the user. High motivation payoff. Aggregate queries + Swift Charts.

**Delivers:** Current-month spend-vs-budget bar; top 3 categories; pinned-note card; spend-by-category and spend-over-time charts (pre-aggregated to `Equatable` snapshots — see Pitfall 15); quick-add "+" actions.

**Research flag:** Swift Charts performance with reactive data + accessibility (Pitfall 15) — pre-aggregate outside view; add `.accessibilityChartDescriptor`; test at Dynamic Type `accessibility5`.

### Phase 5: Face ID Gate + Settings Shell

**Rationale:** Must exist before financial data feels "trusted." Also forces scenePhase thinking before background tasks land. Doing this now de-risks the BGTask phase later.

**Delivers:** `LocalAuthentication` wrapper using `LAPolicy.deviceOwnerAuthentication` (passcode fallback non-negotiable); `RootView` locked/unlocked switching; configurable grace period after backgrounding (default ~3–5 min); Settings tab scaffolded for upcoming Gmail account screen; explicit handling of every `LAError` case (`.biometryNotAvailable`, `.biometryNotEnrolled`, `.biometryLockout`, `.userFallback`, `.userCancel`, `.appCancel`, `.systemCancel`).

**Avoids:** Pitfall 11 (Face ID/Keychain lockout) by construction.

### Phase 6: `GmailClient` SPM Package (NO ingestion wiring yet)

**Rationale:** Network + auth is the riskiest unknown. Prove it as a package in isolation with a debug surface (a "Fetch latest 10 emails" button in Settings) before wiring it to anything else.

**Delivers:** `GmailClient` protocol + live implementation; `OAuthCoordinator` using `ASWebAuthenticationSession` + PKCE + custom-scheme redirect URI (NOT `localhost`, NOT `WKWebView`) (Pitfall 8); Keychain helper storing refresh token with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (NEVER `WhenUnlocked`, NEVER `biometryCurrentSet`) (Pitfall 11); `users.history.list` + `users.messages.get` against a real Gmail account; scope = `gmail.readonly` only (NOT `gmail.modify`); test target with `URLProtocol`-stubbed responses; initial-fetch query bounded by sender list + `newer_than:30d` (Pitfall 9).

**Open decision (see Conflicts section):** Pick Option A (GoogleSignIn-iOS SDKs) vs Option B (raw `ASWebAuthenticationSession` + URLSession) before starting this phase.

**Research flag (VERIFY at implementation time):**
- Google's current iOS OAuth client guidance — Google reshuffles auth libraries periodically (Pitfall 8)
- `gmail.readonly` scope verification rules — restricted scope; Testing-mode OAuth client refresh tokens expire every 7 days; design "reconnect Gmail" CTA accordingly
- Whether the 7-day refresh-token expiry has changed — was true through 2025

### Phase 7: `BankParsers` SPM Package + First Bank Parser

**Rationale:** Per-bank parsers are the long-tail. One parser proves the shape; the rest are a steady drip. Parsers are pure Swift and the easiest piece to TDD.

**Delivers:** `BankParser` protocol + `ParserRegistry` + `ExpenseCandidate` DTO (in pure-Swift SPM package, zero Apple-framework deps); one concrete parser (probably HDFC credit-card — pick whichever covers Reo's most-used card); golden-file tests with real anonymized email fixtures.

**Critical pre-requisite — collect 50+ real bank emails per target bank BEFORE building parser** (Pitfall 9). Empirically, training-data assumptions about Indian bank email templates are stale within months. Collect fresh samples from Reo's own Gmail.

**Parser must include from day one** (Pitfall 9):
- Whole-template fingerprint check separate from extraction regex
- Confidence score per parse (graded, not binary)
- Hard exclusion of OTP / promotional / verification emails (sender + subject pre-filters)
- Reversal/refund detection (`reversed`, `refund`, `credited back`, `reversal of` keywords)
- Raw email body storage (or hash + first 500 chars) for parser replay when templates drift
- `parserID + version` on every saved expense

**Research flag (VERIFY at implementation time):** Each target bank's current email template — they drift. Collect samples first; build parser second.

### Phase 8: `IngestionCoordinator` + Review Inbox

**Rationale:** Wires GmailClient + ParserRegistry + ExpenseStore. Get the pipeline working in the FOREGROUND first with a manual "Run ingestion now" button — background scheduling adds nondeterminism, fight that battle separately with a known-good pipeline.

**Delivers:** `IngestionCoordinator` actor; triage logic (confidence ≥ 0.85 → auto-save; else → Review Inbox); Review Inbox UI (one-tap accept, tap-to-edit, swipe-to-discard); duplicate-detection logic (dedup key: amount + merchant-substring + date ±1 day); merchant normalization seed table (~20–30 common Indian merchants); manual "Sync now" button in Settings.

**Research flag:** Confidence threshold (default 0.85) is a guess — calibrate against real data after first week of use.

### Phase 9: `BackgroundTasks` Registration

**Rationale:** Trivial code, huge testing pain. Doing it last means everything it depends on already works. ARCHITECTURE.md and PITFALLS.md both say: design the UX assuming background is best-effort.

**Delivers:** `BGAppRefreshTask` registered at launch with identifier in Info.plist `BGTaskSchedulerPermittedIdentifiers`; `setMinimumBeginDate: now + 30min`; handler calls `coordinator.runOnce()`; **always-visible "Last ingested at …" timestamp** in Settings (debugging lifeline); BGTask runs `@MainActor`-isolated to safely touch `ModelContext`.

**Verification gate (Pitfall 4 + Pitfall 20):** On-device, unplugged-overnight test required. Simulator BGTask trigger is theatre.

**Avoids:** Pitfall 4 by construction (UX already assumes on-launch is primary).

### Phase 10: Additional Bank Parsers (Long-Tail)

**Rationale:** Each parser is one file + one registry line + tests. Add ICICI, SBI, Axis, Kotak — whichever cards Reo and wife actually use. Build only the parsers needed; build the abstractions only after 2 concrete parsers exist (Anti-Pattern 8: premature parser abstractions).

### Phase 11+ (Post-v1, post-$99-upgrade or product-validated): Future Layers

**Phase 11a — Widget Extension:**
- App Group is already in place from Phase 0
- Snapshot-JSON pattern: app writes `overview-snapshot.json` to App Group container on every meaningful write; widget reads JSON in its timeline provider
- `WidgetCenter.shared.reloadAllTimelines()` from app on writes (Pitfall 13)
- **Research flag — VERIFY:** whether direct `@Model` access from widget extension is viable at the iOS target version; snapshot pattern is the safer assumption regardless

**Phase 11b — CloudKit Mirroring (private DB):**
- Strip every `@Attribute(.unique)` (Pitfall 1, 3); confirm with test that instantiates `ModelContainer(for:configurations:)` with `.cloudKitDatabase: .private("iCloud.com.<domain>.myhome")` and asserts it loads
- Switch `ModelConfiguration` to `.automatic` or `.private(...)`
- Add iCloud entitlement + CloudKit container provisioning in CloudKit Dashboard
- Test private DB sync between two of Reo's own devices (iPhone + iPad simulator) before sharing phase

**Phase 11c — CloudKit Sharing with wife's Apple ID:**
- Implement `windowScene(_:userDidAcceptCloudKitShareWith:)` delegate (Pitfall 14)
- One `Household` root record owning all shareable records via parent reference (already scaffolded in Phase 1 schema)
- `CKShare.Participant.permission = .readWrite` explicitly set
- Two-device + two-Apple-ID test required; expect 5–60s propagation
- "Last synced" UX exists (Pitfall 2 mirroring eventual-consistency)

**Phase 11d — watchOS app:** mirrors widget surface initially; read-only from shared store (writes only from iPhone in v1 of Watch) (Pitfall 13)

**Phase 11e — App Intents / Siri shortcut** (post widgets)

**Phase 11f — Per-merchant category memory** — triggered when 20+ manual corrections accumulate in Review Inbox

### Phase Ordering Rationale

- **Manual entry before ingestion** is the load-bearing sequencing call. Validates schema + UI + formatting + Face ID + budget loop on a closed end-to-end system before staking the project on the riskiest sub-system (Gmail OAuth + parser reliability + BGTask scheduling).
- **`GmailClient` package before parsers before `IngestionCoordinator` before BGTasks** mirrors ARCHITECTURE.md's "Build first / Build last" guidance and the PITFALLS.md observation that each piece compounds nondeterminism. Foreground "Sync now" must work before background scheduling is even attempted.
- **Phase 0 lock-ins (bundle ID, CloudKit container, App Group, Privacy Manifest, strict concurrency, model rules)** are placed first because they are one-way doors. Pitfalls 1, 5, 6, 12, 14, 18 all map here and all become catastrophic if discovered post-launch.
- **CloudKit work is consolidated post-v1** because the free Apple Developer account cannot provision a CloudKit container at all. Doing schema rules in Phase 1 means CloudKit becomes a *configuration flip*, not a rewrite — which is the entire point of the schema discipline.
- **Review Inbox is in the same phase as `IngestionCoordinator`**, not later. Parsers will be wrong on day one; the inbox makes failures one-tap fixes instead of trust-destroying silent garbage.
- **Charts in Phase 4** (not earlier) because they need aggregate queries that need manual data in the system first.

### Research Flags

Phases likely needing deeper research at planning time:

- **Phase 6 (GmailClient):** Google's current iOS OAuth + Gmail scope rules — Google reshuffles auth libraries periodically. Also: stack-choice decision (GoogleSignIn SDK vs raw `ASWebAuthenticationSession`) is genuinely open and should be resolved in the discuss-phase. **VERIFY** against Google's current installed-app OAuth guidance.
- **Phase 7 (BankParsers):** Each target bank's *current* email template — empirical sample collection is a hard prerequisite. Cannot be planned in detail without 50+ real emails in hand per bank.
- **Phase 11a (Widget):** **VERIFY** whether direct SwiftData `@Model` access from a widget extension is viable at the iOS target version, vs the safer snapshot-JSON pattern. Snapshot JSON is the recommended default regardless.
- **Phase 11b (CloudKit Mirroring):** **VERIFY** current SwiftData CloudKit constraints — `.unique`, optionality, inverse-required relationships. This is one of the highest-iteration surfaces in Apple's docs.
- **Phase 11c (CloudKit Sharing):** Two-device + two-Apple-ID testing is mandatory; cannot be validated single-device. Plan for empirical iteration.

Phases with standard patterns (skip research-phase):

- **Phases 1, 2, 3, 4, 5, 8, 9, 10** — well-documented SwiftUI/SwiftData/LocalAuthentication/Swift Charts/BGTasks patterns; the source research docs already provide concrete code shapes. Discuss-phase + plan-phase should suffice without additional research.

---

## Conflicts and Open Questions

Where the four researchers disagreed, or where guidance depends on user choice. Surface these at discuss-phase, do not bury them.

### Conflict 1 — Gmail OAuth library choice (Stack vs Pitfalls)

- **STACK.md recommends**: GoogleSignIn-iOS 9.x + GTMAppAuth + GTMSessionFetcher + GoogleAPIClientForREST_Gmail (official Google path, transitively handles OAuth state, ~1.5 MB binary, "MEDIUM confidence — Google has historically reshuffled iOS auth libraries").
- **PITFALLS.md recommends more strongly**: raw `ASWebAuthenticationSession` + PKCE + URLSession (forces explicit no-`client_secret` PKCE, avoids the `disallowed_useragent` and embedded-webview classes of bugs, no third-party SDK volatility).
- **Both agree**: never `WKWebView`, never `client_secret` in binary, always PKCE, always `gmail.readonly` only, always Keychain with `AfterFirstUnlockThisDeviceOnly`.
- **Open decision for discuss-phase:** which path? Recommendation: start with raw `ASWebAuthenticationSession` (Option B). PITFALLS.md's case is stronger for a personal app where Google SDK volatility is uncontrollable and the OAuth flow is small. ~150 lines of code with explicit PKCE is more inspectable than an opaque SDK chain.

### Conflict 2 — Repository pattern over SwiftData (Architecture vs Stack)

- **ARCHITECTURE.md says firmly**: no repository pattern; `@Query` in views; thin actor stores for multi-model writes only. Repository is Anti-Pattern 2.
- **STACK.md says** (under "If TDD friction hits SwiftData"): "Wrap SwiftData behind a `protocol ExpenseRepository` and inject an in-memory fake in tests."
- **Resolution:** ARCHITECTURE.md's "in-memory `ModelContainer(isStoredInMemoryOnly: true)` is faster than your mock" is the stronger argument. Use in-memory `ModelContainer` for tests; do not introduce a repository protocol layer. STACK.md's fallback is only relevant if SwiftData testing genuinely blocks shipping — empirically it doesn't at this scale.

### Conflict 3 — Approachable Concurrency mode vs strict concurrency

- **STACK.md recommends**: enable Approachable Concurrency (Swift 6.2's single-threaded-by-default opt-in) — friendlier for learner.
- **PITFALLS.md recommends**: strict concurrency at "complete" level from day one — easier to start strict than retrofit (Pitfall 18 is silent and rare-reproducer).
- **Resolution:** both are right at different time horizons. Recommendation: start with Approachable Concurrency on while building Phase 1–3 (UI + persistence), then turn strict concurrency to "complete" before Phase 6 (Gmail networking — first real cross-actor surface).

### Open Question 1 — Which 2 bank parsers in v1?

FEATURES.md says "probably HDFC + ICICI; pick whichever 2 cover Reo's primary cards." This is a user decision, not a research decision. Discuss-phase for Phase 7 should resolve this against Reo's actual card usage.

### Open Question 2 — Historical Gmail backfill depth

FEATURES.md flags: 30 days? 90 days? Trade-off between "instant value" (more backfill) and "parser failure visibility" (less). Cap to `newer_than:30d` for first OAuth grant (PITFALLS.md Pitfall 8 — avoids full-inbox-scan rate-limit pain) and offer "fetch older" as a Settings action later.

### Open Question 3 — Default budget month boundary

FEATURES.md flags: calendar 1st-of-month vs credit-card billing cycle. Default to calendar; revisit if it bites. Per-card billing-cycle-aware view is explicitly P3.

### Open Question 4 — Notification opt-in timing

FEATURES.md flags: first launch (annoying) / first budget-cross (smart) / never until asked (most respectful). Recommendation: never until asked, with a one-line Settings toggle.

### Open Question 5 — Manual entry FIRST vs ingestion FIRST

This is technically already resolved by ARCHITECTURE.md and PITFALLS.md (manual first, both for spine validation and for fallback availability). Surfaced here because it is the single most important sequencing call and must not be silently re-litigated by a future phase.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack — Apple platform choices (Swift 6.2, SwiftUI, SwiftData, Swift Testing, Swift Charts, LocalAuthentication, BackgroundTasks, Keychain) | HIGH | Verified against developer.apple.com (training data through May 2026). Stable Apple-blessed APIs. |
| Stack — Gmail SDK choice (Option A vs Option B) | MEDIUM | Both viable; Google has historically reshuffled iOS auth libraries (Pitfall 8 has examples). PKCE + `ASWebAuthenticationSession` is invariant either way. **VERIFY** Google's current installed-app OAuth guidance at implementation time. |
| Features — table-stakes, anti-features, MVP cut | HIGH | Apple Notes + Sheet competitive framing is durable; India category list and ₹-formatting requirements are grounded in en-IN locale reality. |
| Features — Indian bank email parsing specifics (subjects, body anchors, sender domains) | MEDIUM | Templates drift 1–3 times per year per bank; **VERIFY** empirically by collecting 50+ real samples per bank during Phase 7. Parser fingerprint + confidence gating mitigates the risk by design. |
| Architecture — overall shape (one app + 2 packages, `@Query` + actor stores, strategy parsers, snapshot widget) | HIGH | Maps cleanly to Apple's blessed patterns through iOS 17/18/26 era. |
| Architecture — 8 model rules + CloudKit-readiness | HIGH | Each rule prevents a documented `NSPersistentCloudKitContainer` constraint. **VERIFY** current SwiftData/CloudKit constraints at Phase 11b. |
| Architecture — Widget snapshot pattern | MEDIUM | Recommendation marked **VERIFY** in ARCHITECTURE.md — whether direct `@Model` access from widget process is viable at iOS target version. Snapshot JSON is the safer default. |
| Pitfalls — Top 5 (schema rules, ID locks, BGTask reliability, free-account limits, OAuth) | HIGH | Each pitfall is independently reproducible on any project of this shape; well-documented in Apple forums and WWDC content. |
| Pitfalls — Indian bank email drift (Pitfall 9) | MEDIUM | Severity is HIGH but specifics need per-bank empirical confirmation. The defensive design (fingerprint + confidence + raw-email storage) is sound regardless. |
| Pitfalls — Apple platform specifics (Pitfalls 1–8, 10–18, 20) | HIGH | Stable Apple-platform behaviors. |

**Overall confidence:** HIGH — the research converges across all four documents on the same shape of solution. The MEDIUM-confidence areas (Gmail SDK choice, bank-template drift, widget access pattern) are exactly the surfaces where Apple/Google iterate fastest, all are flagged **VERIFY**, and all have defensive defaults in the recommended approach.

### Gaps to Address

- **Gmail SDK decision (Option A vs Option B)** — resolve at discuss-phase for Phase 6. Recommendation: Option B (raw ASWebAuthenticationSession). **VERIFY** Google's current installed-app OAuth guidance.
- **Real bank email samples for parser fingerprinting** — must be collected from Reo's Gmail before Phase 7 planning. Phase 7 plan-phase should include a "collect 50+ real emails per target bank" task as a hard prerequisite.
- **Confidence-threshold calibration (default 0.85)** — needs real-data tuning after first week of Phase 8 usage. Plan a "calibrate threshold" task in Phase 8 retrospective.
- **Widget snapshot vs direct SwiftData access at Phase 11a** — **VERIFY** at planning time; default to snapshot JSON.
- **CloudKit schema constraint specifics at Phase 11b** — **VERIFY** current SwiftData/CloudKit docs immediately before stripping `.unique` and flipping mirroring on.
- **Per-bank email templates** — **VERIFY** with live samples during every parser build/update.

---

## Sources

### Primary research outputs (HIGH-MEDIUM confidence across the board)

- `/Users/reo/My Projects/my-home/.planning/research/STACK.md` — Apple platform stack, libraries, alternatives, what-not-to-use, version compatibility, confidence by recommendation
- `/Users/reo/My Projects/my-home/.planning/research/FEATURES.md` — feature landscape (table-stakes / differentiators / anti-features) for expense tracker + notes + overview + India-specific; MVP definition; prioritization matrix; competitor analysis; open questions
- `/Users/reo/My Projects/my-home/.planning/research/ARCHITECTURE.md` — system overview, project structure, 5 patterns, 8 model rules, data-flow diagrams, build order, CloudKit-readiness, watch/widget decisions, 10 anti-patterns
- `/Users/reo/My Projects/my-home/.planning/research/PITFALLS.md` — 20 pitfalls with severity + phase + recovery; tech-debt patterns; integration gotchas; performance traps; security mistakes; UX pitfalls; "looks-done-but-isn't" checklist; pitfall-to-phase mapping
- `/Users/reo/My Projects/my-home/.planning/PROJECT.md` — product charter, requirements, out-of-scope, key decisions, constraints

### Verification surface (re-check at implementation time — three of four researchers had WebSearch denied)

- developer.apple.com — SwiftData / NSPersistentCloudKitContainer / BackgroundTasks / LocalAuthentication / WidgetKit / Privacy Manifest / Observation
- developers.google.com — Gmail API + OAuth 2.0 for Mobile & Desktop Apps (installed-app flow specifics, scope policy, refresh-token expiry rules in Testing mode)
- Per-bank email templates — empirical collection from Reo's Gmail before Phase 7

---

*Research synthesis completed: 2026-05-28*
*Ready for roadmap: yes*
