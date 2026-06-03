---
phase: quick-260603-lvt
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - MyHomeApp/Persistence/Schema/SchemaV5.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Persistence/Models/Expense.swift
  - MyHomeApp/Persistence/Models/Category.swift
  - MyHomeApp/Features/Gmail/GmailAccountStore.swift
  - MyHomeApp/Features/Gmail/GmailSyncController.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
  - MyHomeTests/GmailSyncControllerTests.swift
  - MyHomeTests/MultiAccountGmailTests.swift
autonomous: true
requirements: [MULTI-ACCT]
must_haves:
  truths:
    - "A second Gmail can be added without disconnecting the first"
    - "sync() refreshes + fetches every connected account in one run"
    - "An expired token on one account does not abort sync for the others"
    - "Dedup idempotency is scoped to (account, messageID), not messageID alone"
    - "An already-connected single account survives the upgrade with no re-auth"
    - "Each Settings account row has its own last-synced + disconnect; an overall Sync now syncs all"
    - "BGAppRefreshTask drives the multi-account sync loop"
  artifacts:
    - path: "MyHomeApp/Features/Gmail/GmailAccountStore.swift"
      provides: "Per-account state model + connected-accounts list + legacy forward-migration"
    - path: "MyHomeApp/Persistence/Schema/SchemaV5.swift"
      provides: "Expense.sourceAccount field for account-scoped persistence"
    - path: "MyHomeApp/Features/Gmail/GmailSyncController.swift"
      provides: "Multi-account signIn (add account) / sync (loop) / signOut(account)"
  key_links:
    - from: "GmailSyncController.sync"
      to: "GmailAccountStore.accounts"
      via: "per-account refresh + fetch loop"
      pattern: "for .* in .*accounts"
    - from: "GmailSyncController.signIn"
      to: "fetch.getProfile"
      via: "learn email before storing under account key"
      pattern: "getProfile"
    - from: "Expense.sourceAccount"
      to: "dedup guard"
      via: "(account,messageID) idempotency"
      pattern: "sourceAccount"
---

<objective>
Refactor GmailSyncController from single-account to multi-account. Today one Keychain key
(`refresh_token`), one `gmail_connected_email`, and one in-memory access token mean onboarding a
second Gmail clobbers the first. This plan introduces a per-account state model keyed by the
account's email, makes `signIn()` an "add account" operation, makes `sync()` loop over all
connected accounts (one expired account must not abort the others), scopes the dedup idempotency
guard to `(account, messageID)` via a new persisted `Expense.sourceAccount` field (SchemaV4→V5),
rebuilds the Settings Gmail section as a per-account list, and forward-migrates the existing
single-account stored state so the already-connected Gmail survives the upgrade with no re-auth.

Purpose: The user is already signed in to one Gmail and wants to add a second (e.g. a personal +
a shared household account) without losing the first or double-ingesting.
Output: Multi-account GmailSyncController, GmailAccountStore, SchemaV5 + migration, multi-account
Settings UI, updated + new tests, green build.

Design decisions (implementer discretion per task brief — documented here):
- D-MA-01 Account identity = the Gmail address from `GmailFetchPort.getProfile`, lowercased. It is
  the natural per-mailbox key; Gmail message IDs are unique within a mailbox, so the dedup guard
  must combine it with the email.
- D-MA-02 Keying scheme: refresh token in Keychain under `refresh_token_<email>` (one item per
  account, preserving SEC-03 attributes). Per-account metadata (expiry, lastSynced, reconnect-needed)
  in App Group UserDefaults under a single Codable dictionary value keyed by email
  (`gmail_accounts_v2`). The list of connected emails is derived from that dictionary's keys.
- D-MA-03 Persist owning account on Expense (new `sourceAccount: String?`). Required because the
  idempotency guard is rebuilt from existing expenses on every sync; an in-memory-only set would not
  survive launches and could not distinguish identical message IDs from two mailboxes. This forces a
  schema bump SchemaV4→V5 (additive optional field, CloudKit-ready, .custom migration — same
  discipline as v3ToV4). DedupChecker (amount+merchant+date) stays global and unchanged.
- D-MA-04 Access tokens stay in-memory only (D6-07), now held per-account in an in-memory dictionary.
  refresh tokens stay Keychain-only with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (SEC-03).
