# Phase 6: Gmail Sign-In & Client - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver **OAuth sign-in + token storage + manual sync** — proving the riskiest network/auth 
sub-system in isolation before Phase 7 tackles the parsers and ingestion pipeline.

**In scope (ING-01, ING-02, ING-03, ING-05, ING-16, SEC-03, SET-04, SET-05):**

1. **ING-01 (OAuth)** — User can sign in to Gmail via `ASWebAuthenticationSession` + custom PKCE, 
   scope = `gmail.readonly` only
2. **SEC-03 (Token storage)** — Refresh token stored in Keychain with 
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
3. **ING-02 (First sync)** — Initial backfill on OAuth success, bounded to `newer_than:30d`
4. **ING-03 (Manual sync)** — User can trigger "Sync now" from Settings
5. **ING-05 (Last-synced)** — Settings shows "Last synced at …" timestamp (always visible)
6. **SET-04/05 (Reconnect)** — User can sign out and reconnect; "Reconnect Gmail" CTA on token expiry
7. **ING-16 (Expiry CTA)** — When refresh token expires, show clear reconnect prompt

**Out of scope (later phases):**
- **Bank email parsers / confidence scoring** (Phase 7)
- **Review Inbox** (Phase 7)
- **BGAppRefreshTask registration** (Phase 7 introduces background tasks)
- **Merchant deduplication** (Phase 7)
- **Multi-email-account support** — v1 is single Gmail account only
- **Email search/filtering logic** — Phase 6 fetches raw, Phase 7 filters

**Schema constraint:** Phase 6 introduces **no new `@Model` types.** Sync metadata 
(last_synced_at, sync_status) lives in `UserDefaults`; tokens live in Keychain.

</domain>

<decisions>
## Implementation Decisions

### OAuth Setup — ING-01 (discussed)

- **D6-01 (Library):** Use **`ASWebAuthenticationSession`** (no Google SignIn SDK). 
  - ✅ Built into iOS, zero external dependencies
  - ✅ PKCE-capable (iOS 13.7+)
  - ✅ System-owned sheet, secure by default
  
- **D6-02 (PKCE):** Implement **custom PKCE state** for full control.
  - Generate `code_verifier` (43-128 chars, unreserved chars)
  - Compute SHA256 `code_challenge` = BASE64(SHA256(code_verifier))
  - Pass both to ASWebAuthenticationSession
  - Verify `code_verifier` matches on callback
  - *Rationale (user):* "I want visibility into the state being passed around"
  
- **D6-03 (Scope):** **`gmail.readonly` scope only** — read emails, no compose capability.
  - Minimal privilege principle
  - No future expansion needed for v1

- **D6-04 (Redirect URI):** Use iOS custom scheme (e.g., `myhome-oauth://callback`).
  - ASWebAuthenticationSession handles deep-link return automatically
  - Registered in Xcode project + Info.plist

### Token Storage & Refresh Lifecycle — SEC-03, ING-02 (discussed)

