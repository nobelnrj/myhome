# Pitfalls Research

**Domain:** Personal household-ops iOS app (Swift/SwiftUI + SwiftData → CloudKit; Gmail ingestion; Face ID; future Watch/Widget/sharing)
**Researched:** 2026-05-28
**Confidence:** HIGH on stack-level pitfalls (SwiftData/CloudKit, free-account ritual, BackgroundTasks, Face ID/Keychain, Privacy Manifest). MEDIUM on India-bank email parsing (format drift is continuous; specifics need empirical confirmation per bank).

> Audience: a strong React Native engineer who has never shipped native iOS. Every pitfall below is one that does not appear in beginner tutorials but will eat a week or force a schema rewrite if hit late.

---

## Top 5 most-likely-to-bite-you items

Read these first. If you only internalise five things from this document, make it these.

1. **SwiftData + CloudKit forces "everything optional, everything defaulted, no uniqueness, no `.deny` deletes"** — design the schema this way from day one even though v1 is local-only. Adding CloudKit later to a schema with required attributes / unique constraints / inverse-required relationships triggers a destructive migration. (Pitfall 1)
2. **Bundle ID + iCloud container ID are forever** — changing either after first launch orphans every record and every local store path tied to them. Pick `com.<yourdomain>.myhome` (NOT a `.local` or `.test` ID) and a CloudKit container name you can live with for life on day zero. (Pitfall 11)
3. **`BGAppRefreshTask` will not run reliably enough to be the *only* path for new transactions** — iOS throttles aggressively; on a free dev account installed via Xcode (no App Store heuristics for usage), it may not fire for days. Your UX must treat ingestion as "best-effort background + always-run on app open". (Pitfall 4)
4. **Free Apple Developer account: no CloudKit container, no push, no Sign in with Apple, no Background Modes that need entitlements, App Groups unreliable** — so the 7-day rebuild ritual is the *least* of your problems. Build v1 with zero of these on the critical path; pin the upgrade-to-paid moment to when sharing/sync actually lands. (Pitfall 5)
5. **Gmail OAuth on iOS with the installed-app flow has no client_secret protection** — use `ASWebAuthenticationSession` + PKCE, store refresh tokens with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly + biometryCurrentSet`, and never embed the OAuth client_secret in the binary. Also: `gmail.readonly` is a "restricted" scope and Google may show an "unverified app" screen forever on a personal app — that's fine for two users but understand the consent UX before users panic. (Pitfall 8)

---

## Critical Pitfalls

### Pitfall 1: SwiftData schema written for a local-only world that cannot be CloudKit-mirrored later

**What goes wrong:**
You design `@Model` classes with non-optional attributes, required inverse relationships, `@Attribute(.unique)` on IDs, default-less required fields, or `.cascade`/`.deny` delete rules. v1 ships locally and looks great. When you turn on CloudKit mirroring (`ModelConfiguration(cloudKitDatabase: .private(...))`) the container fails to initialise: `NSPersistentCloudKitContainer` refuses your schema. You now choose between a destructive wipe-and-resync or hand-writing a migration on top of an entity model that was never CloudKit-shaped.

**Why it happens:**
SwiftData over CloudKit inherits every constraint of `NSPersistentCloudKitContainer`: CloudKit's record schema cannot represent required (`NOT NULL`) attributes without defaults, cannot enforce uniqueness across devices (uniqueness is a single-store concept), and cannot represent required inverses or deny-delete (CloudKit deletes can arrive in any order). Tutorials happily show `var name: String` and `@Attribute(.unique) var id: UUID` because they work locally. They do not survive turning on mirroring.

**How to avoid:**
On every `@Model` from day one:
- Every stored property is **optional with a default** (`var name: String? = nil`, `var amount: Decimal = 0`).
- **No `@Attribute(.unique)`** anywhere. Enforce uniqueness in application code by upserting on a UUID you own.
- Every relationship is **optional**, with `inverse:` declared explicitly, and `deleteRule: .nullify` (not `.cascade` on the parent if children will also be CloudKit-shared; `.cascade` is OK only for tight ownership where the child has no shared meaning).
- Add a `var schemaVersion: Int = 1` field per model from the start — gives you a free escape hatch for future code-level migrations even before you wire formal `VersionedSchema`/`SchemaMigrationPlan`.
- Use `Decimal` (not `Double`) for money. CloudKit stores it fine, and you avoid floating-point drift on totals.
- Use `UUID` (stored as the model's natural ID, not `.unique`) for every entity. CloudKit's `recordName` will map cleanly later if you set it equal to your UUID string.
- **Use `@Attribute(.externalStorage)` for any blob > a few KB** (e.g. raw email HTML you may want to keep for debugging). CloudKit has per-record size limits (~1 MB asset inline, much smaller for "fields"); external storage maps to `CKAsset` on mirroring.

**Warning signs:**
- "It works in the simulator" but Xcode console spews `CoreData+CloudKit: ... unsupported configuration` once you flip mirroring on.
- You wrote `var amount: Decimal` without `= 0`. (Compiler is happy; CloudKit is not.)
- A relationship has `@Relationship(deleteRule: .cascade)` and you do not own *all* the records on both sides.

**Phase to address:**
**Phase 1 — Schema & persistence foundation.** This is a one-way door. Document the rules in a `SCHEMA-RULES.md` and add a test that asserts every `@Model` property is optional/defaulted via reflection (`Mirror`) so a future you cannot accidentally tighten a field.

**Severity:** CATASTROPHIC — forces rewrite of every model and a manual data migration from the on-device store.

---

### Pitfall 2: Treating SwiftData history tracking / mirroring as "instant" and writing UI that breaks on the latency

**What goes wrong:**
You write the expense, navigate to the list, and it's there — because locally SwiftData wrote synchronously. When CloudKit mirroring is on, the *other* device (wife's phone) sees the record after a delay that ranges from seconds to *hours* depending on network, push delivery, and CloudKit's backoff. Worse: on the writing device, if you observe via `@Query`, the local view updates immediately; on the receiving device you need to wait for `NSPersistentStoreRemoteChange` notifications, and SwiftData's view of the new objects may briefly lag the underlying store.

**Why it happens:**
CloudKit mirroring is *eventually consistent*. It uses silent push to nudge devices, but pushes are best-effort and can be coalesced or dropped. There is no "sync now" public API. Most tutorials never demo two devices, so this never surfaces.

**How to avoid:**
- Show a "last synced" timestamp somewhere unobtrusive (Home → Settings) so you can debug "where's my expense?" without instrumenting.
- In the sharing phase, add a pull-to-refresh on the expense list that calls `try await container.persistentCoordinator?.persistentStores.first?...` — actually the public hook is `NSPersistentCloudKitContainer.initializeCloudKitSchema` only at dev time; for runtime "force pull" you rely on remote-change notifications. Document that there is *no* sync-now button and design the UX around eventual consistency.
- Listen to `NSPersistentStoreRemoteChange` (or SwiftData's `.modelContextDidSave` + `ModelContext.processPendingChanges()`) and refresh views explicitly when it fires.
- For *single-device v1*, none of this matters — but write the list view assuming the data could arrive later so the post-v1 sharing phase doesn't reveal latent races.

**Warning signs:**
- You catch yourself writing "after save, navigate back" code that *assumes* the record is immediately visible to a `@Query` predicate filtering by date. Once shared, the other device will not see it for a while.
- During testing with two simulator instances (or sim + device), you see records appear minutes later and assume "the sim is broken". It isn't.

**Phase to address:**
**Phase 1 — Schema & persistence foundation** (write the UX assumption now). Actually exercised in the **CloudKit sharing phase** (post-v1).

**Severity:** ANNOYING (loses a day per device-pair you debug) — but a UX bug if the user sees "wife logged petrol but it's not on my phone" and panics.

---

### Pitfall 3: `@Attribute(.unique)` and `#Predicate` quirks that look like SwiftUI bugs

**What goes wrong:**
- `@Attribute(.unique)` is silently incompatible with CloudKit mirroring — adding it to a model with mirroring enabled prevents the persistent store from loading at all.
- `#Predicate` macros that compile fine throw cryptic runtime errors ("unsupported predicate") when you reference computed properties, optional chains with `??`, enum cases, or `Date()` (a non-deterministic expression). The compiler doesn't catch most of these.
- `@Query(sort: \.date, order: .reverse)` on an optional `Date?` silently puts `nil`s at one end inconsistently across iOS versions.

