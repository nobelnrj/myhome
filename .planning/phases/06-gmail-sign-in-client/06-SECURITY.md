---
phase: 06
slug: gmail-sign-in-client
status: verified
threats_open: 0
asvs_level: high
created: 2026-06-02
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time (all 4 PLAN.md files carried `<threat_model>` blocks);
> this audit verified mitigations exist in the implementation.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| app → Google authorization endpoint | `buildAuthorizationURL` constructs the URL the system browser opens | PKCE challenge, state (CSRF nonce) |
| app ↔ system browser (ASWebAuthenticationSession) | credentials entered in OS-owned browser, never in app code | user Google credentials |
| OS ↔ app via custom URL scheme | OAuth callback redirect (reverse-client-ID scheme) | authorization code, state |
| controller → KeychainPort | refresh token crosses into secure storage | refresh_token (secret) |
| controller → GmailAuthPort | access/refresh tokens from Google flow | access_token (in-memory), refresh_token |
| app ↔ Google token/Gmail endpoints | network; HTTPS only via URLSession | tokens, email metadata |
| app ↔ Keychain | refresh token at rest | refresh_token (secret) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-06-W0-01 | Tampering | pbxproj build phase | mitigate | Broken pbxproj fails `xcodebuild test`, gating commit | closed |
| T-06-W0-02 | Information Disclosure | Wave-0 stub token persistence | mitigate | No real tokens in Wave 0; access token in-memory `var`, refresh only via in-memory spy | closed |
| T-06-PKCE | Spoofing/Elevation | `PKCE.generate()` | mitigate | `SecRandomCopyBytes` (CSPRNG) + CryptoKit `SHA256` per RFC 7636; no `arc4random`/`drand48`; verifier length asserted by PKCETests — verified `MyHomeApp/Gmail/PKCE.swift:34,46` | closed |
| T-06-CSRF | Tampering | OAuth `state` round-trip | mitigate | `state` (UUID) embedded in auth URL **and now validated on callback**: `SystemGmailAuth.authorize` rejects any callback whose `state` ≠ expected (`GmailAuthError.stateMismatch`); bound via `signIn(expectedState:)` — verified `GmailAuthPort.swift` + `GmailSyncController.swift`; covered by `signInPassesGeneratedStateToAuthorize`, `signInRejectsStateMismatch` | closed |
| T-06-SCOPE | Elevation of Privilege | scope param | mitigate | Scope hardcoded to `gmail.readonly` (D6-03); asserted by GmailAuthURLTests — verified `GmailSyncController.buildAuthorizationURL` | closed |
| T-06-TOKEN | Information Disclosure | refresh/access token handling | mitigate | `refresh_token` → `keychain.save` only (never UserDefaults); `accessToken` in-memory `var` (D6-07); only expiry timestamp persisted; `signOut` deletes Keychain item — verified `GmailSyncController.swift` | closed |
| T-06-EXPIRE | Denial of Service | stale token blocking sync | mitigate | Proactive 5-min refresh (D6-06) + `invalid_grant` → `.tokenExpired` reconnect CTA (ING-16) | closed |
| T-06-04-KEYCHAIN | Information Disclosure | `SystemKeychainStore` | mitigate | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (SEC-03) prevents backup/restore exfiltration — verified `MyHomeApp/Gmail/KeychainPort.swift:83` | closed |
| T-06-04-CALLBACK | Spoofing | custom URL scheme callback | mitigate | ASWebAuthenticationSession validates returned URL matches registered scheme; **`state` now validated** (see T-06-CSRF); reverse-client-ID scheme | closed |
| T-06-04-CODEINTERCEPT | Spoofing/Elevation | authorization code interception | mitigate | PKCE `code_verifier` passed to `exchangeCode` makes an intercepted code useless — verified `GmailAuthPort.swift` exchange path | closed |
| T-06-SC | Tampering | package installs (supply chain) | accept | Zero external packages; all first-party Apple frameworks (CryptoKit/Security/AuthenticationServices) + raw Google REST | closed |
| T-06-RAWERR | Information Disclosure | D6-19 raw Google error display | accept | Owner-chosen debug-friendly raw error display; single-user private app, errors shown only in-app to the owner | closed |
| T-06-04-PII | Information Disclosure | connected-email userinfo fetch | accept | Single email shown only to the app owner; `gmail.readonly` scope; no broader PII (and not yet implemented — deferred to Phase 7) | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-06-01 | T-06-SC | No third-party packages introduced this phase; only first-party Apple frameworks + raw Google REST. No supply-chain surface. | Reo | 2026-06-02 |
| AR-06-02 | T-06-RAWERR | Raw Google OAuth error strings surfaced in-app for debuggability; single-user private app, never shown to third parties. | Reo | 2026-06-02 |
| AR-06-03 | T-06-04-PII | Connected email is the owner's own address, shown only to the owner; `gmail.readonly` scope. (Display itself deferred to Phase 7.) | Reo | 2026-06-02 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-02 | 13 | 13 | 0 | /gsd-secure-phase (orchestrator-verified) |

**Finding & remediation:** Initial audit found `T-06-CSRF` / `T-06-04-CALLBACK` **OPEN** — the OAuth `state` nonce was generated and sent but never validated on the callback (mitigation promised in the plan-time register was absent). Remediated in commit on 2026-06-02: added `expectedState` to `GmailAuthPort.authorize`, `GmailAuthError.stateMismatch`, callback validation in `SystemGmailAuth`, error surfacing in `GmailSyncController.signIn`, and two regression tests. Re-verified CLOSED.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-02
