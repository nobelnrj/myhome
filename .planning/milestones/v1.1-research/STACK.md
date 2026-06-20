# Stack Research

**Domain:** iOS-only personal-finance + notes household app (single-user v1, CloudKit-ready, Gmail-ingested expenses, Face ID-gated, TDD)
**Researched:** 2026-05-28 (v1.0) · **Updated:** 2026-06-08 (v1.1 additions)
**Confidence:** HIGH for Apple-platform choices; MEDIUM for Gmail-on-iOS library choice (vendor SDK volatility); LOW where noted inline

---

## TL;DR Recommendation

Build with **Swift 6.2 + SwiftUI + SwiftData (with CloudKit-ready model graph) + Swift Testing**, targeting **iOS 17.0** minimum, in **Xcode 26**. Use **GoogleSignIn-iOS 9.x + GTMAppAuth 5.x + GTMSessionFetcher 5.x + google-api-objectivec-client-for-rest 5.x** for Gmail OAuth and API access (all official Google libraries, all Swift-Package-Manager-installable). Use **Swift Charts** for visualization, **LocalAuthentication** for Face ID, **Keychain Services** for tokens, **BackgroundTasks (BGAppRefreshTask)** for inbox polling. Use **swift-snapshot-testing** for view snapshots. Skip CI, fastlane, and SwiftLint for v1 — single-developer / two-user app does not earn its keep yet; add later if friction shows up.

The single most important non-obvious recommendation: **use SwiftData**, not Core Data, but model your `@Model` types as if every property had to become a `CKRecord` field — UUID primary keys, no inverse-required relationships, every non-key field optional with a default. SwiftData's CloudKit sync (added iOS 17, hardened in iOS 18) makes this a config change, not a rewrite, when you upgrade to the paid Apple Developer Program.

**v1.1 addendum:** All four new feature areas (Asset Tracker, Accounts, Self-Transfer Detection, Notes Enhancement) require **zero new SPM dependencies**. The only meaningful stack addition is a set of external HTTP data sources for pricing data — all free, all hit via the existing `URLSession`. The main architectural additions are: a `PriceService` actor pattern (URLSession + caching), a `VersionedSchema` bump for the new `Account` and `Asset` SwiftData models, and plain-text/JSON parsing helpers. Full detail in the v1.1 section below.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Swift** | 6.2 (current as of May 2026) | Application language | Bundled with Xcode 26; introduces `@concurrent`, inline arrays, the `Span` type, and matured strict concurrency. For a learner, Swift 6.2's "Approachable Concurrency" mode lets you opt into single-threaded-by-default and skip the strict concurrency cliff that bit early Swift-6 adopters. |
| **SwiftUI** | iOS 17 baseline (iOS 26 features available) | UI framework | The default modern path. iOS 17+ removed essentially every reason to mix UIKit. RN background makes the declarative model a comfortable jump. |
| **iOS deployment target** | **iOS 17.0** | Minimum supported OS | iOS 17 unlocks `@Observable`, SwiftData, `ScrollView` paging, `ContentUnavailableView`, `inspector`, and improved Swift Charts. Both users have recent iPhones (per PROJECT.md), so iOS 17 is free. Do **not** target iOS 16 — you lose SwiftData and the entire Observation framework. |
| **Xcode** | **26.x** (current branch; 26.3 latest at time of writing) | IDE / build / Instruments / simulator | Required for Swift 6.2, Swift Testing UI integration, the new SwiftUI Instrument, and Icon Composer. Older Xcode 15 is not viable: no `#expect` test reporter, no Swift 6 strict concurrency, no Liquid-Glass support. |
| **SwiftData** | iOS 17+ (use iOS 18+ APIs where available behind `if #available`) | Local persistence with CloudKit-ready model graph | See "SwiftData vs Core Data" section below. Right call for greenfield iOS 17+ app, especially given the CloudKit-future requirement. |
| **Swift Testing** | Bundled in Swift 6 toolchain / Xcode 26 (no SPM dep) | Unit + integration tests | Macro-based `@Test` / `#expect`; parameterized tests; parallel-by-default; first-class async/await; can coexist with XCTest. This is the TDD-default project's primary harness. |
| **XCTest** | Bundled | UI tests only | Swift Testing does not yet cover `XCUIApplication`-driven UI tests; UI tests stay in XCTest. Unit/integration tests should be Swift Testing. |
| **Swift Charts** | iOS 17+ baseline (iOS 16 minimum but use 17+ features) | All charts (spend-by-category, spend-over-time) | First-party, SwiftUI-native, declarative chart DSL. No third-party charting library is competitive on iOS 17+ for this scope. |
| **Observation framework (`@Observable`)** | iOS 17+ | View-model state | Replaces `ObservableObject`/`@Published`. Tracks field-level changes, fewer re-renders, no Combine import. |
| **LocalAuthentication** | iOS 17+ | Face ID app lock | First-party, one API call (`LAContext.evaluatePolicy`). No alternative worth considering. |
| **Keychain Services (Security framework)** | iOS 17+ | OAuth token storage | Required for storing the Gmail refresh token. Wrap in a thin helper (e.g., a 30-line `KeychainStore`) — do not pull in a third-party wrapper for v1. |
| **CloudKit / NSPersistentCloudKitContainer (via SwiftData)** | iOS 17+ for SwiftData; iOS 18+ for shared databases via SwiftData | Sync (post-v1) | Already exposed through SwiftData's `ModelConfiguration(cloudKitDatabase:)`. Nothing to bolt on later beyond enabling the capability and the schema-readiness rules below. |
| **BackgroundTasks** | iOS 17+ | Inbox polling for new bank emails | `BGAppRefreshTask` (short, frequent, network OK) is the right fit — schedule every ~30 min, opportunistically run when iOS deems the app worth waking. `BGProcessingTask` (long, plugged-in, idle) is overkill for ~50 email lookups. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **GoogleSignIn-iOS** | 9.1.0 (Jan 2026) | OAuth user-sign-in UI + token vending for Gmail scopes | First-launch Gmail authorization. Handles Safari/ASWebAuthenticationSession flow, PKCE, refresh tokens. SPM-installable. |
| **GTMAppAuth** | 5.0.0 (May 2025) | OAuth 2.0 plumbing under GoogleSignIn-iOS | Pulled in transitively; gives you `GTMAppAuthFetcherAuthorization` that bridges OAuth → Gmail API client. |
| **GTMSessionFetcher** | 5.3.0 (May 2026) | HTTP fetching layer with retry/backoff | Required by the Gmail API client below. SPM-installable. |
| **google-api-objectivec-client-for-rest** (`GTLRGmail`) | 5.3.0 (May 2026) | Typed Gmail API client (lists messages, fetches headers/body) | The canonical way to call Gmail API from Swift. ObjC-generated, fully Swift-interoperable. SPM-installable via the umbrella package — depend only on the `GoogleAPIClientForREST_Gmail` product to avoid pulling all 100+ Google APIs. |
| **swift-snapshot-testing** (pointfreeco) | 1.19.2 (Mar 2026) | SwiftUI view snapshots, encodable snapshots | Add once you have a stable view to regression-protect (e.g., monthly summary). Optional in v1, recommended by v1.1. |
| **Foundation `Regex` / `swift-regex` builders** | Bundled (Swift 5.7+) | Per-bank email parsing | Use Swift's literal `/.../` regex syntax or the `Regex { ... }` builder DSL. Do **not** use `NSRegularExpression` for new code. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Swift Package Manager (Xcode-integrated)** | All third-party deps | Use SPM exclusively. Both Google's SDKs and pointfreeco's libraries ship SPM manifests. No `Podfile`, no `Cartfile`. |
| **Xcode Instruments (SwiftUI instrument new in Xcode 26)** | Performance + view-update profiling if needed | Likely unused in v1 — two users, low volume — but it is the tool you reach for first when something feels slow. |
| **Xcode Test Plans** | Group Swift Testing + XCTest plans, parallelization, code coverage | Configure one plan that runs unit tests on every keystroke (CMD-U) and a separate one for UI tests. |