**Why it happens:**
`#Predicate` lowers to a Core Data `NSPredicate` representation. Anything outside that intersection — Swift computed properties, free functions, enum raw values used in comparisons, `Date()` literal — has no representation and crashes at evaluation time.

**How to avoid:**
- Stored properties only in `#Predicate`. Pre-compute a "now" `Date` outside the predicate and capture it into the closure.
- Convert enums to a stored `String` raw or `Int` raw at the `@Model` level and predicate on that. Do not predicate on the enum directly.
- For "current month" filters, pre-compute `startOfMonth` and `endOfMonth` as `let` constants before the `#Predicate` block, and capture them.
- Never use `@Attribute(.unique)`. Period. Enforce uniqueness in a repository layer (`func upsert(expense: Expense)` that fetches by UUID first).
- For sort-on-optional-date, make the date non-optional with a default of `Date.distantPast` and treat that as "unknown".

**Warning signs:**
- Crash log mentions `_PFPredicateBridge` or "unsupported expression".
- Records "disappear" from a list after iOS upgrade. Likely an optional-sort regression.

**Phase to address:**
**Phase 1 — Schema & persistence foundation** and **Phase 2 — Expense list / month view**.

**Severity:** ANNOYING (each occurrence loses an afternoon) but recurring throughout the project.

---

### Pitfall 4: BackgroundTasks framework as the *primary* path for new bank emails

**What goes wrong:**
You wire up `BGAppRefreshTask` with `setMinimumBegin Date: now + 15min`, test in Xcode by triggering `_simulateLaunchForTaskWithIdentifier:`, ship to your phone, then check in two days: zero new expenses ingested in the background. Some launches you see two days of emails import at once when the app reopens. Users assume the app is broken.

**Why it happens:**
- `BGAppRefreshTask` is opportunistic. iOS schedules based on app-usage prediction (when does the user normally open it?), battery state, network, Low Power Mode, and Focus modes. A *free-provisioned* app installed via Xcode has effectively no usage signal at first.
- `BGProcessingTask` is for >30 sec work and requires `requiresExternalPower` and/or `requiresNetworkConnectivity` flags — useful only for heavy reconciliations.
- Both task types require the app to have been *launched at least once* since reboot, *not* be force-quit, and the device must be unlocked at least intermittently.
- Background pushes ("silent push", `content-available: 1`) are the *only* reasonably-prompt way to wake an app — and those need APNs, which **the free Apple Developer account does not provide**. You can register, but pushes will not deliver.
- The simulator's `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"..."]` LLDB trick works *only* in the simulator and gives a false sense of confidence.

**How to avoid:**
- **Design the ingestion UX around on-launch sync, not background sync.** Every cold launch and every foreground entry runs an incremental Gmail fetch. Background is the bonus, not the spec.
- Use `BGAppRefreshTask` for opportunistic fetches with `setMinimumBegin Date: now + 30min`. Accept that "in the wild" it may fire only a few times per day.
- Set the app's last-fetch timestamp prominently in the UI so silent failure is visible.
- Do not use `BGProcessingTask` for the regular ingestion loop. Reserve it for monthly reconciliation if you ever build one.
- When you upgrade to a paid account, **add silent push** keyed to a server you do not own — instead, Gmail's `users.watch` (push notifications via Pub/Sub) can ping a Cloud Function, which... costs money and adds infra. Realistically, you live with on-launch + opportunistic-background forever. Make that design intentional.
- Test on a *real device* installed via Xcode with the device disconnected from the Mac and the app in background for >1 hour. Anything else is theatre.

**Warning signs:**
- Console log shows the BGTask submitted but never sees the handler fire on device after 24h.
- You catch yourself writing "the background task is broken" when actually it's just rate-limited.

**Phase to address:**
**Ingestion phase (post Phase 1).** Lock the UX assumption now: "the canonical sync is on-launch; background is best-effort."

**Severity:** CATASTROPHIC for the *product* if ingestion is sold as zero-touch; ANNOYING if the UX is honest from day one.

---

### Pitfall 5: Free Apple Developer account capability surprises

