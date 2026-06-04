---
phase: quick-260603-lvt
plan: 01
status: complete
subsystem: gmail-sync
tags: [multi-account, oauth, keychain, swiftdata, migration, settings-ui]
dependency_graph:
  requires: []
  provides: [multi-account-gmail-sync, schemaV5, gmail-account-store]
  affects: [gmail-sync-controller, settings-ui, expense-model, migration-plan]
tech_stack:
  added: []
  patterns:
    - GmailAccountStore (plain struct with injected UserDefaults + KeychainPort, Codable value type)
    - Per-account Keychain keys (refresh_token_<email>)
    - account-scoped dedup idempotency set ((sourceAccount, gmailMessageID))
    - D-MA-06(b) nil-sourceAccount fallback for legacy expenses
    - Legacy single-account sync path preserved for test backward-compat
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV5.swift
    - MyHomeApp/Features/Gmail/GmailAccountStore.swift
    - MyHomeTests/MultiAccountGmailTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeTests/GmailSyncControllerTests.swift
    - MyHomeTests/MigrationTests.swift
    - MyHomeTests/Support/SpyGmailAuth.swift
    - MyHomeTests/Support/SpyGmailFetch.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - D-MA-01: Account identity = lowercased Gmail address from getProfile
  - D-MA-02: refresh_token_<email> in Keychain; gmail_accounts_v2 in UserDefaults
  - D-MA-03: Expense.sourceAccount: String? persisted for (account, messageID) dedup
  - D-MA-04: Access tokens in-memory [String: String] map keyed by email
  - D-MA-05: Per-account rows in Settings with last-synced + Reconnect/Disconnect
  - D-MA-06a: Legacy expense backfill in migrateLegacyIfNeeded (or deferred to setContext)
  - D-MA-06b: nil-sourceAccount expenses match ANY account messageID (legacy fallback)
  - T-MA-06: Per-account token write confirmed before legacy token deleted
metrics:
  duration: "~45 minutes"
  completed: "2026-06-05"
  tasks_completed: 4
  tasks_total: 4
  files_created: 3
  files_modified: 10
---

# Phase quick-260603-lvt Plan 01: Multi-Account Gmail Sync Summary

**One-liner:** Multi-account GmailSyncController with per-account Keychain tokens, (account, messageID) dedup, SchemaV5 sourceAccount field, and per-account Settings UI.

## Tasks Completed

| Task | Name | Commit | Result |
|------|------|--------|--------|
| 1 | SchemaV5 — Expense.sourceAccount | cc77f1a | Build pass |
| 2 | GmailAccountStore — per-account state + migration | 7b64ce9 | 10 tests pass |
| 3 | GmailSyncController — multi-account refactor | dd1d40a | All targeted tests pass |
| 4 | Settings multi-account UI + full suite | 3f8e93d | Full suite green |

## What Was Built

### Task 1: SchemaV5

- `SchemaV5` enum: additive superset of SchemaV4, adds `Expense.sourceAccount: String? = nil`
- `AppMigrationPlan`: SchemaV5 appended; `v4ToV5 = MigrationStage.custom(nil, nil)` (FB13812722 workaround)
- `ModelContainer+App.swift`: switched to `SchemaV5.self` as the current schema
- `Expense` and `Category` typealiases updated from SchemaV4 to SchemaV5

### Task 2: GmailAccountStore

- `GmailAccount`: Codable struct (email, accessTokenExpiry, lastSyncedAt, needsReconnect)
- `GmailAccountStore`: plain struct with `addOrUpdate`, `update`, `remove`, `migrateLegacyIfNeeded`
- Persists accounts as `[String: GmailAccount]` JSON under `gmail_accounts_v2` (UserDefaults)
- `refreshTokenKey(for:)` returns `"refresh_token_\(email)"` for per-account Keychain keys
- T-MA-06 migration safety: per-account token confirmed written before legacy token deleted
- D-MA-06(a): `backfillSourceAccount` backfills `sourceAccount` on legacy expenses
- `migrateLegacyIfNeeded` guarded by one-shot `gmail_multiacct_migrated_v2` flag

### Task 3: GmailSyncController (multi-account refactor)

- `store: GmailAccountStore` replaces singular UserDefaults accessors
- `accessTokenMap: [String: String]` holds in-memory access tokens per-account (D-MA-04)
- `signIn()`: calls `getProfile` to learn email BEFORE storing token; saves under `refresh_token_<email>`
- `sync()`: loops all accounts; one expired account skipped (needsReconnect set), others continue
- `syncAccount(email:accessToken:)`: extracted private method; stamps `expense.sourceAccount`
- Account-scoped dedup: skip on `(sourceAccount, messageID)` match; D-MA-06(b) nil-source fallback
- `signOut(email:)`: removes one account; `signOut()` removes all (backward compat)
- Legacy single-account sync path preserved for tests that inject `accessToken` directly
- `SpyGmailAuth.refreshResultForKey`: per-token refresh responses for multi-account tests
- `SpyGmailFetch.profileResultsByToken`: per-access-token profile responses