- D-MA-05 UI shape: one row per account (email + last-synced + per-account Reconnect/Disconnect),
  an "Add account" button, and one overall "Sync now" that syncs all.
- D-MA-06 Legacy-expense dedup backfill (CAVEAT — added 2026-06-03 before execution). Expenses
  ingested by the shipped single-account build carry `sourceAccount = nil`. The new (account,
  messageID) idempotency set is rebuilt from existing expenses, so nil-source legacy rows would NOT
  be recognized on the FIRST multi-account sync — risking re-fetch + a possibleDuplicate flag on
  every previously-ingested email (no silent double-count: the global amount+merchant+date
  DedupChecker still catches them — just review-inbox noise). Mitigation, do BOTH:
  (a) In `migrateLegacyIfNeeded()` (Task 2): after seeding the migrated account, backfill
      `sourceAccount = <migrated email>` on every existing Expense that has a non-nil
      `gmailMessageID` and a nil `sourceAccount`. This requires the migration to run with a
      ModelContext available (or be invoked once on first sync when the context exists) — if no
      context is reachable at init, defer the backfill to the first `syncAccount` run for the
      migrated email and guard it with the one-shot `gmail_multiacct_migrated_v2` flag.
  (b) In the Task 3 dedup guard: treat a nil-source existing expense as matching ANY account for
      its messageID (fallback to messageID-only membership when `sourceAccount == nil`), so even if
      the backfill has not yet run, a legacy-ingested email is not re-ingested. Exact-match on
      (account, messageID) still applies for rows that DO have a sourceAccount.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@MyHomeApp/Features/Gmail/GmailSyncController.swift
