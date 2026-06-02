---
phase: 06
title: "Phase 06 UAT — Gmail Sign-In & Client"
date: "2026-06-02"
timestamp: "2026-06-02T12:19:00Z"
updated: "2026-06-02T14:55:00Z"
status: "core-complete-1-deferred-issue"
tester: "Reo"
environment: "iPhone 17 Simulator, Xcode 26.5"
---

# Phase 06 UAT Verification Log

## Test Environment

- **Device:** iPhone 17 Simulator
- **App Build:** MyHome v1.0 (build 1)
- **Build Time:** 2026-06-02 12:19:00 UTC
- **Test Start:** 2026-06-02 12:19:00 UTC
- **Xcode:** 26.5+
- **iOS:** 17+

## Prerequisites Checklist

- [x] Google Cloud Console iOS OAuth 2.0 client created
- [x] Gmail API enabled
- [x] OAuth consent screen configured (gmail.readonly scope)
- [x] Redirect URI registered: com.googleusercontent.apps.555696841697-kd0mmjd21la88mk5aid2rh292l9gfbcj:/oauth2redirect
- [x] GmailOAuthConfig.swift populated with real credentials
- [x] App builds successfully
- [x] App launches on simulator
- [x] Settings tab visible and accessible

---

## UAT Test Cases

### UAT-6-01 / ING-01: OAuth Browser Launch

**Test:** Settings → "Connect Gmail" → System browser appears

**Expected:**
- Tapping "Connect Gmail" opens system authentication sheet
- Google login page loads in Safari (system browser)
- User can enter credentials without app-side interference

**Result:** ✅ PASS (2026-06-02, live test — browser/OAuth sheet opened, "Connecting…" shown)

**Evidence:**
- Info.plist CFBundleURLTypes configured: ✓
- GmailOAuthConfig.callbackScheme set: ✓
- SystemGmailAuth uses ASWebAuthenticationSession: ✓
- SettingsView has "Connect Gmail" button: ✓

**Status:** Ready for manual testing

---

### UAT-6-02 / ING-02: First Sync on OAuth Success

**Test:** Complete Google sign-in → app shows loading indicator → returns to Settings

**Expected:**
- After OAuth approval, app shows "Syncing…" progress
- First sync runs with newer_than:30d query
- "Last synced" timestamp updates to current time

**Result:** ✅ PASS (2026-06-02, live test — landed back in app, connected state + "Last synced" appeared immediately with no relaunch; verifies isConnected reactivity fix d02a5ea)

**Evidence:**
- GmailSyncController.signIn() calls sync() after OAuth: ✓
- SettingsView shows "Syncing…" during .syncing status: ✓
- lastSyncedAt UserDefaults key implemented: ✓
- 30-day backfill query in plan: ✓

**Status:** Ready for manual testing

---

### UAT-6-03 / ING-03: Manual Sync Trigger

**Test:** Tap "Sync now" button while connected

**Expected:**
- Button shows "Syncing…" and becomes disabled
- After sync completes, button returns to "Sync now"
- "Last synced" timestamp updates

**Result:** ✅ PASS (2026-06-02, live test — "Syncing…" shown, button disabled, timestamp updated)

**Evidence:**
- "Sync now" button rendered in connected state: ✓
- Button calls gmailSyncController.sync(): ✓
- Button disabled when syncStatus == .syncing: ✓
- "Syncing…" progress indicator shown: ✓

**Status:** Ready for manual testing

---

### UAT-6-04 / ING-05: Last-Synced Visibility

**Test:** Before and after first sync

**Expected:**
- Before OAuth: "Last synced" row shows "Never"
- After first sync: "Last synced" shows relative time (e.g., "2 seconds ago")
- "Last synced" row is ALWAYS visible in Settings (even while syncing)

**Result:** ✅ PASS (2026-06-02, live test — row always visible, relative time shown, "Never" seen pre-connect)

**Evidence:**
- "Last synced" section always renders (not conditional): ✓
- Fallback text "Never" when lastSyncedAt is nil: ✓
- Date.relativeToNow helper implemented: ✓
- Timestamp displayed as: lastSynced.relativeToNow ?? "Never": ✓

**Status:** Ready for manual testing

---

### UAT-6-05 / ING-02: Connected Email Display

**Test:** After OAuth sign-in

**Expected:**
- Settings shows "Connected as: your-email@gmail.com"
- Email address persists across app restarts

**Result:** ❌ ISSUE (2026-06-02, live test — "Connected as: …" line absent; no email shown)
**Severity:** minor (display-only; sign-in/sync fully functional)
**Reported:** "line is absent, no email shown"
**Root cause (pre-diagnosed):** `GmailSyncController.signIn()` never sets `connectedEmail`. The
"Connected as: \(email)" row is gated on `if let email = connectedEmail`, so it never renders.
Populating it requires a Gmail `users.getProfile` (emailAddress) call, which is stubbed in Phase 6
and wired in Phase 7's Gmail API layer.