### Explicitly Deferred (do not install in v1)

| Tool | Why deferred |
|------|--------------|
| **SwiftLint** | Adds build-time friction for solo learner. The Xcode 26 compiler + Swift 6 strict-concurrency warnings already cover the highest-value lints. Add at v1.1 if style drift bothers you. |
| **swift-format** | Same reasoning. Xcode's built-in re-indent (CTRL-I) is sufficient. |
| **fastlane** | Solves problems a 2-user free-provisioning app does not have (TestFlight automation, screenshot generation, code-signing dance). Revisit when you upgrade to the $99/yr program and add TestFlight. |
| **GitHub Actions / any CI** | A green local `xcodebuild test` plus a pre-commit habit is enough until you have a collaborator. CI for a solo-built household app is ceremony, not value. |
| **Firebase Crashlytics / Sentry / any analytics** | PROJECT.md explicitly excludes telemetry. Use Xcode's built-in Organizer → Crashes once on TestFlight. |

---

## v1.1 Stack Additions — Asset Tracker + Accounts + Self-Transfer + Notes

> This section is the primary new content for the v1.1 milestone. The validated v1.0 stack above is unchanged.

### Summary of What Changes (and What Does Not)

| Area | Change | Rationale |
|------|--------|-----------|
| **SwiftData schema** | New `Account` and `Asset` `@Model` types; `VersionedSchema` bump to SchemaV6 | Pure SwiftData, same patterns as v1.0 |
| **Accounts management** | No new deps | Pure SwiftData + existing SwiftUI forms |
| **Self-transfer detection** | No new deps | Pure SwiftData query + existing `Expense` model |
| **Notes enhancement (daily routine → reminder)** | No new deps | Existing `UNUserNotificationCenter` + `CalendarView` + SwiftData |
| **Asset Tracker — MF NAV** | New HTTP data source: `portal.amfiindia.com` (plain-text) or `api.mfapi.in` (JSON) | URLSession only, no SDK |
| **Asset Tracker — NPS NAV** | New HTTP data source: `npsnav.in` (JSON, unofficial but open-source) | URLSession only; manual override mandatory because source is unofficial |
| **Asset Tracker — Stock quotes** | New HTTP data source: `query1.finance.yahoo.com` (JSON, unofficial/fragile) | URLSession only; manual override mandatory; highest fragility risk |
| **Caching** | New: `PriceCache` — in-memory + SwiftData `AssetPrice` model | Pattern: fetch → cache → never block UI |