### Task 4: Settings UI + Migration Tests Fix

- `SettingsView`: per-account rows (email + last-synced + Reconnect/Disconnect); "Add account"; "Sync now"
- Profile header: shows account count ("2 Gmail accounts" or "Gmail connected")
- Per-account Disconnect via confirmation dialog; "Reconnect" shown when needsReconnect
- `MigrationTests`: updated to target SchemaV5; V3→V5 test asserts `sourceAccount == nil`
- BGAppRefreshTask in MyHomeApp.swift confirmed unchanged (calls `sync()` which now loops all accounts)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] String?? flattening for KeychainPort.load() with try?**
- **Found during:** Task 2 build (GmailAccountStore.swift), Task 3 build (GmailSyncController.swift)
- **Issue:** `KeychainPort.load()` returns `String?` (throws), so `try? keychain.load(...)` produces `String??`. Guard-let on `String??` fails to compile in Swift 6 strict concurrency mode.
- **Fix:** Added intermediate `let x: String? = (try? keychain.load(...)) ?? nil` to flatten the nested optional before binding.
- **Files modified:** GmailAccountStore.swift, GmailSyncController.swift

**2. [Rule 1 - Bug] MigrationTests targeted SchemaV4 but AppMigrationPlan now targets SchemaV5**
- **Found during:** Task 4 full test suite
- **Issue:** `Schema(versionedSchema: SchemaV4.self)` opened a container whose `Expense` type was SchemaV4.Expense, but the `Expense` typealias now points to SchemaV5.Expense. The model descriptor mismatch caused MigrationTests to fail.
- **Fix:** Updated all three MigrationTests to target `SchemaV5.self`; V3→V4 test renamed to V3→V5 and also asserts `sourceAccount == nil`.
- **Files modified:** MigrationTests.swift

**3. [Rule 2 - Missing critical functionality] Legacy backward-compat sync path**
- **Found during:** Task 3 — IngestionPipelineTests inject `controller.accessToken = "access_tok"` and expect sync to work without seeding any account in the store.
- **Fix:** Added `legacySingleAccountSync()` private method that activates when `store.accounts.isEmpty` but `accessToken` is set. This preserves all existing IngestionPipelineTests without modification.
- **Files modified:** GmailSyncController.swift

## Test Coverage

| Suite | Tests | Result |
|-------|-------|--------|
| MultiAccountGmailTests | 14 | All pass (MA-01 to MA-09) |
| GmailSyncControllerTests | 16 | All pass (updated for per-account keys) |
| IngestionPipelineTests | 6 | All pass (unmodified, legacy compat preserved) |
| MigrationTests | 3 | All pass (updated to SchemaV5 target) |
| All other suites | ~60 | All pass (unchanged) |

## Known Stubs

None. All data is wired to real store operations. No placeholder text or hardcoded empty values.

## Threat Surface Scan

No new network endpoints or auth paths beyond what is documented in the plan's threat model.

- T-MA-01: `refresh_token_<email>` in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (SEC-03 preserved via SystemKeychainStore reuse)
- T-MA-02: Access tokens in-memory `[email: token]` map only (D6-07, D-MA-04)
- T-MA-03: CSRF state binding in signIn unchanged
- T-MA-04: One expired account does not abort sync for others — verified by MA-08 test
- T-MA-05: (account, messageID) dedup prevents cross-mailbox collapse — verified by MA-07 test
- T-MA-06: Legacy token preserved until per-account copy confirmed — verified by MA-04b test

## Self-Check

**Files created — exist:**
- /Users/reo/My Projects/my-home/MyHomeApp/Persistence/Schema/SchemaV5.swift: exists
- /Users/reo/My Projects/my-home/MyHomeApp/Features/Gmail/GmailAccountStore.swift: exists
- /Users/reo/My Projects/my-home/MyHomeTests/MultiAccountGmailTests.swift: exists

**Commits — verified in git log:**
- cc77f1a: feat(260603-lvt): SchemaV5
- 7b64ce9: feat(260603-lvt): GmailAccountStore
- dd1d40a: feat(260603-lvt): GmailSyncController
- 3f8e93d: feat(260603-lvt): Settings UI + migration tests

**Full test suite:** PASSED on iPhone 17 simulator (Xcode 26.5)

## Self-Check: PASSED
