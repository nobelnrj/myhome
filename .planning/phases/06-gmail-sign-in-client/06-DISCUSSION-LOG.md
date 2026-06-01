# Phase 6: Gmail Sign-In & Client - Discussion Log

**Session:** 2026-06-02  
**Participants:** User (visionary), Agent (builder)

---

## Discussion Areas & Outcomes

### Area 1: OAuth Library & PKCE Flow

**Objective:** Determine OAuth authentication approach.

**Questions & Decisions:**

| Question | Options | Selection | Rationale |
|----------|---------|-----------|-----------|
| OAuth library choice? | ASWebAuthenticationSession only, Google SignIn SDK, Other | **ASWebAuthenticationSession only** | REQUIREMENTS.md mandates "no Google SDK"; built-in, secure, zero-dependency approach |
| PKCE implementation? | Custom scheme + PKCE state, ASWebAuthenticationSession built-in, Other | **Custom scheme + PKCE state** | User preference for control and visibility into state being passed |
| Gmail scope? | gmail.readonly only, gmail.compose, Other | **gmail.readonly only** | Minimum privilege; no compose in v1; satisfies ING-01 |

**Decisions captured:**
- D6-01: ASWebAuthenticationSession (no SDK)
- D6-02: Custom PKCE implementation
- D6-03: gmail.readonly scope
- D6-04: iOS custom scheme redirect URI

---

### Area 2: Token Lifecycle & Refresh

**Objective:** Determine token storage and refresh strategy.

**Questions & Decisions:**

| Question | Options | Selection | Rationale |
|----------|---------|-----------|-----------|
| Token storage location? | Keychain with `AfterFirstUnlockThisDeviceOnly`, UserDefaults, Other | **Keychain with `AfterFirstUnlockThisDeviceOnly`** | SEC-03 requirement; encrypted at rest; secure by default |
| Refresh strategy? | Store refresh token + expiry, proactive check; Store refresh token + access token, lazy refresh on 401 | **Proactive (expiry + pre-check)** | Avoids 401 mid-sync; cleaner error handling; user confident in state |

**Decisions captured:**
- D6-05: Keychain storage with explicit accessibility attribute
- D6-06: Proactive access-token refresh (check expiry before sync)
- D6-07: Access token in memory only (no disk persistence)

---

### Area 3: Sync Trigger Strategy

**Objective:** Determine when/how email ingestion is triggered.

**Questions & Decisions:**

| Question | Options | Selection | Rationale |
|----------|---------|-----------|-----------|
| Sync triggers in Phase 6? | Manual "Sync now" button only, Manual + Background tasks | **Manual "Sync now" button only** | Isolates OAuth testing from background complexity; BGAppRefreshTask deferred to Phase 7 |
| First sync timing? | Immediate on OAuth success, User-triggered later | **Immediate on OAuth success** | Validates token works; user sees updated timestamp upon sign-in completion |
| Backfill window? | 30 days, 90 days, All | **30 days (newer_than:30d)** | Limits initial payload; reasonable for first sync; subsequent syncs use incremental timestamp |

**Decisions captured:**
- D6-08: Immediate first sync on OAuth success
- D6-09: Manual "Sync now" button in Settings
- D6-10: 30-day backfill on first sync

---

### Area 4: Settings UI Integration

**Objective:** Determine how Gmail integration appears in Settings.

**Questions & Decisions:**

| Question | Options | Selection | Rationale |
|----------|---------|-----------|-----------|
| OAuth flow presentation? | Modal sheet overlay (ASWebAuthenticationSession), In-app Safari, Custom | **Modal sheet overlay (ASWebAuthenticationSession)** | System-owned, secure by default; handles entire flow |
| Gmail section content? | Connected email + timestamp + sync button + sign-out, Simplified version | **Full: email + timestamp + sync + sign-out** | User clarity; manual control; satisfies SET-04/05, ING-05 |

**Decisions captured:**
- D6-14: Gmail section with connected email, timestamp, sync button, sign-out
- D6-15: "Connect Gmail" button when not connected
- D6-16: Relative timestamp ("2 hours ago")
- D6-17: Sign-out clears Keychain + UserDefaults

---

### Area 5: Error Recovery & Token Expiry

**Objective:** Determine error handling and token expiry behavior.

**Questions & Decisions:**

| Question | Options | Selection | Rationale |
|----------|---------|-----------|-----------|
| Token expiry detection? | Automatic / proactive check, Reactive on sync failure | **Automatic / proactive** | Catches expiry immediately (v1 testing = 7 days); user knows before attempting sync |
| Error message style? | User-friendly ("Couldn't sign in"), Raw OAuth error (for debugging) | **Raw OAuth error** | Easier debugging during v1 testing; helpful during development |

**Decisions captured:**
- D6-11: Proactive expiry check on Settings foreground
- D6-12: Reconnect flow (full OAuth again)
- D6-13: Sync-time expiry handling (refresh fails, show reconnect)
- D6-19: Show raw OAuth error messages (v1 testing phase)

---

## Deferred Ideas

No new capabilities were proposed that exceeded Phase 6 scope.

---

## Gray Areas Explored

1. ✅ OAuth library & PKCE flow
2. ✅ Token lifecycle & refresh
3. ✅ Sync trigger strategy
4. ✅ Settings UI integration
5. ✅ Error recovery & token expiry

**Total areas:** 5  
**All areas explored:** Yes  
**Convergence:** Achieved; decisions locked

---

## User Preferences & Rationale

- **Security-first:** Keychain + proactive refresh pattern
- **Debugging-friendly:** Raw error messages (testing phase benefit)
- **Control:** Custom PKCE (not black-box library)
- **Isolation:** No background tasks in Phase 6 (proof-of-concept OAuth first)
- **Clarity:** Relative timestamps + visible sync state

---

## Integration Points with Prior Phases

- **Phase 5 (Settings shell):** Phase 6 slots Gmail section into existing clean Settings structure (no displacement)
- **Phase 1 (App Group UserDefaults):** Reuses existing App Group suite for sync metadata
- **Phase 5 (RootView scenePhase):** Reuses existing wiring for expiry check on foreground

---

## Next Actions

1. **Plan Phase 6** → `/gsd-plan-phase 6`
2. **Research URL/OAuth patterns** (researcher reads 06-CONTEXT.md)
3. **Create implementation plan** (planner breaks decisions into executable tasks)
4. **Execute Phase 6 plans** → OAuth implementation, Settings integration, sync proof

---

*Session completed: 2026-06-02*