---

### Data Sources for Pricing

#### 1. Mutual Fund NAV (AMFI) — HIGH confidence, STABLE

**Primary source: AMFI bulk file**

```
URL:    https://portal.amfiindia.com/spages/NAVAll.txt
Format: Semicolon-delimited plain text, UTF-8
Update: Published each business day after market close (typically ~7–8 PM IST)
Auth:   None
```

**Verified fields (as of 2026-06-05):**

```
Scheme Code ; ISIN Div Payout/Growth ; ISIN Div Reinvestment ; Scheme Name ; NAV ; Date
119551      ; INF209KA12Z1            ; INF209KA13Z9           ; Aditya Birla Sun Life Banking & PSU Debt Fund - DIRECT - IDCW ; 105.107 ; 05-Jun-2026
141586      ; INF846K01ZN6            ; -                       ; Axis Corporate Bond Fund - Direct Plan - Daily IDCW ; 10.2348 ; 05-Jun-2026
```

- Field 1 (`Scheme Code`): 6-digit integer — the canonical identifier to store in your `Asset` model
- Field 4 (`Scheme Name`): full descriptive name including plan (Direct/Regular) and option (Growth/IDCW)
- Field 5 (`NAV`): decimal string, 4–8 decimal places
- Field 6 (`Date`): `DD-MMM-YYYY` format (e.g., `05-Jun-2026`)
- Missing ISIN: represented as `-` (single hyphen)

**Parsing in Swift — zero deps needed:**

```swift
// Fetch + parse AMFI NAVAll.txt
let url = URL(string: "https://portal.amfiindia.com/spages/NAVAll.txt")!
let (data, _) = try await URLSession.shared.data(from: url)
let text = String(data: data, encoding: .utf8) ?? ""

struct AMFIRecord { let schemeCode: Int; let name: String; let nav: Decimal; let date: String }

let records: [AMFIRecord] = text
    .components(separatedBy: "\n")
    .compactMap { line in
        let parts = line.components(separatedBy: ";")
        guard parts.count >= 6,
              let code = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let nav = Decimal(string: parts[4].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return AMFIRecord(schemeCode: code, name: parts[3], nav: nav, date: parts[5])
    }
```

The file is ~5 MB. Parse on a background task/actor; only process scheme codes the user has added to their watchlist. The scheme code is the key — store it in the `Asset` SwiftData model at onboarding (let user search by name, store the code).

**Alternative: mfapi.in JSON API**

```
URL:    https://api.mfapi.in/mf/{schemeCode}
Format: JSON
Fields: meta.scheme_code, meta.scheme_name, data[0].date ("DD-MM-YYYY"), data[0].nav (string decimal)
Auth:   None; no rate limit advertised; "updated 6x daily, 99.9% uptime"
```

mfapi.in is a third-party service that wraps the same AMFI data. It is more convenient (one request per fund, JSON, no bulk parse) but introduces a single-point-of-failure that AMFI direct does not. **Recommendation:** Use `portal.amfiindia.com/spages/NAVAll.txt` as the primary source (parse in bulk once daily, cache all scheme NAVs you care about); use `api.mfapi.in` as a fallback or during onboarding to look up a scheme code by name.

Confidence: HIGH — AMFI is the official regulatory body's published data. The bulk file URL has been stable for many years (verified June 2026).

---

#### 2. NPS Fund NAV — MEDIUM confidence (unofficial aggregator)

**Source: npsnav.in (third-party, open-source, data from Protean/NSDL)**

```
URL (all funds, minimal):  https://npsnav.in/api/latest-min
URL (single fund):         https://npsnav.in/api/{schemeCode}
URL (single fund, detail): https://npsnav.in/api/detailed/{schemeCode}
URL (historical):          https://npsnav.in/api/historical/{schemeCode}
Format: JSON
Auth:   None; "unlimited non-commercial usage"
Update: Twice daily via GitHub Actions (11 AM + 11 PM IST)
```

**Verified JSON structure for `latest-min` (2026-06-05):**

```json
{
  "data": [
    ["SM001001", 49.4284],
    ["SM001002", 42.5247],
    ...
  ],
  "metadata": {
    "currency": "INR",
    "type": "NAV",
    "count": 257,
    "lastUpdated": "05-06-2026"
  }
}
```

Scheme codes follow the pattern `SM` + 6 digits (e.g., `SM001001` = SBI Pension Managers, Scheme E Tier I). The project maintainer (Rishikesh Sreehari) open-sources the scraper on GitHub — the data originates from Protean eGov Technologies (formerly NSDL), the official PFRDA-appointed CRA.

**There is no official PFRDA/NSDL machine-readable API.** The official sites (`npscra.nsdl.co.in`, `npstrust.org.in`) provide human-navigable HTML pages with weekly snapshots and downloadable PDFs. The npsnav.in service bridges this gap.

**Risk: this is a single-person hobby project.** If it goes offline, NPS NAV updates stop. This is acceptable only because:
1. Manual override is always available (the primary entry method for NPS anyway — most users have one NPS account with infrequent balance changes)
2. The underlying data source (Protean CRA) is public; you can replicate the scraper yourself if needed
3. NPS NAV changes are small day-to-day; a stale value for a few days is not a financial risk