- **D6-05 (Keychain storage):** Store refresh token in Keychain with 
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - ✅ Encrypted at rest
  - ✅ Not accessible while device locked
  - ✅ Survives app updates
  - ❌ NOT `WhenUnlocked` (too strict; app can't run background tasks)
  - ❌ NOT `biometryCurrentSet` (overkill for a financial app)
  
- **D6-06 (Refresh strategy):** **Proactive access-token refresh** using expiry time.
  - Store: `refresh_token` (in Keychain) + `access_token_expiry` (in UserDefaults, timestamp)
  - Before each sync request: check if expiry is within 5 minutes; if so, refresh
  - Call `/token` endpoint with refresh_token to get new access_token + expiry
  - *Rationale:* Avoids 401 failures mid-sync; cleaner error handling
  
- **D6-07 (Access token storage):** Store current `access_token` **in memory only** (not persisted).
  - Each app launch, access_token is empty → triggers refresh on first sync
  - No disk exposure for short-lived tokens
  - Refreshed before each request (per D6-06)

### Sync Trigger Strategy — ING-02, ING-03 (discussed)

- **D6-08 (First sync):** **Immediate sync on OAuth success** (before closing the sign-in flow).
  - After token exchange, immediately fetch emails from `newer_than:30d`
  - Show loading indicator during fetch
  - Store `last_synced_at` timestamp
  - If fetch succeeds: dismiss sign-in, return to Settings (user sees updated timestamp)
  - If fetch fails: stay on sign-in screen with error + Retry button
  - *Rationale:* Validates token immediately; user knows OAuth works
  
- **D6-09 (Manual sync):** "Sync now" button in Settings Gmail section.
  - User can trigger fetch at any time from Settings
  - Shows loading state, then result (timestamp updated or error)
  - No background tasks in Phase 6; Phase 7 adds BGAppRefreshTask
  
- **D6-10 (30-day backfill):** First sync fetches emails with `newer_than:30d` only.
  - Limits initial payload (don't fetch years of emails)
  - Subsequent syncs use `newer_than:[last_synced_at]` (Phase 7 logic)

### Token Expiry & Reconnect — ING-16 (discussed)

- **D6-11 (Proactive expiry check):** Check token validity on app foreground (Settings tab open).
  - When user opens Settings (or navigates to it), check if refresh_token_expiry < now
  - If expired: show "Gmail connection expired. Tap to reconnect." banner
  - Tapping the banner re-initiates OAuth flow (same as "Connect Gmail" button)
  - *Rationale:* Catches expiry immediately (Testing mode = 7 days; prod = ~45 days)
  
- **D6-12 (Reconnect flow):** Reconnect button / banner initiates full OAuth again.
  - User signs in again
  - New refresh token is stored (overwrites old)
  - Immediate first sync (D6-08 applies)
  
- **D6-13 (Sync-time expiry):** If "Sync now" is tapped and token is expired.
  - Proactive refresh (D6-06) returns 401 or refresh fails
  - Show alert: "Gmail connection expired. Sign in again?" + "Sign in" button
  - Tapping "Sign in" initiates OAuth (D6-12)

### Settings UI Integration — SET-04, SET-05 (discussed)

- **D6-14 (Gmail section content):** Settings > Gmail section shows:
  ```
  🔗 Connected as: user@gmail.com  (or "Not connected" if signed out)
  ⏰ Last synced: 2 hours ago       (or "Never" if no sync yet)
  🔄 Sync now [button]              (disabled if already syncing)
  🔓 Sign out [link]                (hidden if not connected)
  ```
  
- **D6-15 (Sign-in button):** If not connected, show "Connect Gmail" button instead of the section.
  - Tapping initiates ASWebAuthenticationSession
  - After successful OAuth, Gmail section replaces the button
  
- **D6-16 (Last-synced timestamp):** Display format = "Last synced 2 hours ago" (relative).
  - Use DateComponentsFormatter for human-readable relative time
  - If sync is in progress, show "Syncing..." state
  - After sync: timestamp updates immediately

- **D6-17 (Sign-out behavior):** Tapping "Sign out":
  - Removes refresh token from Keychain
  - Clears access_token_expiry from UserDefaults
  - Shows confirmation: "Gmail account disconnected. No more email ingestion until you sign in again."
  - Gmail section disappears; "Connect Gmail" button reappears

### Error Handling — Phase 6 scope (discussed)

- **D6-18 (Network errors):** No internet connection detected.
  - Show: "Check your internet connection. [Retry]"
  - User can retry once connection returns
  
- **D6-19 (OAuth errors):** ASWebAuthenticationSession fails or user cancels.
  - Display **raw error message from Google** (for debugging during v1 testing)
  - Example: "OAuth error: access_denied — The user denied the sign-in"
  - Include "Try again" button
  - *Rationale (user):* "Show me what Google returns; easier to debug"
  
- **D6-20 (Keychain errors):** Can't read/write token to Keychain.
  - Show: "Couldn't save your Gmail credentials. Please try again."
  - Log actual error for debugging
  - User can retry OAuth
  
- **D6-21 (API errors during sync):** Gmail API returns 4xx / 5xx (e.g., 403, 500).
  - Show: "[Error code]: [Error message from Gmail]" + "Retry" button
  - 403 = scope issue (shouldn't happen if D6-03 is followed)
  - 500 = transient; user can retry

### Architectural Constraints & Patterns

- **D6-22 (No schema migration):** Phase 6 introduces no new `@Model` types.
  - Sync metadata (`last_synced_at`, `sync_status`) stored in App Group UserDefaults
  - Tokens stored in Keychain (no model persistence)
  
- **D6-23 (TDD seam — future):** Wrap `URLSession` / OAuth API calls behind a port/protocol.
  - Enables mocking during tests
  - Phase 6 implementation; Phase 7 adds parser testing (which reuses this seam)
  - Do NOT introduce fake OAuth in v1; use real OAuth + TestFlight testing
  
- **D6-24 (URLSession configuration):** Use standard `URLSession.shared` for OAuth token exchange.
  - HTTPS only (automatic with URLSession)
  - Timeouts: 60s for OAuth token endpoint
  - No custom certificate pinning in v1

### Claude's Discretion (planner / UI-SPEC)

- **D6-25 (Loading UX):** How should "Syncing..." state be shown?
  - Spinner + "Syncing…" label in the timestamp area?
  - Disabled "Sync now" button during sync?
  - Both?
  - (Left to UI-SPEC)
  
- **D6-26 (Sign-in entry point):** Where does "Connect Gmail" appear in Settings?
  - Dedicated "Gmail" section?
  - Combined with other account-related options?
  - (Left to planner + UI-SPEC; must slot cleanly into Phase 5's clean Settings structure)
  
- **D6-27 (Keychain error recovery):** If Keychain permanently fails (rare), what's the user's escape hatch?
  - Show guidance to delete/reinstall the app?
  - (Left to planner; rare edge case)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirement & roadmap sources

- `.planning/REQUIREMENTS.md` — v1 requirements, ING-01 through ING-16, SEC-03, SET-04/05
- `.planning/ROADMAP.md` — Phase 6 goal, success criteria, dependencies on Phase 5
- `.planning/PROJECT.md` — Core value, developer context (Reo new to Swift), security posture

### Phase 5 context

- `.planning/phases/05-face-id-gate-settings/05-CONTEXT.md` — Phase 5 decisions; Settings shell ready, 
  no Gmail placeholders, clean structure

### Implementation references

- **Apple Security framework**: `AuthenticationServices.ASWebAuthenticationSession` docs (custom scheme 
  redirect, PKCE flow)
- **Apple Security framework**: `Security.SecItem...` (Keychain operations with `kSecAttrAccessible` parameters)
- **URLSession + OAuth 2.0**: RFC 6234 (SHA256), RFC 7636 (PKCE), RFC 6749 (OAuth 2.0)
- **Gmail API**: OAuth 2.0 scopes, `/token` endpoint for refresh, `/gmail/v1/users/messages/list` with 
  `q` parameter for email filtering

### Codebase patterns (reusable)

- Phase 3 `NotificationCenterPort` — Protocol-based seam for testing. Apply same pattern to 
  URLSession/OAuth client in Phase 6.
- Phase 5 `LockController` — @Observable pattern for state management. Consider for sync status.
- Existing `ModelContainer` factory (Phase 1) — no changes needed; Phase 6 data is UserDefaults + Keychain.

### Deferred Ideas

- Multi-account Gmail support (v2; requires schema changes, account picker UI)
- Email search / advanced filtering (v2; Phase 7 layers on top of Phase 6's raw fetch)
- Offline email caching (v2; out of scope for proof-of-concept)
- Custom OAuth client (v2; ASWebAuthenticationSession sufficient for v1)

</canonical_refs>

<codebase_context>
## Existing Code Context

### Reusable assets from earlier phases

- **NotificationCenterPort** (.../Features/Reminders/NotificationCenterPort.swift) — Protocol-based 
  seam for testable network/API calls. Mirrors this pattern for URLSession in Phase 6.
- **@Observable LockController** (.../Shared/LockController.swift) — State management pattern. 
  Consider for tracking sync status (syncing, last_synced_at, error).
- **App Group UserDefaults** (Phase 1 setup) — Already configured for App Group persistence. 
  Reuse for sync metadata.
- **Keychain helpers** (if any from Phase 5) — None written yet; Phase 6 creates helpers for token 
  storage (standard Security.framework calls).

### Integration points

- **Settings tab** (Phase 5) — Clean, no Gmail placeholder. Phase 6 adds Gmail section here.
- **RootView scenePhase wiring** (Phase 5) — Already has `@Environment(\.scenePhase)`. Phase 6 reuses 
  for expiry check on foreground.

</codebase_context>

---

**Next step:** `/gsd-plan-phase 6` to break this into executable plans.