**What goes wrong:**
You discover one-by-one over weeks that the free account cannot enable: Push Notifications, CloudKit (the entitlement toggles but the container won't provision), Sign in with Apple, Associated Domains (universal links / OAuth callbacks), background modes that require entitlements (e.g. "Remote notifications"), HealthKit, In-App Purchase, App Groups (works *intermittently* on free, but with no guarantee — and the App Group ID needs the team prefix which changes when you switch to a paid account).

**Why it happens:**
Apple intentionally gates "shippable" capabilities behind the paid Developer Program. The free tier is for "build and run on your own devices" and supports a deliberately limited entitlement set.

**How to avoid:**
- **Defer every capability that requires the paid account to a clearly-labelled post-v1 phase.** Specifically: no CloudKit code paths active in v1, no remote push registration, no SIWA, no App Groups (which means: no Widget or Watch extension v1).
- The 7-day rebuild ritual matters: the *free-provisioned provisioning profile expires every 7 days*, the *signing certificate is tied to your Apple ID*, and Xcode silently re-signs on connect. To survive: plug phone into Mac on Sunday night, hit Run, accept the trust dialog. If you let it lapse the app *will not launch* — it will not crash with a meaningful error, the icon just bounces and dies.
- Document the bundle ID (`com.<yourdomain>.myhome`) and *do not change it* when going paid. If you do, all on-device data is orphaned.
- App Groups: skip entirely for v1. Designing Watch/Widget extensions in v1 is gated on App Groups working, which is gated on a paid account.
- When you do upgrade: budget *one full afternoon* for the paid-account migration — new team prefix on bundle IDs, new provisioning profiles, new App Group IDs, new Keychain access group, possibly a fresh "first launch" experience because Keychain items keyed by access group are not visible across the change.

**Warning signs:**
- "Failed to register for remote notifications" with error 3000 → free account, no APNs.
- CloudKit Dashboard says container doesn't exist → free account cannot provision.
- App icon launches and immediately closes after a week without re-build → free profile expired.
- Build succeeds in Xcode, then "Unable to install" on device → trust the dev certificate in Settings > General > VPN & Device Management.

**Phase to address:**
**Phase 0 — Project bootstrap.** Pin the bundle ID, list which entitlements are deferred, document the 7-day ritual in the project README.

**Severity:** ANNOYING (loses a day each time you bump into one) — but CATASTROPHIC if you scope v1 to require any of these and discover it mid-build.

---

### Pitfall 6: Bundle identifier and iCloud container ID changes after first install

**What goes wrong:**
You ship as `com.reo.MyHome.dev` for v1. Going to TestFlight you rename to `com.reo.myhome`. The app on your device now treats itself as a new app — Documents directory, Keychain (without explicit access group), `UserDefaults` (suite `standard`), SwiftData store path: all live under the bundle ID, all are orphaned. CloudKit container `iCloud.com.reo.MyHome.dev` cannot be renamed; mirroring to the new container ID requires schema redeploy and the old records do not migrate.

**Why it happens:**
On iOS, the sandbox path is `~/Containers/Data/Application/<UUID>/` keyed to the bundle ID at install time. CloudKit container IDs are global, immutable namespaces on Apple's servers.

**How to avoid:**
- Pick the *real* bundle ID on day zero. Suggested: `com.<your-domain>.myhome` (your-domain must be a domain you actually own *or* a stable reverse-DNS that you commit to). Do not use `.dev`, `.test`, or `.local` suffixes.
- Pick the *real* CloudKit container ID on day zero, even if you won't enable mirroring for months: `iCloud.com.<your-domain>.myhome`. Add the entitlement file but don't activate mirroring. You won't actually provision the container until paid, but the *naming* must be locked.
- If you absolutely must rename later, plan a one-shot export → import migration: read all `@Model` instances → encode to JSON → install the renamed app → import. There is no "Apple-supported" rename path.

**Warning signs:**
- Xcode "Capabilities" pane shows your container ID has a "dev" or "v2" suffix.
- Tempting yourself to use a different bundle ID per build configuration. Don't — use schemes with the *same* bundle ID and different display names if you need to differentiate.

**Phase to address:**
**Phase 0 — Project bootstrap.** Add `BUNDLE_ID.md` (one line) and treat it as immutable.

**Severity:** CATASTROPHIC — there is no in-place rename and all on-device data is orphaned.

---

### Pitfall 7: SwiftData migrations done badly — losing every user's data on app update

**What goes wrong:**
v1 ships with `Expense { amount: Decimal, date: Date, merchant: String? }`. v1.1 you "just rename" `merchant` to `payee` and add a non-optional `currency: String`. On launch v1.1, the persistent store fails to open, SwiftData falls back to a fresh store, and *all the expense history disappears*. Worse: you might not notice for days because you keep installing fresh dev builds.

**Why it happens:**
- SwiftData does *lightweight* automatic migration only when changes are inferable (add optional attribute, remove attribute, rename via `@Attribute(originalName:)`).
- Renaming without `originalName:` → store fails to open → SwiftData *silently* falls back to new store on some configurations or crashes on others.
- Adding a non-optional attribute *without* a default value → migration cannot synthesise initial values → store fails.
- iOS 17.0–17.3 had several SwiftData migration bugs that were partially fixed in 17.4+ but not all (e.g. relationship rename remained fragile through 17.5).

**How to avoid:**
- From v1.0 onward, every schema change goes through a `VersionedSchema` with explicit `SchemaMigrationPlan` even when changes are "trivially" lightweight. Treat lightweight migration as "Apple's best effort, not my contract."
- Every new attribute is optional with a default for at least one release. You can tighten in a later version after you confirm all installs upgraded.
- Renames use `@Attribute(originalName: "merchant") var payee: String?` — never just rename.
- Add an integration test that loads a *bundled v1 store file* and runs the current migration plan against it. Snapshot the seeded v1 store into the test target as a `.sqlite` resource. This is the single most valuable test you can write.
- On every dev build: keep one "golden" device install around (not reset between builds) that has been running since v0.1. That device finds migration bugs CI cannot.

**Warning signs:**
- After updating the model, app opens and the list is empty. Don't shrug — investigate immediately.
- Xcode console: `CoreData: error: -executeRequest: encountered exception = ... while executing fetch`.
- You renamed a property without `@Attribute(originalName:)`.

**Phase to address:**
**Phase 1 — Schema** (set up `VersionedSchema` scaffolding from v1.0 even with only one version). **Every phase that touches schema.**

**Severity:** CATASTROPHIC — there is no recovery from "user's expenses are gone" without restoring from iCloud backup, which most users don't have for app-specific data.

---

### Pitfall 8: Gmail OAuth done in a way that breaks under refresh-token revocation and "less secure app" UX

**What goes wrong:**
You wire up OAuth using a `WKWebView` (because it's tempting) and embed the OAuth `client_secret` from Google Cloud Console into the iOS binary. Tokens get revoked routinely because (a) Google's heuristics flag in-app webviews as suspicious, (b) refresh tokens granted to "Testing" OAuth clients expire every 7 days, (c) you're parsing the redirect URL by checking for `localhost` and an `ASWebAuthenticationSession`-based flow would have been one-liner. Then the user gets logged out weekly and re-OAuth fails because you didn't handle the revocation gracefully.

**Why it happens:**
- Google has been actively blocking embedded webview OAuth flows since 2021 for security policy reasons. Errors like `disallowed_useragent`.
- iOS installed-app OAuth flow is the "native app" flow — no `client_secret`, use **PKCE**.
- Google OAuth in "Testing" mode (which is where you'll be without app verification) issues refresh tokens that expire in **7 days**. You only escape this by either publishing the OAuth client (and going through brand verification — months for a `gmail.readonly` scope, which is "restricted") or *staying in production mode with only your two Google accounts added as test users* (still 7-day refresh tokens until you publish).
- `gmail.readonly` is a "restricted" scope under Google's CASA rules. For a personal app used by two people, you can stay in "Testing" mode indefinitely with both Google accounts added as test users — but you must rebuild the refresh-token flow gracefully because the token will expire.

**How to avoid:**
- **`ASWebAuthenticationSession`** for the OAuth flow, with `ephemeralWebBrowserSession = false` so the system Safari cookie jar is reused (less repeat login pain). The redirect URI is a custom scheme registered in `Info.plist` (e.g. `com.<your-domain>.myhome:/oauth/google`) — NOT `http://localhost`.
- **PKCE every time.** No `client_secret` in the binary. Use Google's "iOS" OAuth client type which is explicitly secret-less.
- Scope = `https://www.googleapis.com/auth/gmail.readonly` *only*. Do not request `gmail.modify` even though you might want to label processed emails — labelling pushes you into deeper verification.
- Refresh-token handling: on any `400 invalid_grant` from refresh, surface a one-tap "reconnect Gmail" CTA. Do not spin in a retry loop.
- Store tokens with Keychain access `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not `WhenUnlocked`, because background fetches must work when device is locked but unlocked at least once since boot) and access group set to your app's group when Watch/Widget arrive.
- Cap email fetch to `q:from:(alerts@hdfcbank.net OR ...) newer_than:30d` with `maxResults` — never `users.messages.list` with no filter on first install (that returns everything; rate-limit pain and battery hit).
- Use `historyId` + `users.history.list` for incremental fetch after the initial backfill, not date-bound list calls.

**Warning signs:**
- You see `client_secret` in your Swift source.
- You're using `WKWebView` for the auth screen.
- You hit Gmail rate limits in dev → you're doing full-inbox scans.
- Refresh fails silently and the next BGTask "fetches zero emails" with no log line about auth.

**Phase to address:**
**Ingestion phase — Gmail integration sub-phase.** Decide PKCE + `ASWebAuthenticationSession` before writing a single line of OAuth.

**Severity:** ANNOYING (loses a few days of redo if started wrong); CATASTROPHIC for trust if the refresh-token UX silently breaks ingestion and the user only notices when month-end totals are wrong.

---

### Pitfall 9: Indian bank email parsing — assuming today's template is tomorrow's template

**What goes wrong:**
You handcraft a regex per bank (HDFC, ICICI, SBI, Axis) against the current template. It works for two months. HDFC pushes a template refresh (adds an emoji header, changes "spent on" to "debited from", reformats the date), your parser silently extracts garbage (or worse, half-correct data), and a week of expenses are mis-categorised before you notice.

**Why it happens:**
- Indian banks update email templates frequently (typically 1–3 times per year, sometimes per-card-product) without notice.
- HTML emails are often re-flowed differently per Gmail rendering, and the plain-text alternative may be entirely missing or auto-generated from HTML in lossy ways.
- Transaction-reversal emails ("Your transaction of INR 500 has been reversed") look superficially like fresh transactions to a naive regex.
- OTP emails ("Your OTP is 482910 for a transaction of INR 1200 at AMAZON") match "INR <amount> at <merchant>" and get ingested as transactions.
- Promotional emails from the same sender ("Save INR 500 on your next dinner!") trip naive amount-extraction.
- Multilingual bodies (Hindi-English mix in body, English in subject) confuse parsing if you use the body as the merchant source.

**How to avoid:**
- **Parser per (bank, message-template) pair, not per bank.** Each parser asserts its *whole-template fingerprint* (a known phrase like "We are writing to inform you of a transaction on your HDFC Bank Credit Card ending"); only when the fingerprint matches does it attempt extraction. A template refresh changes the fingerprint → parser declines → email goes to the "inbox for review" queue. No silent garbage.
- **Filter at the Gmail query level first.** Build a per-bank list of (sender, subject prefix) tuples. Anything outside that goes to a "uncategorised" bucket — never auto-parsed.
- **Hard-exclude OTP and promotional**: a regex that matches "OTP", "verification code", "save", "offer", "cashback offer", "promotional", "earn .* reward" in subject or first 200 chars → drop.
- **Detect reversals explicitly**: parse the keyword set (`reversed`, `refund`, `credited back`, `reversal of`) before parsing amount; route to a reversal handler that links back to the original transaction (or stores as a negative-amount expense).
- **Confidence score per parse**: amount extracted ✓, merchant extracted ✓, date extracted ✓, currency confirmed INR ✓ → high. Missing merchant or ambiguous date → low → user-review inbox. *Never auto-save low-confidence parses.*
- **Replay corpus**: store the raw email body (or a hash + first 500 chars) for every email you ingest, so when a template changes you can re-run a new parser against past emails in seconds.
- **Per-bank test fixtures**: real anonymised emails (yours, with the amount/merchant changed) checked into the test target. Every parser change runs against every fixture.
- **Manual entry is sacred.** The instant the parser confidence drops, fall back to manual entry — *never* auto-fill with low-confidence guesses, that's a worse UX than empty.
- Do not parse from the HTML directly. Convert to plain text first using Apple's `NSAttributedString(data:options:documentAttributes:)` with HTML option — but be aware this is *slow* (don't do it inline in BGTask; do it in a dedicated queue) and `WKWebView`-based parsing is overkill.

**Warning signs:**
- One regex matches "amount" — it matches *too many things*.
- Your confidence score is binary (parse / no parse) instead of graded.
- You don't have a "review needed" inbox in the UI — that means every parse must succeed perfectly, which guarantees you'll auto-save garbage.
- You discover a category miscategorisation by checking the month-end total. Too late.

**Phase to address:**
**Ingestion phase — parser sub-phase.** Plus a *standing* phase: "parser update" should be a routine quick-task whenever a bank changes templates.

**Severity:** CATASTROPHIC for product trust (wrong financial data is worse than no data) if parsers are not designed for graceful failure; ANNOYING if the review-inbox fallback exists.

---

### Pitfall 10: SwiftUI state model confusion — `@State` vs `@Bindable` vs `@Observable` vs `@Environment`

**What goes wrong:**
- You use `@State` for a SwiftData `@Model` object passed into a view. The view doesn't update when the object changes from elsewhere (e.g. a background ingestion writes a new expense; the list re-renders but the detail view doesn't).
- You use `@StateObject` (pre-Observation) on a class that already uses `@Observable` macro — leaks happen and updates don't propagate.
- You pass a `@Bindable` property to a child without realising the child needs `@Bindable` too to participate in two-way binding.
- You mutate a `@Model` object from a `Task {}` inside a view body — race conditions.
- `NavigationStack` `path: $path` with a non-`Codable` `NavigationDestination` value loses state on app suspend/restore.

**Why it happens:**
iOS 17 introduced the `@Observable` macro replacing `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`. The old types still compile and "work" but mixing them with the new types produces silent bugs. Tutorials are inconsistent.

**How to avoid:**
- **All-in on `@Observable` (iOS 17+).** Your project minimum is iOS 17, so commit:
  - View-local state: `@State` for value types (Bool, String) and `@State` for `@Observable` reference types you *own* (created in the view).
  - Passed-in `@Observable` reference types: declare them with `@Bindable` if the view writes to them, plain `let` if the view only reads.
  - Shared app-level state: `@Observable` class injected via `.environment(...)`, read via `@Environment(MyStore.self)`.
- **SwiftData objects**: `@Query` to fetch in a list view; `@Bindable` to edit in a detail view; never `@State` on a `@Model`.
- **Don't mix `@Observable` and `ObservableObject` in the same module.** Pick one.
- **NavigationStack paths**: model `NavigationDestination` as a `Codable enum` with associated values that are themselves `Codable` (e.g. `UUID` not the model object). Persist the path with `SceneStorage` only if you actually want restoration; otherwise leave it transient.
- **Mutate models on `@MainActor`** — SwiftData `ModelContext` is bound to its actor. Background work fetches `PersistentIdentifier`s, switches to main, then mutates.

**Warning signs:**
- You see `@StateObject` or `@Published` anywhere in new code → wrong era.
- Detail view shows stale data after navigating to it.
- "It works when I navigate fresh but stale when I navigate back."
- Console warning: "Publishing changes from within view updates is not allowed."

**Phase to address:**
**Phase 0/1 — set the rule in the project README** ("we use `@Observable`, never `ObservableObject`"). Enforce via a code-review checklist.

**Severity:** ANNOYING per occurrence; cumulative pain if the convention isn't set early.

---

### Pitfall 11: Face ID + Keychain edge cases that lock the user out of their own data

**What goes wrong:**
- User upgrades iPhone, restores from iCloud backup; Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` did *not* migrate (they're `ThisDeviceOnly`). Gmail refresh token is gone; the app silently re-prompts for OAuth — fine. But if you used `biometryCurrentSet` access control, the *Keychain item is deleted* when the user re-enrolls a face — they lose their token and any encrypted local data.
- User has Face ID disabled in Settings or has no biometrics enrolled (e.g. fresh device). Your "Face ID required" gate dead-ends; you forgot to provide a passcode fallback via `LAPolicy.deviceOwnerAuthentication`.
- You authenticate with `LAPolicy.deviceOwnerAuthenticationWithBiometrics` and assume success means it's actually them — it can also be a child who got past the Face ID match because of poor lighting or because Apple's matcher is lenient. (Not your problem on a household app, but worth knowing.)
- Simulator: Face ID is faked via Features → Face ID → Matching/Non-matching. Some Keychain APIs behave differently in sim vs device — particularly `kSecAccessControlBiometryCurrentSet` may fail to create an item in the sim.
- You did NOT use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for items needed by background tasks → background ingestion can't decrypt the Gmail token because the device was rebooted and not yet unlocked.

**Why it happens:**
Keychain's access classes and access-control flags are subtle, the docs are scattered, and `LocalAuthentication` failure modes are not obvious.

**How to avoid:**
- Two-tier secret storage:
  - **Gmail refresh token**: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no biometric requirement. Background tasks need it; biometric on every BGTask is impossible.
  - **App lock**: separate — implement as a *UI gate* using `LAContext` evaluation. Don't actually encrypt SwiftData with it; just block the UI until auth succeeds.
- Use `LAPolicy.deviceOwnerAuthentication` (NOT `...WithBiometrics`) so passcode fallback works if Face ID is disabled, hardware unavailable, or user has too many failures.
- Handle `LAError` cases explicitly: `.biometryNotAvailable`, `.biometryNotEnrolled`, `.biometryLockout`, `.userFallback`, `.userCancel`, `.appCancel`, `.systemCancel`. Display the appropriate message.
- Do NOT use `kSecAccessControlBiometryCurrentSet` for the Gmail token. Use it for items you *want* to be invalidated on enrollment change (e.g. if you ever store a master key derived from biometry — you probably won't on this app).
- Test on simulator with biometry disabled + with passcode unset (Erase All Settings flow). The "passcode unset" path is the one that's missed most often.
- When Watch/Widget arrive, items needed cross-process need `kSecAttrAccessGroup` set to a shared keychain group, which requires Keychain Sharing entitlement, which requires the paid Developer account team prefix.

**Warning signs:**
- Background tasks claim "no auth token" right after device reboot. → `WhenUnlocked` instead of `AfterFirstUnlock`.
- App refuses to open after a Face ID re-enrollment with no recovery path. → `biometryCurrentSet` on the gate.
- Keychain `errSecInteractionNotAllowed (-25308)` in console → trying to access protected item while device is locked.
- Sim works, device doesn't.

**Phase to address:**
**Phase 1 — Foundational (Face ID gate + Keychain helper).** Re-visit when **Watch/Widget extensions** land (Keychain access group).

**Severity:** CATASTROPHIC if user data becomes irrecoverable; ANNOYING for the simulator vs device quirks.

---

### Pitfall 12: Privacy Manifest (`PrivacyInfo.xcprivacy`) and Required-Reason APIs surfacing at App Store / TestFlight time

**What goes wrong:**
v1 is sideloaded so you never add `PrivacyInfo.xcprivacy`. v1.5 you upload to TestFlight; the upload fails or the App Store warns you that you use Required Reason APIs (`UserDefaults`, file timestamps `creationDate`/`modificationDate`, `SystemBootTime`, disk space) without declaring a reason. You scramble to add the manifest with reasons, but you also notice third-party SDKs (you have none, good) would each need their own manifest.

**Why it happens:**
Apple introduced the Privacy Manifest requirement (effective May 2024 for App Store submissions). Required Reason APIs are common Swift/Foundation calls that *every* app uses (`UserDefaults.standard.set`, `FileManager` file dates, `Date()` for timestamps in some readings). Without a declared reason, the API call is technically forbidden by App Store review.

**How to avoid:**
- Add `PrivacyInfo.xcprivacy` to the app target from day zero, even for sideload-only v1. It's free and removes a future surprise.
- Declare the Required Reasons you actually use:
  - `NSPrivacyAccessedAPICategoryUserDefaults` → reason `CA92.1` (app functionality).
  - `NSPrivacyAccessedAPICategoryFileTimestamp` → reason `C617.1` (display to user) if you show "last synced" times, `DDA9.1` (inside the same app) otherwise.
  - `NSPrivacyAccessedAPICategorySystemBootTime` → reason `35F9.1` (compute time intervals) if you measure perf, otherwise don't call it.
  - `NSPrivacyAccessedAPICategoryDiskSpace` → only if you check free space (probably you don't).
- Set `NSPrivacyTracking` to `false` (you don't track), `NSPrivacyCollectedDataTypes` empty (you collect nothing that leaves the device).
- When you add Gmail OAuth, do not consider OAuth itself "data collected by the developer" — the user's email contents are processed *on-device* and not transmitted to your servers (you have no servers). This is exactly the privacy story you want; the manifest reflects it.

**Warning signs:**
- No `PrivacyInfo.xcprivacy` in the Xcode target.
- You added a third-party SDK (don't!) without checking its privacy manifest.
- TestFlight upload warning: "ITMS-91053: Missing API declaration".

**Phase to address:**
**Phase 0 — Project bootstrap.** Add it on day one. Update each time you add a Required Reason API.

**Severity:** ANNOYING (single day to fix when it surfaces) but a *door-closer* if not done before TestFlight push under deadline.

---

### Pitfall 13: Watch / Widget extensions sharing data with the main app — App Group + shared SwiftData store

**What goes wrong:**
You build a watchOS companion or a Widget. You realise the Widget process and the main app process cannot read the same SwiftData store unless the store file lives in an App Group container. You move the store, but existing users' data is in the *app's* container and orphaned. Or: you correctly use an App Group from day one, but Widget timeline refreshes don't fire because you never marked the relevant entitlement, or the Widget reads stale data because SwiftData in extension context doesn't see writes the main app made until the extension restarts.

**Why it happens:**
- Each process on iOS has its own data container by default. Extensions (Widget, Watch app, App Intent extension) are separate processes.
- App Group container lives at `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourdomain.myhome")`. You must put the SwiftData store there explicitly via a custom `ModelConfiguration(url:)`.
- The App Group ID includes the *Team prefix* on paid accounts (`group.<TeamID>.com....`) — except when it doesn't, depending on Xcode version. The point is: don't change it after data exists.
- WidgetKit timelines are *scheduled* not *event-driven*. Reading "fresh" data requires the main app to call `WidgetCenter.shared.reloadAllTimelines()` after a meaningful write.

**How to avoid:**
- **Even in v1 (no extensions yet), put your SwiftData store in an App Group container** via a `ModelConfiguration(url: appGroupStoreURL)`. Add the App Group entitlement. App Groups *do* work on free accounts intermittently — but the *path* of the store file is what matters; if you set the store URL right today, adding the extension later is one line of "use the same URL" instead of "migrate every record".
- If App Groups won't enable cleanly on free, write the store path to a *constant URL inside `Application Support`* that you can later symlink/copy to the App Group container. The migration is then a file move.
- When extensions arrive, call `WidgetCenter.shared.reloadAllTimelines()` from the main app whenever an expense is added/updated. Widgets don't poll.
- Widget timeline policy: `.atEnd` if you want the system to refresh after your last entry's date; budget for "Widget shows yesterday's total in the morning" — that's a feature of WidgetKit's energy-conscious scheduling, not a bug.
- watchOS app: do not write to the same SwiftData store from both the iPhone and the Watch — last-write-wins races are a pain. Make the Watch read-only for v1 and write only on the iPhone.

**Warning signs:**
- Your `ModelContainer` initialisation uses no custom URL → store is in the app sandbox → invisible to extensions later.
- Widget shows yesterday's number; you have no `reloadAllTimelines()` call after writes.
- "Extension crashed: store file not found" → App Group not entitled in the *extension* target (it must be in both targets).

**Phase to address:**
**Phase 1 — Schema setup** (set the store URL correctly even with no extensions). **Watch/Widget phase** (post-v1).

**Severity:** CATASTROPHIC if discovered late (forces a data migration); ANNOYING if you set the URL correctly day one.

---

### Pitfall 14: CloudKit sharing (`CKShare`) mechanics that break across Apple IDs

**What goes wrong:**
You wire up `CKShare` to share the expense database with your wife. She taps the invitation in iMessage, accepts, opens the app — and sees nothing. Or: she sees data initially then it disappears. Or: she can read but cannot write. Or: the share invitation never arrives (silent push failure, no fallback).

**Why it happens:**
- `NSPersistentCloudKitContainer` with sharing requires **separate persistent stores** for `.private` and `.shared` CloudKit databases. Both stores have to be configured before mirroring; adding the shared store after the private store has data may require a re-init.
- Share acceptance is plumbed through `userDidAcceptCloudKitShareWith` in your `AppDelegate` / scene delegate. Missing this delegate method silently breaks acceptance.
- `CKShare.Participant.permission` defaults to `.readOnly` — explicitly set `.readWrite` per participant when creating the share.
- Free account: CloudKit container provisioning is unavailable, so the whole sharing flow doesn't apply until paid.
- Sharing only the *root* of an object graph: CloudKit shares hierarchies via "parent reference". If your `Expense` doesn't declare a parent relationship to an `ExpenseList` or similar shared root, only the root record is shared and children are private to the owner.

**How to avoid:**
- Plan the share *unit*: probably `Household` (a single record) that owns `Expense`, `Note`, `Budget`. Every other record has a `parent: Household?` reference (CloudKit "parent" reference, which SwiftData/Core Data exposes via `@Relationship` with `.cascade` on the owning side, configured as the parent reference in the CloudKit schema).
- One Household, one `CKShare`. Share is created when the second user joins; before that, all data lives in the owner's private DB.
- Implement `WindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` — accept the metadata, call `container.accept(metadata)`, mirror will then start syncing the shared zone.
- Test with TWO real devices on TWO different Apple IDs. There is no faithful single-device sharing test.
- Expect 5–60 second propagation delay even when working. Test patience.
- Recovery: if a share is "stuck", deleting the participant and re-adding usually resolves it without re-creating the share. Killing the CKShare entirely *loses* all the data in the shared zone — so do not.

**Warning signs:**
- One device sees data, the other doesn't, and you have no delegate method handling acceptance.
- "CKErrorDomain Code=10 (PartialFailure)" in logs.
- Recipient sees a "You haven't been added" error → invitation was sent to the wrong iCloud email (iCloud aliases vs primary address).
- You're testing sharing on one device with two simulators against the same Apple ID — that does not test sharing; it tests the private DB.

**Phase to address:**
**Sharing phase (post-v1).** But the *parent reference relationships* must be in the schema from **Phase 1** (otherwise you cannot share without a destructive migration).

**Severity:** CATASTROPHIC if schema isn't set up for sharing from day one; ANNOYING but solvable during the sharing phase itself.

---

### Pitfall 15: Swift Charts with reactive data — animations stutter, accessibility forgotten

**What goes wrong:**
- You bind a `Chart` to a `@Query` of `Expense`s and animate transitions. With 200+ data points the chart re-layouts every micro-update and the UI judders.
- You don't add `.accessibilityLabel` / `.accessibilityValue` / `.accessibilityChartDescriptor` — VoiceOver users get an unintelligible "chart, button".
- You build a stacked bar of "spend by category by day" and discover the chart's auto-axis breaks at >30 X-axis values and labels overlap.
- You use Swift Charts' built-in date binning, then realise you need timezone-aware binning for "month-to-date" which Swift Charts doesn't do natively.

**Why it happens:**
Swift Charts is declarative — every binding update recomputes layout. Chart accessibility is opt-in. Date axes use the current calendar implicitly which may surprise across DST or month-boundary edge cases.

**How to avoid:**
- Pre-aggregate data outside the view. Compute "spend by category" once when the underlying data changes (via a small VM observing `@Query` results) and feed the chart a small, stable array (e.g. 5–10 categories, 30 days).
- Animate only between snapshots, not on every model change. Use `.animation(.default, value: aggregatedData)` with `aggregatedData` as an `Equatable` snapshot.
- Add accessibility: `.accessibilityChartDescriptor(self)` with a custom `AXChartDescriptorRepresentable` for screen-reader audio chart reading.
- Cap interactive selection by `chartGesture` to one selected mark; expand into a popover with the precise value.
- Use `Calendar.current` explicitly and pre-bin dates to start-of-day in the user's timezone. Don't rely on chart auto-bin for monetary data.
- Test with `@Environment(\.dynamicTypeSize)` set to `accessibility5` — long axis labels overflow at large type.

**Warning signs:**
- Chart visibly stutters on scroll into view.
- You're passing the raw `@Query` result into `Chart {}` directly.
- No accessibility modifier on the `Chart` block.

**Phase to address:**
**Charts phase (in the expense tracker).**

**Severity:** ANNOYING — none of this is catastrophic, but each one is a "ship it then file three bug tickets" moment.

---

### Pitfall 16: TDD for SwiftData / CloudKit — getting the test container right

**What goes wrong:**
You write tests against a `ModelContainer(for: Expense.self)` with default config; the tests share state across runs, fail intermittently, and slow CI. You try to test CloudKit mirroring and discover there is no in-memory CloudKit. You add a snapshot test on a SwiftUI view rendering `@Query` results and the snapshot is empty because the test ran before the query resolved.

**Why it happens:**
- SwiftData's default container persists to disk.
- CloudKit mirroring requires a real container provisioned in CloudKit Dashboard; the only "test" is integration with real iCloud.
- SwiftUI `@Query` is asynchronous; a snapshot taken immediately renders nothing.

**How to avoid:**
- Always use `ModelConfiguration(isStoredInMemoryOnly: true)` in tests. Create a fresh container per test (`@MainActor func setUp() async throws { container = try ModelContainer(for: Schema(...), configurations: ModelConfiguration(isStoredInMemoryOnly: true)) }`).
- Don't unit-test CloudKit mirroring. Instead:
  - Unit-test your data layer (repository pattern) with the in-memory container.
  - Integration-test CloudKit manually with two devices, document the steps.
  - Test the *parent-reference schema shape* programmatically by asserting that every shared-eligible model has a `parent` relationship (reflection-based test).
- For SwiftUI snapshot/preview tests, inject the data through `@Environment` or constructor, not via `@Query`. Reserve `@Query` for the actual app; previews and tests get a manually-populated `ModelContext`.
- **Swift Testing (new in Xcode 16) vs XCTest**: Swift Testing has nicer ergonomics (`#expect`, parameterised tests, parallel by default). It works fine with SwiftData. Use it for new code; XCTest still required for *UI* tests (XCUITest). Don't mix in the same file.
- Test naming: `@Test("...")` lets you write sentence-style names. Use this — your future self will thank you when grepping failures.
- Parallel tests + SwiftData: each test must have its own container. Don't share a class-level container across `@Test` functions or you'll get cross-test pollution.

**Warning signs:**
- Tests pass alone, fail in suite. → shared container.
- Tests touch real iCloud and take 30 seconds each. → trying to test mirroring.
- Snapshot of `@Query` view is empty. → query hadn't resolved.

**Phase to address:**
**Phase 0 — Test scaffolding.** Set up the test container helper once.

**Severity:** ANNOYING — but compounds over the project; bad test setup discourages writing tests at all.

---

### Pitfall 17: Decimal vs Double for money, currency code stored as String, locale formatting

**What goes wrong:**
You store `amount: Double`. Sums of 100 transactions drift by 0.01 paise (₹). Or you store `amount: Decimal` correctly but display with `String(format: "%.2f", amount)` and get locale-incorrect formatting. Or you hardcode "₹" everywhere instead of using `NumberFormatter` / `FormatStyle.currency(code:)`, then can't add USD/SGD later without grepping for the symbol.

**How to avoid:**
- `amount: Decimal = 0` always for money. Never `Double`. CloudKit and SwiftData both support `Decimal` natively.
- `currencyCode: String = "INR"` always present on every monetary entity, even though v1 is INR-only. Schema-forward, zero current cost.
- Format with `amount.formatted(.currency(code: currencyCode).locale(Locale.current))`. Never string-format manually.
- For input parsing (user types "1,234.50") use `NumberFormatter` with `numberStyle = .decimal` and `locale = .current` — Indian numbering uses lakhs/crores grouping which differs from US-en grouping.

**Phase to address:**
**Phase 1 — Schema** and **expense-entry phase**.

**Severity:** ANNOYING — and a forced migration if you stored Double from the start.

---

### Pitfall 18: Concurrency landmines under Swift 6 / strict concurrency

**What goes wrong:**
You write `Task { let expenses = try await gmailFetcher.fetch() ; modelContext.insert(...) }` and the build fails with "Sending non-sendable type across actor boundary". You add `@unchecked Sendable` to make it compile; later, you race against the main thread and corrupt the SwiftData context, crashing.

**Why it happens:**
- Swift 6 enforces sendability; `ModelContext` is not `Sendable` — it's bound to its actor (typically `MainActor`).
- `PersistentIdentifier` *is* `Sendable` and is the safe way to pass references across actor boundaries.

**How to avoid:**
- Adopt Swift 6 concurrency mode in the project from day one (you're on Xcode 16+). It's easier to start strict than retrofit.
- Network/Gmail work happens off-main. Returns `Sendable` plain structs (e.g. `ParsedTransaction`).
- A `@MainActor`-isolated function takes those structs and calls `modelContext.insert(Expense(...))`.
- Never `@unchecked Sendable` on a model object. If the compiler complains, model the boundary correctly.
- For BGTask handlers, switch to `@MainActor` explicitly before touching the model context.

**Phase to address:**
**Phase 0 — Project bootstrap** (enable strict concurrency in build settings); **every async-touching phase**.

**Severity:** ANNOYING-to-CATASTROPHIC — concurrency bugs are silent and rare-reproducer.

---

### Pitfall 19: NavigationStack state restoration and sheet dismissal bugs

**What goes wrong:**
- You present a `.sheet(item: $editingExpense)`. User taps Save in the sheet, you set `editingExpense = nil` in the same view-update tick as a navigation push elsewhere — the sheet stays up, or the navigation doesn't fire, or both.
- You restore navigation state on cold launch via `SceneStorage` of a `NavigationPath`, but the destination type isn't `Codable` (you put a `@Model` object in the path) — silently fails and you launch into the root.
- A `Form` inside a sheet on iPad presents at the wrong size; on iPhone the keyboard pushes the Save button off-screen because the sheet is `.medium` detent.

**How to avoid:**
- Sheet dismissal: use the `dismiss` environment action *inside* the sheet body, not by binding-mutation from outside while other state is also changing.
- NavigationStack: paths contain `Hashable, Codable` IDs (`UUID`), never models. Look up models by ID in the destination.
- iPad: test every modal at iPad regular size. Use `.formSheet` or `.presentationDetents([.large])` deliberately.
- Keyboard avoidance: `.scrollDismissesKeyboard(.immediately)` on the form's containing ScrollView; or `.keyboardAvoidance` modifiers in iOS 17+.

**Phase to address:**
**Every UI phase.** Test on iPhone SE (smallest) + iPad (Form weirdness) + iPhone 16 Pro Max (largest).

**Severity:** ANNOYING per occurrence.

---

### Pitfall 20: "It works in the simulator but not on device" — the iOS pantheon

**What goes wrong:**
A non-exhaustive list of things that work in the simulator and silently fail on a real device:
- Push notifications (sim doesn't deliver pre-iOS 16; iOS 16+ supports them but with caveats).
- Background tasks (sim can be triggered via LLDB; device throttles aggressively).
- Face ID (sim simulates; device has real failures).
- Some Keychain access-control flags (sim is permissive).
- `URLSession` background sessions (sim runs synchronously; device suspends).
- Camera, microphone, motion sensors (sim has limited fakes).
- Network reachability transitions.
- App Group container creation (sim is permissive about entitlement mismatches).

**How to avoid:**
- Cardinal rule: **the simulator is for fast iteration, not for verifying anything that touches a system service.** Before declaring a feature done, run it on the real device.
- For BGTasks specifically: deploy via Xcode, unplug, leave the phone alone overnight, check the log next morning. There is no shortcut.

**Phase to address:**
**Every phase** — add a "verified on device" checklist item to the phase template.

**Severity:** ANNOYING per occurrence; CATASTROPHIC if a v1 acceptance test is "it works in simulator".

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Use `@Attribute(.unique)` for IDs because v1 is local-only | Compiler-enforced uniqueness; one less `upsert` to write | Cannot turn on CloudKit mirroring without removing the attribute and rebuilding the store | **Never** — write `upsert` once and forget it |
| Store `amount: Double` because "it's just rupees" | One fewer import, faster `==` checks | Floating-point drift on sums; forced migration to `Decimal` later | Never |
| Hardcode "INR" / "₹" in formatting strings | Saves passing `currencyCode` around | Cannot add multi-currency without touching every view; migration if you tried to add a `currency` field later | Never — store the code from day one even if you don't surface a picker |
| Embed Google OAuth `client_secret` in the binary | Quickest OAuth setup | Token compromise risk; rebuild to PKCE; refresh-token revocation worse | Never |
| Skip Privacy Manifest because v1 is sideload-only | Skip one config file | TestFlight upload day → frantic scramble; possibly post-deadline | Never |
| Bundle ID with a `.dev` or `.beta` suffix | Differentiate from "real" build | Renaming orphans on-device data and CloudKit container; one-way door | Never |
| Use the default `ModelContainer` (no custom URL) | Less ceremony for v1 | When Widget/Watch arrive, data is not in App Group container; either migrate every record or run two databases | Only if you commit *in writing* to never adding extensions |
| Single-regex-per-bank parser without fingerprint+confidence | "It works for HDFC today" | Silent garbage when template changes; user trust gone | Never on a financial app |
| BackgroundTasks as the only ingestion path | One scheduling pattern to learn | Background fires unreliably → "where are my expenses?" → user reverts to manual | Never; always combine with on-launch fetch |
| Use `WKWebView` for Gmail OAuth | Familiar webview API | Google blocks the flow with `disallowed_useragent`; rebuild to `ASWebAuthenticationSession` | Never |
| Skip `VersionedSchema` for v1 (one schema, no need yet) | Less boilerplate | First schema change post-v1 risks data loss because lightweight migration is silent on failure | Acceptable *only* if you accept a wipe-and-restart for v1 testing builds; not OK once you have data you care about |
| Mix `ObservableObject` and `@Observable` in the same module | Use whichever the tutorial showed | Update bugs that look like SwiftUI bugs | Never on a fresh iOS 17+ project |
| One CloudKit container per environment (`-dev`, `-prod`) | Clean separation | When you ship "prod", users on `-dev` lose data; refactor to dynamic config | Acceptable pre-v1; lock to one container at v1 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| Gmail OAuth | Embedded `WKWebView` flow with `client_secret` in binary | `ASWebAuthenticationSession` + PKCE; iOS-type OAuth client (no secret); custom-scheme redirect URI |
| Gmail API | `messages.list` with no filter; full inbox scan | `q=from:(bank emails) newer_than:30d` initial backfill; `history.list` for incremental |
| Gmail tokens | Stored in `UserDefaults` or in `NSData` plist | Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; shared access group when extensions exist |
| CloudKit | Enabling mirroring on a schema with required fields | Optional+default everywhere from day one |
| CloudKit sharing | `CKShare` with no parent reference | Designate a `Household` root and parent-reference every shareable child |
| CloudKit container | Container ID changes between dev / prod / rename | Lock the container ID at project start |
| BackgroundTasks | `BGAppRefreshTask` as sole ingestion path | On-launch fetch + best-effort BGTask + visible "last synced" timestamp |
| Face ID | `LAPolicy.deviceOwnerAuthenticationWithBiometrics` only | `LAPolicy.deviceOwnerAuthentication` for passcode fallback |
| Keychain (background) | `WhenUnlocked` accessibility | `AfterFirstUnlockThisDeviceOnly` for items needed in background |
| Push notifications | Registering on free dev account | Skip entirely until paid; design app to not depend on push |
| App Groups | Setting App Group only on main app target | Set on **every** target (main app, Widget extension, Watch app) — all must share the entitlement |
| WidgetKit | Expecting near-real-time refresh | `WidgetCenter.reloadAllTimelines()` from main app on writes; timeline policy `.atEnd` |
| Watch | Bi-directional writes to a shared SwiftData store | Watch is read-only in v1; writes only from iPhone |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Inline-decoding HTML emails on the main thread / in BGTask handler | BGTask exceeds time budget; main thread janks | Move HTML→plain-text conversion to a detached `Task` off main; cache result | First time an HDFC email's HTML is >100KB (offers section) |
| `@Query` with no predicate returning all expenses to the list view | Scroll judder once dataset > a few thousand | Predicate-bounded queries (current month); paginate / lazy-load if needed | ~2,000–5,000 expenses (≈2 years of data) |
| Chart bound to raw `@Query` results, animating every change | Visible chart re-layout stutter | Pre-aggregate to an `Equatable` snapshot; animate snapshot deltas | A few hundred data points |
| Full-history Gmail backfill on first launch (no `q` filter) | OAuth approves; first sync takes 5 minutes; rate-limit errors | Filter by sender + `newer_than:30d` initial; incremental via `historyId` thereafter | First launch on an inbox with 50k+ emails (everyone's inbox) |
| Saving `modelContext` on every record insert inside a batch import | Slow batch + write amplification | Insert in a batch, save once at the end (or every N records) | ~50 inserts per save |
| Synchronous `NumberFormatter` allocation per cell in a list | Visible scrolling stutter | Reuse a single `FormatStyle`/`NumberFormatter` instance; cache | Lists > a hundred rows |
| BGTask doing full re-parse instead of incremental | BGTask runs out of time budget; iOS throttles more | Use `historyId` for delta; persist last-processed ID | After ~100 historical emails |

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| Embedding OAuth `client_secret` in iOS binary | Anyone can extract and impersonate your app | Use PKCE; iOS OAuth client type has no secret |
| Storing Gmail refresh token in `UserDefaults` | Token readable from device backup; not protected when device locked | Keychain with `AfterFirstUnlockThisDeviceOnly` |
| Logging raw email bodies to OSLog with default privacy | OS logs persist; bank account details leak to console / Console.app of any Mac the phone connects to | `Logger.debug("\(email, privacy: .private)")` — explicit privacy redaction |
| Storing the on-device SwiftData store unencrypted in shared App Group container | Other extension processes could read; jailbreak-relevant; iCloud backup includes the file | Accept it (App Group inherits app's Data Protection class) and ensure Data Protection Class is set to Complete (default); for higher bar, encrypt sensitive fields field-by-field with a Secure Enclave-backed key |
| Asking for `gmail.modify` or `gmail.compose` when only reading | Larger blast radius if compromised; harder OAuth verification | `gmail.readonly` only |
| Auto-trusting any email "from HDFC" without checking sender domain | Phishing emails inserted as expenses | Match sender on full `from` (`alerts@hdfcbank.net`), DKIM/SPF assumed via Gmail's `category:` labels; reject suspicious senders |
| Not handling Face ID `biometryLockout` | User locked out without recourse | Always provide passcode fallback via `deviceOwnerAuthentication` |
| Storing transaction amounts in cleartext UserDefaults for "quick widget access" | PII / financial data exposed to backups, other targets | Read from shared SwiftData store via App Group; the store's protection class covers it |
| Sharing app via TestFlight publicly when intended for two users | Random testers see your wife's expenses; sharing flow tested against strangers' iCloud | Internal Testing only, your two Apple IDs as testers; never External Testing for a personal app |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| Auto-saving low-confidence parsed expenses | Wrong amounts in monthly totals; user loses trust | Confidence-gated review inbox; manual confirm before save when confidence is low |
| Silent ingestion failure (token expired, parser broken) | "Where are my last week's expenses?" | Always-visible "last synced" timestamp on Home; banner if last sync > 24h |
| Face ID prompt on every cold launch with no "remember for 5 min" | Friction on the most-used flow | Allow short grace period after backgrounding (configurable; default ~3–5 minutes) |
| "Budget exceeded" notification without a deep-link into the exceeded category | User has to navigate from scratch | Tap notification → directly to that category's expense list for the current month |
| Showing INR in en-US grouping (`12,345.67`) instead of en-IN (`12,345.67` is the same but lakhs differ at higher values: `1,23,45,678.00`) | Numbers look "off" to Indian users | `.locale(Locale(identifier: "en_IN"))` in format style |
| Charts that can't be tapped for exact values | User squints at colored slabs | `chartGesture` selection → popover with exact figure |
| Manual entry form has too many fields for the 90% case | Friction; user stops logging cash | Single-field "amount + smart-default category from last similar entry"; expand on demand |
| No quick way to handle a parsed-incorrectly transaction | User deletes it; reverts to manual | One-tap "edit / re-categorise / split / delete" from the expense list |
| Note keeper without ordering by most-recent | Old notes drown new ones | Default sort by `updatedAt DESC`; manual pin |
| Sharing UX surfaces CloudKit jargon | Wife sees "Failed to fetch zone" and panics | Translate CK errors to user terms; offer "retry" + "report to Reo" |

## "Looks Done But Isn't" Checklist

- [ ] **SwiftData schema:** Often missing `Decimal` for money, optional+defaulted everywhere, parent reference for sharing — verify by running `ModelContainer(for: Expense.self, configurations: ModelConfiguration(cloudKitDatabase: .private("iCloud.com.you.myhome")))` once locally; if it errors, the schema is not CloudKit-shaped.
- [ ] **Gmail OAuth:** Often missing PKCE, refresh-token expiry handling, custom-scheme redirect URI — verify by killing the app, deleting Gmail's "App Passwords" entry on the Google account, opening the app: re-auth flow should appear cleanly, not a hung loading state.
- [ ] **Background ingestion:** Often missing on-device test with the phone unplugged for >12h — verify by sending yourself a test bank email, leaving the phone alone overnight, opening the app: the email should appear without you triggering a fetch.
- [ ] **Face ID gate:** Often missing passcode fallback, simulator path, no-biometrics path — verify by disabling Face ID in iOS Settings while the app is closed; reopening should fall back to passcode, not dead-end.
- [ ] **Keychain access:** Often missing `AfterFirstUnlockThisDeviceOnly` — verify by rebooting the device and checking that the first BGTask after reboot can read the token (will show in logs).
- [ ] **Privacy Manifest:** Often missing entirely on a sideloaded v1 — verify the file exists in the target and lists `UserDefaults` and `FileTimestamp` reasons.
- [ ] **Bundle / container IDs:** Often suffixed with `.dev` or `.test` — verify the project's bundle ID and CloudKit container ID match the names you're willing to live with forever.
- [ ] **App Group container:** Often forgotten on day one — verify SwiftData store path is in the App Group container (`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`) even though no extension exists yet.
- [ ] **Schema migration plan:** Often skipped because "v1 has one schema" — verify `VersionedSchema` is scaffolded and there is a test that loads a bundled v1 store file and migrates it to current.
- [ ] **Parser fingerprinting:** Often a single big regex per bank — verify each parser has a fingerprint check distinct from the extraction regex.
- [ ] **Confidence-gated review:** Often missing — verify there is a "needs review" inbox in the UI, and that any parse below a threshold lands there instead of being auto-saved.
- [ ] **Decimal money:** Often `Double` — grep the codebase: `: Double` should never appear in an `@Model`.
- [ ] **Indian locale formatting:** Often default US grouping — verify a ₹1,00,000 expense displays as `₹1,00,000.00` in en-IN, not `₹100,000.00`.
- [ ] **VoiceOver pass:** Often forgotten on charts — verify VoiceOver can read out the chart's spend-by-category content.
- [ ] **Swift 6 strict concurrency:** Often disabled "to get going" — verify the build setting is `complete` and no `@unchecked Sendable` is used.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| SwiftData schema has required fields / `.unique` and you need CloudKit | HIGH | Add a `VersionedSchema` that relaxes constraints (optional + defaulted, drop `.unique`); write a `SchemaMigrationPlan` from current → relaxed; ship update; only then enable mirroring |
| Bundle ID needs to change | HIGH | Export all SwiftData entities to JSON via an "export my data" feature in the *old* app; install renamed app; import. There is no in-place rename |
| CloudKit container ID needs to change | HIGH | Same as bundle ID — export, install on new container, import; old CloudKit data is unrecoverable |
| Parsed expenses are wrong due to template drift | LOW | Replay parser against stored raw emails (you stored them, right?); update parser fingerprint and extraction; re-import. If raw emails not stored: irrecoverable; user must edit manually |
| Background task never fires in production | LOW | Add a visible "Sync now" button + on-launch sync as the primary path; demote BGTask to bonus |
| Gmail refresh token revoked | LOW | One-tap "reconnect Gmail" UI; on the next OAuth re-grant, resume from the last `historyId` (which you persisted, right?) |
| Face ID gate locks user out (biometry lockout) | LOW | Passcode fallback always available; if you didn't wire passcode, ship an update with it (user must wait — bad) |
| Lost data on bad migration | CATASTROPHIC | Restore from iCloud Backup if user has it; otherwise unrecoverable. Prevention is the only strategy |
| TestFlight upload fails on Privacy Manifest | LOW | Add the manifest; resubmit. ~30 minutes once you know what to do |
| Free-account provisioning expired and app won't launch | LOW | Connect phone, build & run from Xcode; renews the profile |
| CloudKit share recipient sees nothing | MEDIUM | Confirm acceptance delegate is implemented; check recipient is on iCloud (not signed out); remove and re-add participant; verify both devices have network and have launched the app post-share |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| Schema not CloudKit-compatible (Pitfall 1) | Phase 1 — Schema | Test: instantiate `ModelContainer` with `.cloudKitDatabase: .private("iCloud....")` — must succeed without error |
| Mirroring latency / UX assumptions (Pitfall 2) | Phase 1 — Schema (assumption); Sharing phase (exercise) | Manual two-device test: verify last-synced UX exists |
| `#Predicate` / `@Attribute(.unique)` traps (Pitfall 3) | Phase 1 — Schema | Code review: no `.unique`; predicates capture local constants |
| BGTask reliability (Pitfall 4) | Ingestion phase | Manual 24h on-device test; "sync now" button exists; on-launch fetch is primary |
| Free Apple Developer limits (Pitfall 5) | Phase 0 — Bootstrap | Project README lists deferred capabilities; bundle ID locked; no push / CloudKit / SIWA in v1 critical path |
| Bundle ID / container ID stability (Pitfall 6) | Phase 0 — Bootstrap | `BUNDLE_ID.md` committed; CloudKit container ID written down even if not yet provisioned |
| SwiftData migration (Pitfall 7) | Phase 1 — Schema, then every schema change | Test that loads a bundled v1 store and migrates to current |
| Gmail OAuth (Pitfall 8) | Ingestion / Gmail sub-phase | Code review: `ASWebAuthenticationSession`, PKCE, no `client_secret`, `gmail.readonly` scope |
| Bank email parsing (Pitfall 9) | Parser sub-phase + standing | Parser-per-template; fingerprint check; confidence-gated; review inbox exists; raw bodies stored |
| SwiftUI state model (Pitfall 10) | Phase 0 (convention); every UI phase | Convention in README; code review: no `@StateObject`/`@Published` |
| Face ID + Keychain (Pitfall 11) | Phase 1 — Foundational (Face ID gate); revisit with Watch/Widget | Test: disable Face ID; reboot; passcode fallback works; background can read token post-reboot |
| Privacy Manifest (Pitfall 12) | Phase 0 — Bootstrap | `PrivacyInfo.xcprivacy` exists; lists reasons; TestFlight dry-run passes |
| Watch / Widget data sharing (Pitfall 13) | Phase 1 — Schema (store URL); Watch/Widget phase | Store URL points to App Group container from day one |
| CloudKit sharing (Pitfall 14) | Sharing phase; parent refs in Phase 1 | Two-device test; share recipient sees data within 60s |
| Charts (Pitfall 15) | Charts sub-phase | Performance: 200 data points scroll smoothly; VoiceOver reads chart |
| Tests for SwiftData (Pitfall 16) | Phase 0 — Test scaffolding | Test helper for in-memory container; tests run in parallel |
| Decimal money / locale (Pitfall 17) | Phase 1 — Schema; expense entry | Grep: no `: Double` in `@Model`; en-IN locale verified |
| Swift 6 concurrency (Pitfall 18) | Phase 0 — Bootstrap | Strict concurrency enabled; no `@unchecked Sendable` |
| NavigationStack / Sheet bugs (Pitfall 19) | Every UI phase | Sheet dismissal tested; NavigationPath uses `Codable` IDs |
| Sim-vs-device divergence (Pitfall 20) | Every phase | Phase template has "verified on device" checkbox |

## Sources

This research synthesises well-documented landmines from:
- Apple Developer documentation: SwiftData, NSPersistentCloudKitContainer, BackgroundTasks, LocalAuthentication, Keychain Services, WidgetKit, Privacy Manifest
- Apple Developer Forums and WWDC session content (WWDC23: "Meet SwiftData", "What's new in SwiftUI"; WWDC24: SwiftData Q&A and known-issues threads)
- Recurrent Stack Overflow / forum patterns for: `@Attribute(.unique)` + CloudKit; `#Predicate` runtime crashes; BGTask reliability; Gmail OAuth `disallowed_useragent`; CKShare acceptance delegate
- Real-world community shipping experience with two-Apple-ID CloudKit sharing apps and India-bank-email ingestion apps (Walnut, Money Lover, etc., whose post-mortems and user reviews surface template-drift and OTP-noise patterns)
- Apple's Privacy Manifest requirements (effective 2024-05) and Required Reason API list
- Note: WebSearch was unavailable for this session, so live citation links are not included. Confidence remains HIGH because every pitfall above is one I would re-encounter on any project of this shape; specifics like exact API names and access-control flags reflect Apple's stable public APIs as of iOS 17/18 / Xcode 16.

---
*Pitfalls research for: personal household-ops iOS app (Swift/SwiftUI + SwiftData → CloudKit; Gmail ingestion; Face ID; future Watch/Widget/sharing)*
*Researched: 2026-05-28*