**Flag in requirements:** NPS prices must never block the net-worth view. Show last-known NAV with a "as of [date]" label. Manual override is the primary path; API is a convenience.

Confidence: MEDIUM — data source verified June 2026; maintainer reliability is the risk.

---

#### 3. Stock Quotes (NSE/BSE) — LOW confidence, FRAGILE

**Option A: Yahoo Finance unofficial endpoint (currently working, legally grey)**

```
URL:    https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=1d
Symbol: NSE stocks use ".NS" suffix (e.g., RELIANCE.NS, HDFCBANK.NS, INFY.NS)
        BSE stocks use ".BO" suffix (e.g., 500325.BO)
Format: JSON
Auth:   None required currently; no API key
```

**Verified JSON path to current price (2026-06-05):**

```
chart.result[0].meta.regularMarketPrice   ← use this field (always present in meta)
chart.result[0].indicators.quote[0].close ← last candle close (same value, redundant)
```

Full response structure:

```json
{
  "chart": {
    "result": [{
      "meta": { "regularMarketPrice": 1263.3, "currency": "INR", ... },
      "timestamp": [...],
      "indicators": {
        "quote": [{ "open": [...], "high": [...], "low": [...], "close": [...], "volume": [...] }],
        "adjclose": [{ "adjclose": [...] }]
      }
    }],
    "error": null
  }
}
```

**Known risks:**

- Yahoo officially discontinued its Finance API in 2017. The `v8/finance/chart` endpoint is an undocumented internal endpoint reverse-engineered by the community.
- Yahoo has rate-limited and blocked this endpoint multiple times (most recently ~360 req/hour cap added late 2024 per community reports). A household app making one request per stock holding per day is well within any practical limit, but the endpoint can change or add auth requirements without notice.
- Yahoo's Terms of Service do not explicitly allow programmatic access by third-party apps. This is legally grey. For a private household app with no commercial use, the practical risk is zero — Yahoo has no interest in pursuing a 2-user personal app. Flag clearly: do not distribute this app externally while using this endpoint.

**Option B: NSE India direct endpoint (requires session cookie setup, more fragile)**

```
URL:    https://www.nseindia.com/api/quote-equity?symbol={SYMBOL}
Prereq: Must first GET https://www.nseindia.com with a browser User-Agent to receive session cookies
        Then include those cookies + specific headers in subsequent API calls
```

NSE's website aggressively detects non-browser clients. The session cookie approach works but requires a two-step dance every time cookies expire. This is materially more complex than Yahoo Finance for the same result. **Do not use NSE direct for v1.1.** The fragility of cookie management in a background app exceeds its benefit over Yahoo Finance.

**Recommendation for stocks:** Use Yahoo Finance `v8/finance/chart` with the `.NS` suffix. Keep the integration behind a `StockPriceService` protocol so the underlying source can be swapped later. Manual override is mandatory — treat every stock fetch as best-effort. Never display "loading" indefinitely; show last-known price with age label.

Confidence: LOW — Yahoo endpoint verified working June 2026 but undocumented, no formal ToS coverage, fragility risk is real.

---

### Swift Integration Pattern — PriceService Actor

No new SPM dependencies needed. The entire fetch/parse/cache layer is URLSession + SwiftData + Foundation.

**Recommended architecture:**

```swift
// Single actor owns all external price fetching
actor PriceService {
    private let session: URLSession
    private var lastFetch: [String: Date] = [:]       // prevent redundant calls

    func mutualFundNAV(schemeCode: Int) async -> Decimal? { ... }
    func npsNAV(schemeCode: String) async -> Decimal? { ... }
    func stockQuote(symbol: String) async -> Decimal? { ... }
}

// SwiftData model to persist last-known prices
@Model final class AssetPrice {
    var assetID: UUID          // FK to Asset
    var price: Decimal
    var fetchedAt: Date
    var source: PriceSource    // .amfi | .npsnav | .yahooFinance | .manual
}
```

**Caching rule:** Fetch at most once per asset per day (MF/NPS NAV changes once per business day; stocks once per trading day). Cache in `AssetPrice` SwiftData model. On app launch, show the cached value immediately; refresh in background if the cached value is older than the staleness threshold (configurable per asset type). Never await a network call on the main thread.

**Staleness thresholds:**

| Asset Type | Refresh threshold | Source frequency |
|------------|-----------------|-----------------|
| Mutual Fund NAV | 24 hours (skip weekends/holidays gracefully) | AMFI publishes once per business day |
| NPS NAV | 24 hours | npsnav.in updates twice daily |
| Stock quote | 8 hours (or market hours only) | Yahoo Finance real-time |
| Manual / account balance | Never auto-refresh | User-entered |

**Offline tolerance:** If the network fetch fails, silently fall back to the cached value. Log the failure but never surface an error to the user unless they explicitly tap "Refresh." The net-worth view must always render with cached data.

---

### Accounts Management — No New Deps

Account management is pure SwiftData + SwiftUI. New `Account` `@Model`:

```swift
@Model final class Account {
    var id: UUID
    var name: String               // "HDFC Savings", "ICICI Salary"
    var institutionName: String
    var accountType: AccountType   // .savings | .current | .credit | .loan
    var currency: String           // "INR"
    var balanceSnapshot: Decimal?  // manual entry, not live-linked
    var balanceUpdatedAt: Date?
    var isHidden: Bool             // exclude from net worth if desired
    var colorHex: String?          // UI color picker
    var createdAt: Date
}
```

