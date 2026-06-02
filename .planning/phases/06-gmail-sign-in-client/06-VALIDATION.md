---
phase: 6
slug: gmail-sign-in-client
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-02
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`) — matches Phase 3–5 tests |
| **Config file** | none — auto-discovered from `MyHomeTests` target |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/GmailSyncControllerTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~60–120 seconds (full suite, simulator build) |

---

## Sampling Rate

- **After every task commit:** Run the quick run command for the affected suite
- **After every plan wave:** Run the full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 6-01-* | 01 | 0 | ING-01,02,03,05,16,SEC-03,SET-04,05 | — | Failing test stubs compile | unit | `xcodebuild ... -only-testing:MyHomeTests` | ❌ W0 | ⬜ pending |
| 6-*-PKCE | — | 1 | ING-01 | T-6-PKCE | verifier 43–128 chars; challenge=SHA256(verifier) base64url | unit | `... -only-testing:MyHomeTests/PKCETests` | ❌ W0 | ⬜ pending |
| 6-*-AUTHURL | — | 1 | ING-01 | — | auth URL carries all required params, encoded | unit | `... -only-testing:MyHomeTests/GmailAuthURLTests` | ❌ W0 | ⬜ pending |
| 6-*-KEYCHAIN | — | 1 | SEC-03 | T-6-TOKEN | spy save/load/delete round-trip | unit | `... -only-testing:MyHomeTests/KeychainPortTests` | ❌ W0 | ⬜ pending |
| 6-*-REFRESH | — | 1 | ING-16 | — | needsProactiveRefresh true when expiry < 5 min | unit | `... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ W0 | ⬜ pending |
| 6-*-EXPIRED | — | 1 | ING-16 | — | isTokenExpired → syncStatus == .tokenExpired | unit | `... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ W0 | ⬜ pending |
| 6-*-SYNC | — | 1 | ING-02,03,05 | — | idle→syncing→done; lastSyncedAt written | unit | `... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ W0 | ⬜ pending |
| 6-*-SIGNOUT | — | 1 | SET-04 | T-6-TOKEN | signOut() deletes keychain + clears UserDefaults | unit | `... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ W0 | ⬜ pending |
| 6-*-TIMESTAMP | — | 1 | ING-05,SET-05 | — | RelativeDateTimeFormatter output for known dates | unit | `... -only-testing:MyHomeTests/RelativeTimestampTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*The planner assigns final task IDs; rows above map requirements to the testable units identified in RESEARCH.md "Validation Architecture".*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/PKCETests.swift` — stubs for ING-01 (PKCE math)
- [ ] `MyHomeTests/GmailAuthURLTests.swift` — stubs for ING-01 (auth URL builder)
- [ ] `MyHomeTests/GmailSyncControllerTests.swift` — stubs for ING-02, ING-03, ING-05, ING-16, SET-04, SET-05 (state machine)
- [ ] `MyHomeTests/KeychainPortTests.swift` — stubs for SEC-03 (spy round-trip)
- [ ] `MyHomeTests/RelativeTimestampTests.swift` — stubs for SET-05 (display format)
- [ ] `MyHomeTests/Support/SpyGmailAuth.swift` — test double for `GmailAuthPort`
- [ ] `MyHomeTests/Support/SpyKeychainStore.swift` — test double for `KeychainPort`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real OAuth browser flow | ING-01 | ASWebAuthenticationSession sheet + user consent; no automation | UAT-6-01/02: Tap "Connect Gmail" → sheet appears → complete sign-in → returns to app |
| Real Gmail fetch (newer_than:30d) | ING-02 | Live Google API + real account | UAT-6-03: After OAuth → sync completes; timestamp updates |
| Manual "Sync now" round-trip | ING-03 | Live network | UAT-6-04: Tap Sync now → syncing → done; timestamp updates |
| Last-synced always visible | ING-05 | UI placement | UAT-6-05: Timestamp visible in Settings even when "Never" |
| 7-day refresh expiry CTA | ING-16 | Requires real elapsed time / device | UAT-6-06: After Testing-mode expiry, Settings shows reconnect CTA |
| Real Keychain write on device | SEC-03 | Entitlement-gated; not in plain test bundle | UAT-6-07: Verify Keychain item exists post-sign-in (Instruments/device) |
| Sign-out + reconnect end-to-end | SET-04 | Full UI + network flow | UAT-6-08/09: Sign out → button reappears, no token → reconnect → new token, sync completes |
| OAuth cancel handling | D6-19 | User-driven cancel path | UAT-6-10: Cancel mid-flow → "Try again" shown, no crash/stuck state |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