@MyHomeApp/Gmail/KeychainPort.swift
@MyHomeApp/Gmail/GmailAuthPort.swift
@MyHomeApp/Gmail/GmailFetchPort.swift
@MyHomeApp/Gmail/GmailOAuthConfig.swift
@MyHomeApp/Features/Settings/SettingsView.swift
@MyHomeApp/RootView.swift
@MyHomeApp/MyHomeApp.swift
@MyHomeApp/Persistence/Schema/SchemaV4.swift
@MyHomeApp/Persistence/Schema/MigrationPlan.swift
@MyHomeApp/Persistence/ModelContainer+App.swift
@MyHomeApp/Persistence/Models/Expense.swift
@MyHomeTests/GmailSyncControllerTests.swift
@MyHomeTests/IngestionPipelineTests.swift
@MyHomeTests/Support/SpyGmailFetch.swift
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: SchemaV5 — add Expense.sourceAccount for account-scoped dedup persistence</name>
  <files>MyHomeApp/Persistence/Schema/SchemaV5.swift, MyHomeApp/Persistence/Schema/MigrationPlan.swift, MyHomeApp/Persistence/ModelContainer+App.swift, MyHomeApp/Persistence/Models/Expense.swift, MyHomeApp/Persistence/Models/Category.swift</files>
  <behavior>
    - A container opened on an existing SchemaV4 store migrates to V5 without data loss (additive).
    - A new Expense has sourceAccount == nil by default (manual + legacy expenses).
    - `typealias Expense` / `typealias Category` resolve to SchemaV5 types and the app still builds.
  </behavior>
  <action>
    Create SchemaV5 as an additive superset of SchemaV4 per the project's VersionedSchema discipline
    (SchemaV4.swift header rules; never edit shipped V1–V4). Copy SchemaV4's four @Model types
    (Expense, Category, Note, NoteBlock) verbatim into a new `enum SchemaV5: VersionedSchema` with
    `versionIdentifier = Schema.Version(5, 0, 0)`. Add ONE new field to Expense:
    `var sourceAccount: String? = nil  // D-MA-03 — owning Gmail account email; nil for manual/legacy`.
    Keep CloudKit rules intact (optional/defaulted, no @Attribute(.unique), no stored enums).
    In MigrationPlan.swift append SchemaV5 to `schemas` (never remove V1–V4) and add a `v4ToV5`
    MigrationStage.custom(fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil,
    didMigrate: nil) — additive-only, .custom over .lightweight to sidestep FB13812722 (match the
    v3ToV4 rationale). Add v4ToV5 to `stages`. In ModelContainer+App.swift change
    `Schema(versionedSchema: SchemaV4.self)` to `SchemaV5.self`. Update the two typealiases in
    Persistence/Models/Expense.swift and Category.swift from SchemaV4 to SchemaV5. Leave all other
    files referencing `Expense`/`Category` (via typealias) untouched.
  </action>
  <verify>
    <automated>xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -20</automated>
  </verify>
  <done>Project builds against SchemaV5; AppMigrationPlan lists V1–V5 with a v4ToV5 stage; Expense has an optional sourceAccount field defaulting to nil.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GmailAccountStore — per-account state model + legacy forward-migration</name>
  <files>MyHomeApp/Features/Gmail/GmailAccountStore.swift, MyHomeTests/MultiAccountGmailTests.swift</files>
  <behavior>
    - addOrUpdate(email:) followed by addOrUpdate for a different email yields accounts.count == 2 (no clobber).
    - remove(email:) deletes only that account's metadata; other accounts remain.
    - Per-account expiry/lastSynced/needsReconnect round-trip through the Codable dictionary.
    - migrateLegacyIfNeeded(): given legacy `gmail_connected_email`="a@x.com" + a Keychain item under
      `refresh_token`, after migration: accounts contains "a@x.com", a Keychain item exists under
      `refresh_token_a@x.com`, the legacy `gmail_connected_email` key is cleared, and a one-shot
      migration-done flag prevents re-running. The legacy `refresh_token` item is left in place OR
      deleted only after the per-account copy is confirmed written (no window where the token is lost).
    - migrateLegacyIfNeeded() is a no-op when there is no legacy email or migration already ran.
    - D-MA-06(a): after migrating, existing expenses with a non-nil gmailMessageID and nil
      sourceAccount are backfilled to sourceAccount == <migrated email> (deferred to first sync if
      no ModelContext is reachable at init; still guarded by the one-shot migrated flag).
  </behavior>
  <action>
    Create `GmailAccountStore` (a plain struct/class, @MainActor not required — pure state, injectable
    UserDefaults + KeychainPort) implementing D-MA-02. Define a Codable `GmailAccount` value type
    { email: String; var accessTokenExpiry: Date?; var lastSyncedAt: Date?; var needsReconnect: Bool }
    persisted as a `[String: GmailAccount]` dictionary under UserDefaults key `gmail_accounts_v2`
    (JSON-encoded Data). Expose: `accounts -> [GmailAccount]` (sorted by email for stable UI ordering),
    `addOrUpdate(_:)`, `update(email:mutate:)`, `remove(email:)` (also deletes Keychain
    `refresh_token_<email>`), and helpers `refreshTokenKey(for:) -> "refresh_token_\(email)"`.
    Normalize all emails with `.lowercased()` (D-MA-01). Implement `migrateLegacyIfNeeded(keychain:)`:
    guard on a one-shot flag `gmail_multiacct_migrated_v2`; if a legacy `gmail_connected_email` exists
    and a `refresh_token` Keychain item exists, copy the token to `refresh_token_<email>`, seed a
    GmailAccount from legacy `gmail_last_synced_at`/`gmail_access_token_expiry`, then clear the three
    legacy `gmail_*` singular keys and the legacy `refresh_token` item, and set the migrated flag.
    Order writes so the per-account token is confirmed saved before the legacy token is deleted
    (critical — the user must not be forced to re-auth). Keep everything unit-testable via the existing
    spy pattern (inject UserDefaults + KeychainPort). Write MultiAccountGmailTests.swift covering the
    five behaviors above using SpyKeychainStore + an isolated UserDefaults suite.
  </action>
  <verify>
    <automated>xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/MultiAccountGmailTests -quiet 2>&1 | tail -25</automated>
  </verify>
  <done>GmailAccountStore stores N accounts without clobbering; legacy single-account state migrates once into the per-account scheme preserving the refresh token; all MultiAccountGmailTests pass.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: GmailSyncController — multi-account signIn (add), sync (loop), signOut(account)</name>
  <files>MyHomeApp/Features/Gmail/GmailSyncController.swift, MyHomeTests/GmailSyncControllerTests.swift, MyHomeTests/MultiAccountGmailTests.swift</files>
  <behavior>
    - signIn(): after OAuth, calls getProfile to learn the email, stores the refresh token under
      `refresh_token_<email>`, and adds/updates that account — adding a second account leaves the first
      connected (Keychain has both `refresh_token_<a>` and `refresh_token_<b>`).
    - sync(): iterates all connected accounts; for each, proactive-refresh → fetch → ingest, stamping
      `expense.sourceAccount = <email>`. The idempotency guard skips a message only when an existing
      expense has the SAME sourceAccount AND gmailMessageID (account-scoped) — the same messageID under
      a different account is NOT skipped. D-MA-06(b): a nil-sourceAccount existing expense matches
      ANY account for its messageID (messageID-only fallback) so legacy-ingested emails are not
      re-ingested before the backfill runs.
    - One account whose refresh throws invalid_grant is marked needsReconnect and skipped; sync still
      processes the remaining accounts and finishes (not aborted). Overall syncStatus reflects success
      when at least one account synced; surfaces per-account reconnect state.
    - signOut(email:) deletes only `refresh_token_<email>` and that account's metadata; other accounts
      remain connected. isConnected reflects "any account connected".
    - Existing single-account-shaped tests still pass after migration semantics (init runs
      migrateLegacyIfNeeded; a pre-seeded legacy `refresh_token` makes isConnected true).
  </behavior>
  <action>
    Refactor GmailSyncController to delegate persistent account state to GmailAccountStore (Task 2).
    Replace the single `accessToken: String?` with an in-memory `[String: String]` access-token map
    keyed by email (D-MA-04). Replace the singular `connectedEmail`/`lastSyncedAt`/`accessTokenExpiry`
    computed UserDefaults accessors with reads through the store; keep `isConnected` as an observable
    derived from `!store.accounts.isEmpty`. In `init`, after seeding the store, call
    `store.migrateLegacyIfNeeded(keychain:)` so the already-connected account is preserved.
    `signIn()`: keep the existing PKCE/authorize/exchange/CSRF flow unchanged (SEC: state binding,
    gmail.readonly scope, refresh_token guard). After a successful exchange, do NOT store under the
    fixed `refresh_token` key — instead obtain the access token, call `fetch.getProfile` to learn the
    email (D-MA-01), store the refresh token under `refresh_token_<email>`, put the access token in the
    in-memory map, addOrUpdate the account with expiry, then run an initial sync for that one account.
    Extract the existing per-account sync body (refresh→list→fetch→parse→triage→persist) into a private
    `syncAccount(_ account:) async -> Bool` returning success. `sync()` becomes: refresh the account
    list, loop `syncAccount` over all accounts, aggregate results, set syncStatus to .done if any
    succeeded (or .tokenExpired/.error only if all failed), and update each account's lastSynced/
    needsReconnect via the store. In `syncAccount`, use `refresh_token_<email>`, stamp
    `expense.sourceAccount = account.email`, and change the idempotency set to
    `Set(existing.compactMap { e in e.sourceAccount.map { ($0, e.gmailMessageID) } })`-style
    account+messageID membership (skip only on exact (account,messageID) match). Keep getProfile→email,
    DismissedMessageStore, DedupChecker (global), ConfidenceScorer, and category-hint logic intact.
    Replace `signOut()` with `signOut(email:)` that removes one account; keep a `signOutAll()` if the UI
    needs it. Update GmailSyncControllerTests.swift for the new shapes (e.g. the reconnect-overwrite
    test becomes add-second-account; signOut tests target a specific email; keychain key assertions use
    `refresh_token_<email>`). Add multi-account sync + account-scoped-dedup + one-expired-doesnt-abort
    cases to MultiAccountGmailTests.swift. Preserve all Phase 6/7 security decisions (SEC-03, D6-07,
    CSRF, scope).
  </action>
  <verify>
    <automated>xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/GmailSyncControllerTests -only-testing:MyHomeTests/MultiAccountGmailTests -only-testing:MyHomeTests/IngestionPipelineTests -quiet 2>&1 | tail -30</automated>
  </verify>
  <done>signIn adds an account without clobbering; sync loops all accounts with account-scoped dedup; one expired account does not abort the rest; signOut(email:) removes a single account; all targeted tests pass.</done>