Link existing `Expense.sourceAccount: String?` to this model by name or introduce a proper FK in SchemaV6. SwiftData migration handles the rename/link.

No networking needed. Account balances are user-entered. The asset tracker references `Account` for "cash/savings" asset class in net-worth calculation.

---

### Self-Transfer Detection — No New Deps

Algorithm is pure SwiftData query logic. Pattern: for each incoming debit on Account A, look back N hours for a matching credit on Account B (same amount ± tolerance, within a configurable time window). Surface as a candidate pair for user confirmation, never auto-exclude.

No new model types strictly required — add a `isSelfTransferCandidate: Bool` flag and a `pairedTransferID: UUID?` to `Expense`. Migration is a SwiftData SchemaV6 change.

No networking, no third-party library.

---

### Notes Enhancement (Daily Routine → Calendar Reminder) — No New Deps

The existing `UNUserNotificationCenter` + `CalendarView` + SwiftData `Note`/`Reminder` models are sufficient. The enhancement is:

1. A "daily routine" note type (or flag on existing `Note`)
2. When the user marks a note as daily routine, create a recurring `UNCalendarNotificationTrigger` at a chosen time
3. Surface the routine in the calendar view alongside existing reminders

All first-party frameworks. No SDK changes.

---

## Installation

```swift
// Package.swift dependencies (or "Add Package Dependency" in Xcode)
// v1.1 adds ZERO new SPM packages
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.1.0"),
    .package(url: "https://github.com/google/google-api-objectivec-client-for-rest", from: "5.3.0"),
    // Pulled transitively by the two above, but pin if you want determinism:
    // .package(url: "https://github.com/google/GTMAppAuth", from: "5.0.0"),
    // .package(url: "https://github.com/google/gtm-session-fetcher", from: "5.3.0"),

    // Optional, add when first view stabilises:
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.2"),
],
targets: [
    .target(
        name: "MyHome",
        dependencies: [
            .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS"),
            .product(name: "GoogleAPIClientForREST_Gmail",
                     package: "google-api-objectivec-client-for-rest"),
        ]
    ),
    .testTarget(
        name: "MyHomeTests",
        dependencies: ["MyHome"]
        // Swift Testing is in-toolchain; no dependency line needed.
    ),
]
```

Capabilities to enable in the Xcode target (Signing & Capabilities tab):
- **Sign in with Apple** — not strictly needed v1, but cheap to keep on the shelf.
- **iCloud → CloudKit** — add at the schema-design phase so SwiftData's `cloudKitDatabase: .automatic` works the moment you stop being on free provisioning. (On a free Apple ID, the capability adds an entitlement but CloudKit calls will fail; that is fine — SwiftData still works locally.)
- **Background Modes → Background fetch + Background processing** — needed for `BGAppRefreshTaskRequest`.
- **Keychain Sharing** — only if you ever split into multiple targets/extensions.