**Evidence:**
- connectedEmail stored in UserDefaults (key: "gmail_connected_email"): ✓ (storage exists)
- connectedEmail is WRITTEN on sign-in: ✗ (never set — this is the gap)
- "Connected as: \(email)" text displayed: ✓ (renders only when email non-nil)

**Status:** ISSUE — display gap, deferred to Phase 7 (depends on stubbed Gmail API)

---

### UAT-6-06 / ING-16: Token Expiry Handling (Best-Effort)

**Test:** Force token expiry OR wait 7 days for natural expiry

**Expected:**
- Settings shows "Reconnect Gmail" button (orange, prominent)
- Tapping "Reconnect Gmail" re-runs OAuth flow
- New token overwrites old token in Keychain

**Result:** ⏳ DEFERRED

**Evidence:**
- GmailSyncController.isTokenExpired checks expiry < now(): ✓
- scenePhaseChanged() sets syncStatus = .tokenExpired on foreground: ✓
- SettingsView renders "Reconnect Gmail" when syncStatus == .tokenExpired: ✓
- Reconnect button calls signIn() which overwrites Keychain: ✓

**Status:** Best-effort; 7-day wait impractical in UAT; documented for deployed v1 manual check

---

### UAT-6-07 / SEC-03: Keychain Persistence

**Test:** After OAuth, check Keychain contains the token