</task>

<task type="auto">
  <name>Task 4: Settings multi-account UI + BGTask loop verification + full build/test</name>
  <files>MyHomeApp/Features/Settings/SettingsView.swift</files>
  <action>
    Rebuild the Gmail Section to render the multi-account model (D-MA-05). When no accounts are
    connected, keep the "Connect Gmail" button + authorizing/error states. When one or more accounts
    are connected, render one row per `gmailSyncController.accounts` (sorted by email): each row shows
    the email, its last-synced (relativeToNow / "Never"), a per-account "Reconnect" affordance when that
    account `needsReconnect`, and a per-account "Disconnect" (calling `signOut(email:)`, optionally via a
    confirmation dialog). Below the list add an "Add account" button (calls `signIn()`) and one overall
    "Sync now" button that calls `sync()` (syncs all). Keep the syncing/authorizing ProgressView states
    and the global error display. Do NOT change MyHomeApp.swift or RootView.swift — the BGAppRefreshTask
    already calls `gmailSyncController.sync()`, which is now the multi-account loop, and setContext is
    unchanged; confirm by inspection that no edit is needed. Then run the FULL test + build pass on the
    iPhone 17 simulator (Xcode 26.5) to confirm the whole suite stays green and the app builds.
  </action>
  <verify>
    <automated>xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -30</automated>
  </verify>
  <done>Settings shows a per-account list with per-account disconnect/reconnect + last-synced, an Add account button, and an overall Sync now; BGTask path still drives the multi-account sync() unchanged; full test suite passes and the app builds for iPhone 17.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| app → Google OAuth/Gmail | refresh tokens (per account) and access tokens cross here |