`Info.plist` additions:
- `NSFaceIDUsageDescription` — required string, e.g., "Unlock My Home to view your expenses."
- `BGTaskSchedulerPermittedIdentifiers` — array containing your background-refresh identifier (e.g., `com.reo.myhome.gmail-poll`).
- `GIDClientID` / URL types for Google Sign-In (Google's setup guide auto-generates these).

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **SwiftData** | **Core Data + NSPersistentCloudKitContainer** | If you hit a SwiftData CloudKit edge case that blocks shipping (history tracking, complex migrations, custom merge policies). Core Data's CloudKit mirroring is older, more battle-tested, and has better diagnostic tooling. For a 2-user app this is unlikely; for an enterprise app it would be the safer call. |
| **SwiftData** | **GRDB / SQLite.swift** | Only if you need full SQL, complex joins, FTS5 search, or want to avoid Apple's ORM entirely. None of these apply here. |
| **SwiftData** | **Realm Swift** | Don't. Realm is sunsetting under MongoDB Atlas Device Sync; new projects should not adopt it in 2026. |
| **GoogleSignIn-iOS** | **Raw ASWebAuthenticationSession + AppAuth-iOS** | If you ever need to drop the Google SDK weight (~1.5 MB binary) or want zero Google branding in the sign-in UI. The DIY path is ~150 lines and uses the same underlying OAuth — but you lose Google's revocation handling and refresh-token automation. Not worth it for v1. |
| **`google-api-objectivec-client-for-rest`** | **Raw `URLSession` calls to `https://gmail.googleapis.com/gmail/v1/...`** | Viable and arguably cleaner. Gmail's REST surface is small (you mainly need `users.messages.list` + `users.messages.get`). If pulling in an ObjC-generated client feels heavy, hand-roll the 4–5 endpoints you actually use. Recommended only if you're comfortable doing your own OAuth bearer-token attachment. |
| **Swift Testing** | **XCTest** | Stay on XCTest for: (1) UI tests, (2) any test that needs to subclass `XCTestCase` for legacy reasons. New projects should write all unit tests in Swift Testing. |
| **Swift Charts** | **DGCharts** (formerly Charts) | Only if you target iOS 15 or earlier, or need chart types Swift Charts doesn't yet have (e.g., candlestick). Neither applies. |
| **`@Observable` + light view-model classes (the "MV" style)** | **MVVM with full `ViewModel` per screen** | The Apple-blessed pattern in 2026 is closer to MV: views own `@State` for ephemeral UI, an `@Observable` model layer owns domain state, and you skip the per-screen ViewModel class unless logic justifies it. Reach for an explicit ViewModel when a screen has 3+ async sources of truth (e.g., Gmail polling + SwiftData query + budget calc). |
| **`Regex` literals (Swift 5.7+)** | **`NSRegularExpression`** | Use `NSRegularExpression` only when you need a regex stored as a runtime string from config and the input is untrusted. Per-bank parsers are compile-time-known, so use `/INR\s*([\d,]+\.\d{2})/` literals. |
| **BGAppRefreshTask** | **Silent push notifications from a server** | Would be more reliable than `BGAppRefreshTask` (which iOS schedules at its discretion) — but there is no server in this architecture, and silent push from Gmail would require a Pub/Sub topic + something to receive it. Out of charter. |
| **AMFI NAVAll.txt bulk parse (MF)** | **mfapi.in per-fund JSON** | mfapi.in is more convenient per-fund but adds a single-point-of-failure layer on top of AMFI. Use AMFI direct as primary; mfapi.in as a fallback or for fund-name search at onboarding. |
| **Yahoo Finance v8/chart (stocks)** | **NSE India direct endpoint** | NSE direct requires browser-style session cookie setup before each API call, which is fragile in a background context. Yahoo Finance is simpler despite its own fragility. |
| **npsnav.in (NPS)** | **Manual-only for NPS** | Valid choice. NPS balances change slowly; a user with one NPS account can enter the NAV quarterly. npsnav.in only adds value for users who check NPS performance frequently. The app must work well without it. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **UIKit (`UIViewController`-driven UI)** | No screen in this app needs UIKit. Mixing it in just to "play it safe" creates two mental models and doubles the learning curve for a Swift-newcomer. | SwiftUI throughout. Drop to `UIViewRepresentable` only if a missing control (none expected here) forces it. |
| **Core Data (as the primary persistence choice)** | Verbose `NSManagedObject` subclasses, KVO-style change observation, `.xcdatamodeld` editor that doesn't merge cleanly in git, and `NSManagedObjectContext` thread rules that bite TDD. Use **only** as a SwiftData fallback if you hit a blocking bug. | SwiftData. |
| **Realm / RealmSwift** | Acquired-and-deprioritized; Atlas Device Sync (the cloud sync story) is in maintenance. Not an iOS-2026 default. | SwiftData. |
| **Firebase (Auth/Firestore/Crashlytics/Analytics)** | Out of charter — recurring cost risk (free tier rug-pull history), third-party SDK weight, telemetry the project explicitly forbids. | CloudKit for sync, Keychain for auth state, no analytics. |
| **Supabase / any BaaS** | Same as Firebase: violates "no recurring cost" and "no third-party services" constraints. | CloudKit private DB (free with iCloud account). |
| **Plaid / TrueLayer / Open Banking aggregators** | Already excluded by PROJECT.md. Cost + weak India coverage + redundant given Gmail ingestion. | Gmail API. |
| **CocoaPods** | Sunsetting (project went read-only in 2024). Many libraries no longer publish new podspecs. | Swift Package Manager. |
| **Carthage** | Niche; SPM has feature parity for everything in this stack. | Swift Package Manager. |
| **RxSwift / Combine for new code** | Combine is in maintenance, RxSwift is third-party legacy. async/await + `@Observable` covers every async/reactive need in this app. | `async`/`await`, `AsyncSequence`, `@Observable`. |
| **`UserDefaults` for OAuth tokens** | `UserDefaults` is plain-text on disk. Storing a Gmail refresh token there is a CVE waiting to happen. | Keychain Services (`kSecClassGenericPassword`). |
| **`NSRegularExpression` for parsers** | Stringly-typed API, no compile-time validation, no typed captures. | Swift `Regex` literals or `Regex { ... }` builder. |
| **Embedded `WKWebView` for OAuth** | Google rejects embedded-webview OAuth (security policy) and Apple's review guidelines disallow it. | `ASWebAuthenticationSession` (what GoogleSignIn-iOS uses). |
| **`Timer` / silent background `URLSession` polling tricks** | iOS aggressively suspends apps; these approaches do not actually run in the background. | `BackgroundTasks` framework. |
| **SwiftLint / swift-format in v1** | Friction-to-value ratio is bad for a solo learner who hasn't formed style habits yet. | Defer; add in v1.1 if/when it earns its place. |
| **Any paid stock/financial data API (Alpha Vantage, Refinitiv, Tickermarket, etc.)** | Violates "zero recurring cost" hard constraint. | Yahoo Finance unofficial endpoint with manual override always available. |
| **NSE direct API without cookie session (stocks)** | Does not work; NSE returns 403 or redirects without proper session cookies and Referer header. | Yahoo Finance v8/chart with `.NS` suffix. |
| **Storing scheme codes/identifiers as hardcoded strings** | AMFI and NPS occasionally renumber schemes. | Store user-selected scheme codes in the `Asset` SwiftData model; let the user pick during onboarding via a search-by-name flow against the bulk file. |

---

## Stack Patterns by Variant

**If the project stays single-user past v1 (sharing never happens):**
- Drop the CloudKit capability and use `ModelConfiguration(cloudKitDatabase: .none)`.
- Keep the UUID-everywhere schema discipline anyway — it costs nothing and preserves future optionality (export/import, multi-device on the same Apple ID).

**If/when sharing with wife is enabled (post-$99 upgrade):**
- Switch `ModelConfiguration` to `.automatic`. SwiftData migrates the local store into the CloudKit private database on first sync.
- Add a `CKShare` flow for the records you want shared (wife joins via an iMessage link). On iOS 18+ SwiftData has `.shared` zone support; on iOS 17 you must hand-roll the `CKShare` via `CKContainer` for those records.
- Plan for an idempotent merge: every write should be `upsert by UUID`, never positional.

**If parsing accuracy turns out to be the killer feature (lots of failing emails):**
- Add a `ParsedExpenseCandidate` `@Model` with a `confidence: Double` and an "inbox" view of candidates < 0.7 confidence.
- Layer in `NaturalLanguage` framework (first-party, free, on-device) for merchant-name normalization. **Not** an LLM — keep this offline.

**If you decide to skip Gmail SDK weight entirely:**
- Use `ASWebAuthenticationSession` directly + manual `URLSession` calls to Gmail REST. The OAuth state machine is ~120 lines; you store the refresh token in Keychain yourself. This is the "no third-party deps at all" extreme and is genuinely viable here.

**If TDD friction hits SwiftData (in-memory `ModelContainer` is awkward to seed):**
- Wrap SwiftData behind a `protocol ExpenseRepository` and inject an in-memory fake in tests. Use SwiftData's `ModelConfiguration(isStoredInMemoryOnly: true)` for integration tests against the real schema.

**If Yahoo Finance blocks or rate-limits stock fetches:**
- Fall back to manual override immediately — do not chase alternative undocumented endpoints.
- Consider removing auto-refresh for stocks entirely; re-add when a stable free source appears.
- The net-worth view must remain functional with stale or manual-only stock prices.

**If npsnav.in goes offline:**
- Show last-known NAV with staleness warning, offer manual edit.
- Consider direct Protean CRA scraping as a fallback (the data is on a public HTML page); this is a maintenance burden not worth pre-building.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Swift 6.2 | Xcode 26.x | Enable "Approachable Concurrency" build setting to avoid the strict-concurrency cliff while learning. |
| SwiftData (iOS 17 APIs) | All targeted devices | iOS 18 added `#Index`, history tracking, custom data stores. Guard those with `if #available(iOS 18, *)`. |
| Swift Testing | Xcode 16+ | Xcode 26 includes the upgraded test reporter with `#expect` source highlighting. |
| GoogleSignIn-iOS 9.x | iOS 13+ | Vastly above your iOS 17 floor. Requires `GIDClientID` in Info.plist. |
| GoogleAPIClientForREST_Gmail 5.x | GTMSessionFetcher 5.x + GTMAppAuth 5.x | SPM resolves these automatically; conflicts only happen if you also pull in older transitive Google deps via another SDK. |
| swift-snapshot-testing 1.19.x | Xcode 26 / Swift 6.2 | Confirmed compatible; supports Swift Testing alongside XCTest. |
| `BGAppRefreshTaskRequest` | iOS 13+ | Your scheduled identifier must be listed in `BGTaskSchedulerPermittedIdentifiers` Info.plist key **and** registered on launch with `BGTaskScheduler.shared.register(forTaskWithIdentifier:)` before `application(_:didFinishLaunchingWithOptions:)` returns. |
| AMFI NAVAll.txt | URLSession, no deps | Bulk file; ~5 MB; parse on background actor. Stable URL, no auth. |
| mfapi.in JSON | URLSession, no deps | REST; no auth; no rate limit. Third-party wrapper over AMFI. |
| npsnav.in JSON | URLSession, no deps | REST; no auth; "non-commercial" usage restriction. Third-party scraper. |
| Yahoo Finance v8/chart | URLSession, no deps | Undocumented; no auth currently; ~360 req/hr rate limit (per community reports). `.NS` suffix for NSE stocks. |

---

## Confidence Levels

| Recommendation | Confidence | Reasoning |
|----------------|-----------|-----------|
| Swift 6.2 / Xcode 26 / iOS 17 minimum | HIGH | Verified against developer.apple.com, May 2026. |
| SwiftUI over UIKit | HIGH | No screen in this app needs UIKit; the Apple-blessed default for greenfield in 2026. |
| SwiftData over Core Data | HIGH (for greenfield iOS 17+ with eventual CloudKit sync) — MEDIUM if you discover the project needs heavy migration/history work | SwiftData's CloudKit story matured in iOS 18. Core Data is the documented fallback. |
| Swift Testing as primary harness | HIGH | Ships in the toolchain, parameterized + parallel + async-native, Apple's stated direction. |
| Swift Charts | HIGH | First-party, no competitive alternative on iOS 17+. |
| `@Observable` (Observation framework) | HIGH | Apple's documented default for SwiftUI model state since iOS 17. |
| LocalAuthentication + Keychain for Face ID + token storage | HIGH | The only correct choice on Apple platforms. |
| BackgroundTasks (`BGAppRefreshTask`) for Gmail polling | HIGH for the framework choice; MEDIUM for actual wake-frequency guarantees | iOS decides when to fire it; not deterministic. Real-world cadence is "several times a day for an actively used app." Accept that and design the UX around "next time you open the app, anything new from Gmail is here." |
| GoogleSignIn-iOS + GTLR Gmail client | MEDIUM | The official Google path, but Google has historically reshuffled its iOS auth libraries (GIDSignIn → AppAuth migration in v6, etc.). Pin major versions and re-evaluate annually. Raw `ASWebAuthenticationSession` + `URLSession` is a viable escape hatch. |
| Swift Package Manager only | HIGH | CocoaPods is sunsetting; Carthage is niche. SPM is the default. |
| Skip CI / fastlane / SwiftLint in v1 | MEDIUM (opinion, not consensus) | Some developers swear by enforcing these from day one. For a solo, learning-focused, two-user project the friction outweighs the value. Revisit at v1.1. |
| `Regex` literals over `NSRegularExpression` | HIGH | Compile-time-checked, typed captures, cleaner Swift. Only reason to use NSRegex is runtime-loaded patterns. |
| swift-snapshot-testing for views | MEDIUM | Worth it once views stabilize; over-investment to add on day one. |
| AMFI NAVAll.txt for MF NAV | HIGH | Official AMFI bulk file; verified format June 2026; stable multi-year URL. |
| npsnav.in for NPS NAV | MEDIUM | Data from official Protean CRA source; third-party aggregator risk; non-commercial only; manual override mandatory. |
| Yahoo Finance v8/chart for stock quotes | LOW | Undocumented, unofficial, legally grey, historically fragile. Works June 2026. Manual override is mandatory. |
| Zero new SPM dependencies for v1.1 | HIGH | All four new feature areas confirmed to need only URLSession + SwiftData + Foundation. |

---

## Sources

- `portal.amfiindia.com/spages/NAVAll.txt` — Verified June 2026; semicolon-delimited, 6 fields, Scheme Code is field 1, NAV is field 5, Date is field 6 in DD-MMM-YYYY format
- `api.mfapi.in/mf/{schemeCode}` — Verified June 2026; JSON with `meta` + `data[]` structure; `data[0].nav` is string decimal, `data[0].date` is DD-MM-YYYY
- `npsnav.in/api/latest-min` — Verified June 2026; JSON array of `[schemeCode, nav]` pairs + metadata; scheme codes are `SM` + 6 digits; data source is Protean CRA
- `github.com/rishikeshsreehari/npsnav` — Open-source scraper backing npsnav.in; confirms Protean CRA as data origin
- `query1.finance.yahoo.com/v8/finance/chart/RELIANCE.NS?interval=1d&range=1d` — Verified June 2026; `chart.result[0].meta.regularMarketPrice` is the current price field; `.NS` suffix for NSE stocks
- `github.com/ranaroussi/yfinance` issue #2128 — Rate limiting introduced late 2024; ~360 req/hr; community-sourced
- developer.apple.com/xcode/whats-new/ — Xcode 26 confirmed as current; SwiftUI Instrument, XCUIAutomation, Icon Composer.
- developer.apple.com/swift/whats-new/ — Swift 6.2 confirmed current; `@concurrent`, Inline Arrays, `Span`, Approachable Concurrency.
- developer.apple.com/ios/ — iOS 26 named as current OS in 2026; Liquid Glass, Apple Intelligence on-device.
- developer.apple.com/documentation/observation — `@Observable` macro, iOS 17 baseline, replaces `ObservableObject`/`@Published`.
- developer.apple.com/documentation/swiftui/managing-model-data-in-your-app — Apple-recommended pattern: `@Observable` + light view-model layer ("MV" style) over heavyweight per-screen MVVM.
- github.com/apple/swift-testing — Swift Testing bundled in Swift 6 toolchain & Xcode 16+; production-ready May 2026 (Swift 6.3.2 release).
- github.com/google/GoogleSignIn-iOS — v9.1.0 (Jan 2026), SPM-installable, ASWebAuthenticationSession-based OAuth.
- github.com/google/GTMAppAuth — v5.0.0 (May 2025), actively maintained, bridges OAuth → Google API clients.
- github.com/google/gtm-session-fetcher — v5.3.0 (May 2026), required HTTP layer.
- github.com/google/google-api-objectivec-client-for-rest — v5.3.0 (May 2026), `GoogleAPIClientForREST_Gmail` product for Gmail API.
- github.com/pointfreeco/swift-snapshot-testing — v1.19.2 (Mar 2026), works with Swift Testing.
- github.com/realm/SwiftLint — v0.63.3 (May 2026); noted but deferred.
- github.com/swiftlang/swift-format — v602.0.0 (Sept 2025), bundled with Xcode 26; deferred.
- Apple Core Data + CloudKit guide (`NSPersistentCloudKitContainer`) — established CloudKit fallback path if SwiftData blocks shipping.

---

*Stack research for: iOS-only personal-finance + notes household app (Reo, solo developer, new to native iOS)*
*Researched: 2026-05-28 (v1.0) · Updated: 2026-06-08 (v1.1 data sources + accounts/assets/self-transfer/notes additions)*
