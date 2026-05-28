# Stack Research

**Domain:** iOS-only personal-finance + notes household app (single-user v1, CloudKit-ready, Gmail-ingested expenses, Face ID-gated, TDD)
**Researched:** 2026-05-28
**Confidence:** HIGH for Apple-platform choices; MEDIUM for Gmail-on-iOS library choice (vendor SDK volatility); LOW where noted inline

---

## TL;DR Recommendation

Build with **Swift 6.2 + SwiftUI + SwiftData (with CloudKit-ready model graph) + Swift Testing**, targeting **iOS 17.0** minimum, in **Xcode 26**. Use **GoogleSignIn-iOS 9.x + GTMAppAuth 5.x + GTMSessionFetcher 5.x + google-api-objectivec-client-for-rest 5.x** for Gmail OAuth and API access (all official Google libraries, all Swift-Package-Manager-installable). Use **Swift Charts** for visualization, **LocalAuthentication** for Face ID, **Keychain Services** for tokens, **BackgroundTasks (BGAppRefreshTask)** for inbox polling. Use **swift-snapshot-testing** for view snapshots. Skip CI, fastlane, and SwiftLint for v1 — single-developer / two-user app does not earn its keep yet; add later if friction shows up.

The single most important non-obvious recommendation: **use SwiftData**, not Core Data, but model your `@Model` types as if every property had to become a `CKRecord` field — UUID primary keys, no inverse-required relationships, every non-key field optional with a default. SwiftData's CloudKit sync (added iOS 17, hardened in iOS 18) makes this a config change, not a rewrite, when you upgrade to the paid Apple Developer Program.

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

## Installation

```swift
// Package.swift dependencies (or "Add Package Dependency" in Xcode)
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

---

## Sources

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
*Researched: 2026-05-28*