| app → OS Keychain | per-account refresh tokens stored under `refresh_token_<email>` |
| app → App Group UserDefaults | per-account non-secret metadata (expiry, lastSynced) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-MA-01 | Information Disclosure | per-account refresh tokens | mitigate | Keychain only, key `refresh_token_<email>`, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (SEC-03) preserved by reusing SystemKeychainStore.save; never in UserDefaults |
| T-MA-02 | Information Disclosure | per-account access tokens | mitigate | in-memory `[email: token]` map only (D6-07); never persisted, never logged |
| T-MA-03 | Tampering | OAuth callback | mitigate | existing CSRF state binding in signIn/authorize left unchanged |
| T-MA-04 | Denial of Service | one expired account | mitigate | syncAccount failure is isolated; sync() continues other accounts (one expired must not abort the rest) |
| T-MA-05 | Repudiation/Integrity | dedup across mailboxes | mitigate | idempotency keyed on (sourceAccount, gmailMessageID) so identical message IDs across mailboxes are not collapsed |
| T-MA-06 | Tampering | upgrade migration | mitigate | per-account token write confirmed before legacy token deletion — no window where the user's existing connection is lost |
| T-MA-SC | Tampering | package installs | accept | no new third-party packages added; all ports/spies already in repo |
</threat_model>

<verification>
- Build succeeds for iPhone 17 simulator (Xcode 26.5, scheme MyHome).
- Full MyHomeTests suite passes (GmailSyncControllerTests, MultiAccountGmailTests, IngestionPipelineTests, KeychainPortTests, GmailAuthURLTests).
- SchemaV5 migration is additive; existing stores open without data loss.
- A legacy single-account install (seeded `refresh_token` + `gmail_connected_email`) appears as one connected account after launch with no re-auth.
- Adding a second account preserves the first (two `refresh_token_<email>` Keychain items).
- Dedup is account-scoped; the same Gmail message ID under two accounts is not collapsed.
</verification>

<success_criteria>
- GmailSyncController is multi-account: signIn adds, sync loops, signOut targets one account.
- Per-account state keyed by lowercased email; refresh tokens in Keychain (SEC-03), access tokens in-memory (D6-07).
- Expense.sourceAccount persisted via SchemaV5; idempotency guard is (account, messageID)-scoped.
- Existing single-account user forward-migrated with no forced re-auth.
- Settings renders a per-account list (last-synced + reconnect/disconnect each), Add account, overall Sync now.
- BGAppRefreshTask drives the new multi-account sync() unchanged.
- All tests green; app builds for iPhone 17.
</success_criteria>

<output>
Create `.planning/quick/260603-lvt-support-syncing-from-multiple-gmail-acco/260603-lvt-SUMMARY.md` when done
</output>
