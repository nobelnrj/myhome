---
phase: 06-gmail-sign-in-client
plan: "02"
subsystem: gmail
tags: [tdd, green-phase, pkce, oauth, wave-2]
dependency_graph:
  requires: ["06-01"]
  provides:
    - PKCE.generate() — real CryptoKit + SecRandomCopyBytes implementation (ING-01)
    - GmailSyncController.buildAuthorizationURL — full 9-param Google OAuth URL builder (ING-01)
    - Date.relativeToNow — RelativeDateTimeFormatter extension (ING-05, SET-05)
  affects:
    - MyHomeApp/Gmail/PKCE.swift (stub replaced with real impl)
    - MyHomeApp/Features/Gmail/GmailSyncController.swift (buildAuthorizationURL implemented)
    - MyHomeApp/Gmail/RelativeTimestamp.swift (new file)
    - MyHomeApp/Support/Date+Display.swift (stub removed)
    - MyHome.xcodeproj/project.pbxproj (RelativeTimestamp.swift registered)
tech_stack:
  added: []
  patterns:
    - CryptoKit.SHA256 for PKCE S256 challenge derivation (T-06-PKCE)
    - SecRandomCopyBytes for CSPRNG verifier generation (RFC 7636)
    - URLComponents queryItems builder for OAuth URL construction
    - RelativeDateTimeFormatter with unitsStyle=.full for locale-aware relative timestamps
key_files:
  created:
    - MyHomeApp/Gmail/RelativeTimestamp.swift
  modified:
    - MyHomeApp/Gmail/PKCE.swift
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeApp/Support/Date+Display.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "RelativeTimestamp.swift is a separate file from Date+Display.swift — cleanly scopes Phase 6 additions; stub in Date+Display.swift removed to avoid duplicate property definition"
  - "PKCE.generate() uses 32 random bytes giving a 43-char base64url verifier — well within RFC 7636 43-128 range without needing truncation"
  - "buildAuthorizationURL left nonisolated as planned — pure function, no actor state mutation, callable from test context without main-actor hop"
metrics:
  duration: 15
  completed: "2026-06-02"
  tasks: 2
  files: 5
---

# Phase 06 Plan 02: Pure Logic GREEN — PKCE, Auth URL, Relative Timestamp Summary

Wave 2 pure-logic GREEN: PKCE CryptoKit math, Google OAuth authorization URL builder, and relative-timestamp display helper implemented; PKCETests (3), GmailAuthURLTests (8), and RelativeTimestampTests (3) all turn GREEN — 14 tests total.

## What Was Built

**Task 1 — PKCE.generate() (commit 8fe7000):**
- Replaced `fatalError` stub with real RFC 7636 implementation
- `SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)` → CSPRNG 32 bytes
- Base64url-encode via `.base64EncodedString()` + 3-line replace (`=` → `""`, `+` → `-`, `/` → `_`) → `verifier`
- `CryptoKit.SHA256.hash(data: verifier.data(using: .ascii)!)` → base64url-encode digest → `challenge`
- Guards: throws `PKCEError.failedToGenerateRandomBytes` on CSPRNG failure or ASCII conversion failure
- Added `import CryptoKit` and `import Security`
- All 3 PKCETests GREEN: verifier 43–128 chars, challenge != verifier, two calls differ

**Task 2 — buildAuthorizationURL + RelativeTimestamp (commit 1d2743b):**
- `GmailSyncController.buildAuthorizationURL`: URLComponents builder with all 9 required query params:
  `client_id`, `redirect_uri`, `response_type=code`, `scope=https://www.googleapis.com/auth/gmail.readonly`,
  `code_challenge`, `code_challenge_method=S256`, `access_type=offline`, `state`, `prompt=consent`
- `RelativeTimestamp.swift`: new file, `extension Date { var relativeToNow: String }` using
  `RelativeDateTimeFormatter` with `unitsStyle = .full` and `localizedString(for:relativeTo:)`
- `Date+Display.swift`: removed empty `relativeToNow` stub (would cause duplicate property error)
- `project.pbxproj`: RelativeTimestamp.swift registered as `F621RT`/`A621RT` in G160 Gmail group + MyHome Sources phase
- All 8 GmailAuthURLTests and 3 RelativeTimestampTests GREEN

## Verification Results

- `xcodebuild test -only-testing:MyHomeTests/PKCETests` — TEST SUCCEEDED (3/3)
- `xcodebuild test -only-testing:MyHomeTests/GmailAuthURLTests -only-testing:MyHomeTests/RelativeTimestampTests` — TEST SUCCEEDED (11/11)
- All three suites together (14 tests) — TEST SUCCEEDED
- GmailSyncControllerTests / KeychainPortTests remain as expected (not targeted by this plan)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed conflicting relativeToNow stub from Date+Display.swift**
- **Found during:** Task 2 — RelativeTimestamp.swift defines `var relativeToNow: String`; Date+Display.swift had an existing stub with the same property name
- **Issue:** Duplicate property definition would cause a compile error (Swift does not allow duplicate extension properties within the same module)
- **Fix:** Removed the stub block (11 lines including comments) from `Date+Display.swift`; the real implementation in `RelativeTimestamp.swift` is the sole definition
- **Files modified:** `MyHomeApp/Support/Date+Display.swift`
- **Commit:** 1d2743b

None of the other stubs from plan 01 were touched — `signIn()`, `sync()`, `signOut()`, `scenePhaseChanged()`, and `_StubGmailAuth`/`_StubKeychain` remain as-is for plan 03.

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| `GmailSyncController.signIn()` sets `syncStatus = .idle` only | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~161 | Plan 03 implements full OAuth flow |
| `GmailSyncController.sync()` is empty | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~169 | Plan 03 implements Gmail API fetch |
| `GmailSyncController.signOut()` is empty | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~177 | Plan 03 implements Keychain + defaults cleanup |
| `GmailSyncController.scenePhaseChanged()` is a no-op | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~151 | Plan 03 implements token expiry check |
| `_StubGmailAuth` / `_StubKeychain` as default args | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~137 | Plan 04 replaces with SystemGmailAuth/SystemKeychainStore |

## Threat Surface Scan

No new threat surface beyond the plan's threat model. All mitigations applied:
- T-06-PKCE: `SecRandomCopyBytes` + `CryptoKit.SHA256` used as specified; no arc4random/drand48
- T-06-CSRF: `state` query param included in auth URL
- T-06-SCOPE: Scope hardcoded to `gmail.readonly` only
- T-06-SC: Zero external packages; CryptoKit/Security/Foundation are first-party

## Self-Check: PASSED

Files exist:
- MyHomeApp/Gmail/PKCE.swift: FOUND (contains SecRandomCopyBytes + SHA256.hash)
- MyHomeApp/Gmail/RelativeTimestamp.swift: FOUND (contains RelativeDateTimeFormatter)
- MyHomeApp/Features/Gmail/GmailSyncController.swift: FOUND (contains access_type=offline, code_challenge_method=S256)
- MyHome.xcodeproj/project.pbxproj: RelativeTimestamp.swift registered (F621RT/A621RT)

Commits exist:
- 8fe7000: feat(06-02): implement PKCE.generate() with CryptoKit + SecRandomCopyBytes
- 1d2743b: feat(06-02): implement buildAuthorizationURL + RelativeTimestamp helper
