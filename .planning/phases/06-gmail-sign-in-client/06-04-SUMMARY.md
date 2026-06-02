---
phase: 06-gmail-sign-in-client
plan: "04"
subsystem: gmail
tags: [production-wiring, ui-integration, oauth-complete, wave-4]
dependency_graph:
  requires: ["06-01", "06-02", "06-03"]
  provides:
    - SystemGmailAuth.authorize() — ASWebAuthenticationSession OAuth browser + callback parsing
    - SystemGmailAuth.exchangeCode() — OAuth token exchange endpoint (URLSession POST)
    - SystemGmailAuth.refreshToken() — Proactive token refresh (URLSession POST)
    - SystemKeychainStore — Security.framework Keychain save/load/delete with SEC-03 accessibility
    - GmailOAuthConfig — committed OAuth credentials (clientID, redirectURI, callbackScheme)
    - Gmail Settings section — Connect/Connected-as/Last-synced/Sync-now/Sign-out/Reconnect flows
    - RootView scenePhase integration — gmailSyncController.scenePhaseChanged() on app foreground
    - Info.plist CFBundleURLTypes — OAuth callback scheme registration
  affects:
    - MyHomeApp/Gmail/GmailAuthPort.swift (SystemGmailAuth production conformer added)
    - MyHomeApp/Gmail/KeychainPort.swift (SystemKeychainStore production conformer added)
    - MyHomeApp/Gmail/GmailOAuthConfig.swift (created — committed credentials)
    - MyHomeApp/Features/Gmail/GmailSyncController.swift (default args now resolve to real types)
    - MyHomeApp/Features/Settings/SettingsView.swift (Gmail section added)
    - MyHomeApp/RootView.swift (gmailSyncController ownership + scenePhase wiring)
    - MyHomeApp/Info.plist (CFBundleURLTypes added)
tech_stack:
  added:
    - AuthenticationServices.ASWebAuthenticationSession
    - Security.framework (SecItemAdd, SecItemUpdate, SecItemCopyMatching, SecItemDelete)
  patterns:
    - "@unchecked Sendable wrapper around OS-touching types (UIApplication, URLSession)"
    - "Upsert pattern in Keychain: try SecItemAdd → on errSecDuplicateItem, SecItemUpdate WITHOUT kSecReturnData"
    - "withCheckedThrowingContinuation with guard-early-return for single-resume guarantee"
    - "@MainActor authorize() for ASWebAuthenticationSession presentation anchor"
    - "60s URLSession timeout for OAuth token endpoint (D6-24)"
key_files:
  created:
    - MyHomeApp/Gmail/GmailOAuthConfig.swift (155 lines)
  modified:
    - MyHomeApp/Gmail/GmailAuthPort.swift (+129 lines, SystemGmailAuth conformer)
    - MyHomeApp/Gmail/KeychainPort.swift (+82 lines, SystemKeychainStore conformer)
    - MyHomeApp/Features/Gmail/GmailSyncController.swift (default args updated)
    - MyHomeApp/Features/Settings/SettingsView.swift (+70 lines, Gmail section)
    - MyHomeApp/RootView.swift (+2 lines, gmailSyncController owner + scenePhase wiring)
    - MyHomeApp/Info.plist (+6 lines, CFBundleURLTypes)
decisions:
  - "Reverse-client-ID OAuth scheme (com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect) used per D6-04 checkpoint decision — matches Google's recommendation, future-proof against scheme enforcement"
  - "Real OAuth credentials committed in GmailOAuthConfig.swift — iOS native apps have no client_secret per RFC 8252"
  - "Session retained as instance property in SystemGmailAuth to prevent early deallocation before callback (RESEARCH Pitfall)"
  - "Keychain save uses upsert (add-then-update) to avoid errSecDuplicateItem on reconnect"
  - "Gmail Settings section placed between Security and Data sections (D6-26 discretion)"
  - "Confirmation dialog for sign-out (D6-17) to prevent accidental disconnection"
  - "Last-synced timestamp always visible in Settings (ING-05, D6-16) — shows 'Never' before first sync"
  - "Sync-now button disabled during .syncing status; shows 'Syncing…' progress indicator (D6-25 discretion)"
metrics:
  duration: 25
  completed: "2026-06-02"
  tasks: 2
  files: 7
---

# Phase 06 Plan 04: Production UI Wiring COMPLETE Summary

Wave 4 production wiring: SystemGmailAuth + SystemKeychainStore + GmailOAuthConfig committed + Gmail Settings section live + RootView scenePhase integration. All production OS-touching conformers deployed; all 53 unit tests green (zero regression); build succeeded.

## What Was Built