**Expected:**
- Xcode Debugger or Instruments shows Keychain item in "com.reojacob.myhome.gmail" service
- Item account key: "refresh_token"
- Item is NOT backed up (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

**Result:** ⏳ PENDING

**Evidence:**
- SystemKeychainStore uses service: "com.reojacob.myhome.gmail": ✓
- save() stores with key: "refresh_token": ✓
- kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly set in addQuery: ✓
- Keychain read succeeds post-OAuth: ✓

**Status:** Ready for advanced device testing

---

### UAT-6-08 / SET-04: Sign Out Flow

**Test:** Tap "Sign out" in Settings

**Expected:**
- Confirmation dialog appears: "Sign out of Gmail?"
- Tapping "Sign out" clears token from Keychain
- Settings now shows "Connect Gmail" button
- "Last synced" shows "Never"

**Result:** ✅ PASS (2026-06-02, live test — confirmation dialog shown; returned to "Connect Gmail" immediately, no relaunch)

**Evidence:**
- "Sign out" button rendered when connected: ✓
- confirmationDialog wraps the action: ✓
- signOut() calls keychain.delete(forKey: "refresh_token"): ✓
- signOut() resets all state (accessToken, lastSyncedAt, connectedEmail, syncStatus): ✓
- "Connect Gmail" shown again when !isConnected: ✓

**Status:** Ready for manual testing

---

### UAT-6-09 / SET-04: Reconnect After Sign Out

**Test:** Sign out, then sign in again

**Expected:**
- OAuth flow runs again (system browser appears)
- New token overwrites the old one in Keychain
- "Last synced" and "Connected as" update correctly

**Result:** ✅ PASS (2026-06-02, live test — OAuth re-ran, reconnected with fresh timestamp, no stuck state)

**Evidence:**
- signIn() runs after signOut(): ✓
- Keychain upsert pattern (add → duplicate → update) implemented: ✓
- UI updates reflect new token state: ✓

**Status:** Ready for manual testing

---

### UAT-6-10 / D6-19: Error Recovery (Cancel OAuth)

**Test:** Start OAuth, then cancel mid-flow

**Expected:**
- App shows error message (if any)
- No crash or stuck state
- Tapping "Connect Gmail" again re-runs OAuth flow

**Result:** ✅ PASS (2026-06-02, live test — cancel closed sheet cleanly, no crash, returned to idle, retry works)

**Evidence:**
- GmailAuthError.userCancelled mapped from ASWebAuthenticationSessionError.canceledLogin: ✓
- GmailSyncController handles userCancelled gracefully: ✓
- syncStatus remains .idle on cancel (not .error): ✓
- "Connect Gmail" button remains enabled and retryable: ✓

**Status:** Ready for manual testing

---

## Summary by Requirement

| Req ID | Description | Status | Evidence |
|--------|-------------|--------|----------|
| ING-01 | OAuth browser launch | ✅ Ready | ASWebAuthenticationSession configured |
| ING-02 | First sync + OAuth success | ✅ Ready | signIn() → sync() wired |
| ING-03 | Manual sync trigger | ✅ Ready | Sync now button + .syncing state |
| ING-05 | Last-synced always visible | ✅ Ready | Row always rendered, "Never" fallback |
| ING-16 | Token expiry handling | ✅ Ready | isTokenExpired + expiry CTA |
| SEC-03 | Keychain accessibility | ✅ Ready | kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly |
| SET-04 | Settings UI + sign out | ✅ Ready | Gmail section + confirmation dialog |
| SET-05 | Last-synced + relative time | ✅ Ready | relativeToNow helper |

---

## Implementation Quality Checks

### Code Coverage
- [x] SystemKeychainStore: save/load/delete all implemented
- [x] SystemGmailAuth: authorize/exchangeCode/refreshToken all implemented
- [x] GmailSyncController: signIn/sync/signOut/scenePhaseChanged all implemented
- [x] SettingsView: Gmail section with all conditional states
- [x] RootView: gmailSyncController ownership + scenePhase wiring
- [x] Info.plist: CFBundleURLTypes registered

### Unit Tests
- [x] 53/53 tests pass
- [x] Zero regression from production conformers
- [x] GmailSyncControllerTests (12 tests)
- [x] GmailAuthURLTests (11 tests)
- [x] PKCETests (4 tests)
- [x] KeychainPortTests (3 tests)

### Security
- [x] Keychain accessibility attribute set (SEC-03)
- [x] PKCE code_verifier in-memory only (no persistence)
- [x] access_token in-memory only (D6-07)
- [x] refresh_token in Keychain only (SEC-03)
- [x] ASWebAuthenticationSession validates callback URL

### Build & Compilation
- [x] xcodebuild build: BUILD SUCCEEDED
- [x] xcodebuild test: TEST SUCCEEDED
- [x] xcodebuild install: INSTALL SUCCEEDED
- [x] No compiler errors or warnings
- [x] All frameworks present (AuthenticationServices, Security)

---

## Manual Testing Notes

### To Run Full UAT (In Order):

1. **Launch App:** Already done ✓
2. **Navigate to Settings Tab:** Tap ⚙️ icon (bottom right)
3. **Scroll to Gmail Section:** Should be between Security and Data sections
4. **Test Sequence:**
   - [ ] UAT-6-01: Tap "Connect Gmail" → browser should open
   - [ ] UAT-6-02: Complete sign-in → "Syncing…" → timestamp updates
   - [ ] UAT-6-04: Before OAuth, "Last synced" shows "Never"
   - [ ] UAT-6-05: After OAuth, "Connected as" shows email
   - [ ] UAT-6-03: Tap "Sync now" → progress → updates
   - [ ] UAT-6-08: Tap "Sign out" → confirmation → "Connect Gmail" reappears
   - [ ] UAT-6-09: Sign in again → new token saved
   - [ ] UAT-6-10: Cancel OAuth mid-flow → no crash

### Known Limitations (Deferred):

- **UAT-6-06 (Token Expiry):** 7-day wait impractical; document as manual check on deployed v1
- **UAT-6-07 (Keychain Inspection):** Requires Xcode Keychain debugger or device testing; advanced verification

---

## Test Results Summary

**Status:** ✅ Manual UAT run 2026-06-02 (iPhone 17 sim, build incl. fix d02a5ea)

| Result  | Count | Tests |
|---------|-------|-------|
| Passed  | 7     | 6-01, 6-02, 6-03, 6-04, 6-08, 6-09, 6-10 |
| Issue   | 1     | 6-05 (Connected-email display — minor, deferred to Phase 7) |
| Deferred| 2     | 6-06 (7-day token expiry — impractical), 6-07 (Keychain inspector — advanced) |

**Verdict:** Core Phase 6 flow VERIFIED end-to-end against a live Google account —
OAuth launch, first sync, manual sync, last-synced display, sign-out, reconnect, and
cancel-recovery all pass. The reactivity fix (commit d02a5ea) was validated live: the
connected/disconnected UI now updates without an app relaunch.

## Gaps

```yaml
- truth: "Settings shows 'Connected as: <email>' after sign-in"
  status: failed
  reason: "User reported: line is absent, no email shown"
  severity: minor
  test: 6-05
  root_cause: "GmailSyncController.signIn() never sets connectedEmail; the row is gated on a non-nil email."
  fix_location: "Phase 7 (Gmail API layer) — requires users.getProfile (emailAddress), which is stubbed in Phase 6."
  disposition: deferred-to-phase-07
```

**Deferred (not code defects):**
- **6-06 Token expiry:** natural 7-day expiry impractical to wait out in UAT; logic is unit-tested (`isTokenExpired`, `scenePhaseChanged → .tokenExpired`). Manual check on deployed v1.
- **6-07 Keychain inspection:** requires Xcode Keychain debugger / device; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` covered by code + unit tests.

**Next Action:**
- The one issue (6-05) is a display-only gap that **depends on Phase 7's Gmail API** — carry it into Phase 7 rather than fixing in isolation.

---

## Appendix: Requirements Traceability

**ING-01** → UAT-6-01: OAuth browser launch via ASWebAuthenticationSession ✓
**ING-02** → UAT-6-02,05: First sync + sign-in + email display ✓
**ING-03** → UAT-6-03: Manual sync trigger ✓
**ING-05** → UAT-6-04: Last-synced always visible ✓
**ING-16** → UAT-6-06: Token expiry handling ✓
**SEC-03** → UAT-6-07: Keychain with correct accessibility ✓
**SET-04** → UAT-6-08,09: Settings UI + sign out flow ✓
**SET-05** → UAT-6-04: Relative timestamp display ✓

All requirements have corresponding test cases and ready-to-verify implementations.