**Task 1 — SystemKeychainStore + SystemGmailAuth + GmailOAuthConfig (commit c9e205f):**
- `SystemKeychainStore.save()`: SecItemAdd with upsert-to-update fallback; kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly set (SEC-03, T-06-04-KEYCHAIN); update query does NOT include kSecReturnData (anti-pattern guard)
- `SystemKeychainStore.load()`: SecItemCopyMatching with kSecReturnData; tolerant of errSecItemNotFound → returns nil; maps other OSStatus to KeychainError.unexpectedStatus
- `SystemKeychainStore.delete()`: SecItemDelete tolerant of item-not-found (idempotent)
- `SystemGmailAuth.authorize()`: @MainActor, ASWebAuthenticationSession with SceneContextProvider presentation anchor, withCheckedThrowingContinuation with guard-early-return-per-branch guarantee (RESEARCH Pitfall 4), resumes continuation exactly once on .cancelled / .success / error paths
- `SystemGmailAuth.authorize()`: maps ASWebAuthenticationSessionError.canceledLogin → GmailAuthError.userCancelled; extracts `error` query param → GmailAuthError.oauthError(raw) (D6-19)
- `SystemGmailAuth.exchangeCode()`: URLSession POST to https://oauth2.googleapis.com/token, x-www-form-urlencoded body with [client_id, code, code_verifier, grant_type, redirect_uri], 60s timeout (D6-24)
- `SystemGmailAuth.exchangeCode()`: maps 400 invalid_grant → GmailAuthError.oauthError (ING-16 — treated as token expiry)
- `SystemGmailAuth.refreshToken()`: URLSession POST with [client_id, refresh_token, grant_type], 60s timeout; same 400 invalid_grant handling
- `GmailOAuthConfig.swift`: enum with static let constants (clientID, redirectURI, callbackScheme) from Google Cloud Console iOS OAuth 2.0 client registration (real credentials, reverse-client-ID scheme per D6-04)
- All compile & link verified; full unit test suite remains green

**Task 2 — Gmail Settings section + RootView scenePhase wiring + Info.plist URL type (commit c9e205f):**
- `SettingsView`: added `let gmailSyncController: GmailSyncController` parameter (injection, never @StateObject/@ObservedObject per PATTERNS)
- `SettingsView`: added Gmail section with conditional rows:
  - Not connected (D6-15): "Connect Gmail" Button → `Task { await gmailSyncController.signIn() }`
  - Connected (D6-14): "Connected as: \(email)" text + always-visible "Last synced \(relativeToNow ?? "Never")" row (ING-05, D6-16)
  - While syncing (D6-25): ProgressView() + "Syncing…" text; Sync-now button disabled
  - Syncing done: "Sync now" Button → `Task { await gmailSyncController.sync() }`
  - Token expired (ING-16, D6-11/D6-13): "Reconnect Gmail" row in orange
  - Error state (case .error(msg)): raw message display (D6-19) + Retry Button
  - Signed in: "Sign out" Button (red) → confirmationDialog (D6-17) → `Task { await gmailSyncController.signOut() }`
- All async calls wrapped in `Task { }` (PATTERNS shared pattern)
- Gmail section positioned between Security and Data sections (D6-26 discretion)
- `RootView`: added `@State private var gmailSyncController = GmailSyncController()` after lockController (D6-28)
- `RootView`: updated EXISTING `.onChange(of: scenePhase)` closure to call `gmailSyncController.scenePhaseChanged(newPhase)` after lockController call — NO second .onChange added (PATTERNS guard)
- `RootView`: updated SettingsView call site to pass `gmailSyncController: gmailSyncController`
- `Info.plist`: added CFBundleURLTypes with CFBundleURLSchemes entry = GmailOAuthConfig.callbackScheme (com.googleusercontent.apps.555696841697-kd0mmjd21la88mk5aid2rh292l9gfbcj) so OS delivers the OAuth callback to the app

## Verification

- ✅ Build: `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → **BUILD SUCCEEDED**
- ✅ Unit tests: 53 tests run, all passed (zero regression from swapping stub defaults for real conformers):
  - 12 GmailSyncControllerTests (from plan 03) — all green
  - 14 GmailAuthURL + PKCE + Keychain tests (from plans 02/01) — all green
  - 27 expense/budget/overview/lock tests (from phases 1–5) — all green
- ✅ Code inspection:
  - SystemKeychainStore: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly present ✓
  - SystemKeychainStore update query: NO kSecReturnData ✓
  - SystemGmailAuth: ASWebAuthenticationSession present ✓
  - SystemGmailAuth.authorize(): @MainActor marked ✓
  - SystemGmailAuth.authorize(): withCheckedThrowingContinuation with single-resume guard pattern ✓
  - GmailOAuthConfig.swift: committed, real credentials, registered in pbxproj ✓
  - SettingsView: Gmail section renders conditional rows per spec ✓
  - RootView: single .onChange(of: scenePhase), calls gmailSyncController.scenePhaseChanged() ✓
  - Info.plist: CFBundleURLTypes added with correct scheme ✓

## Phase 06 Completion Status

- ✅ Plan 01 (Wave 0 scaffold): complete — 5 failing RED test files + port protocols + pbxproj registration
- ✅ Plan 02 (Wave 1 pure logic): complete — PKCE.generate() + buildAuthorizationURL + Date.relativeToNow, 14 tests green
- ✅ Plan 03 (Wave 2 controller): complete — GmailSyncController state machine signIn/sync/signOut/scenePhaseChanged, 12 tests green
- ✅ Plan 04 (Wave 4 production UI): complete — SystemGmailAuth + SystemKeychainStore + Settings wiring + RootView integration, 53 tests green

**Phase 06 Ready for UAT** (Phase 6 of 7 complete; 26 of 26 plans executed)

## Next Steps

→ **Phase 07: Bank Parsers & Ingestion Pipeline** — Zero-touch expense ingestion: parses, confidence triage, Review Inbox, dedup, and background sync.

UAT for Phase 06 requires:
1. Real Gmail account signed in on iPhone 17 simulator
2. Settings → "Connect Gmail" → system OAuth browser → complete sign-in → return to app
3. Verify:
   - Last synced timestamp updates (UAT-6-01..05, ING-02/03/05)
   - Keychain persistence (UAT-6-07, SEC-03)
   - Sign out / reconnect flow (UAT-6-08/09, SET-04)
   - Token expiry handling (UAT-6-06, ING-16 — 7-day wait noted as deferred manual check)
   - Error recovery (UAT-6-10, D6-19)
