# Phase 6: Gmail Sign-In & Client — Research

**Researched:** 2026-06-02
**Domain:** iOS OAuth 2.0 + PKCE / ASWebAuthenticationSession / Keychain / Gmail REST API / Swift 6.2 strict concurrency
**Confidence:** HIGH (core APIs verified; one redirect-URI nuance flagged as MEDIUM)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D6-01**: Use `ASWebAuthenticationSession` (no Google SignIn SDK)
- **D6-02**: Custom PKCE — generate `code_verifier` (43-128 chars), compute SHA256 `code_challenge`, base64url-encode both
- **D6-03**: Scope = `gmail.readonly` only
- **D6-04**: Redirect URI = `myhome-oauth://callback` (custom iOS scheme) — **see Redirect URI Warning below**
- **D6-05**: Store refresh token in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- **D6-06**: Proactive access-token refresh: check expiry within 5 minutes before each sync request
- **D6-07**: `access_token` in memory only; `access_token_expiry` in App Group UserDefaults; `refresh_token` in Keychain
- **D6-08**: Immediate first sync on OAuth success — `newer_than:30d`, show loading indicator
- **D6-09**: "Sync now" button in Settings; no background tasks until Phase 7
- **D6-10**: First sync bounded to `newer_than:30d`; subsequent syncs use `newer_than:[last_synced_at]`
- **D6-11**: Check token validity on app foreground (Settings tab open); show "Gmail connection expired" banner if expired
- **D6-12**: Reconnect button re-initiates full OAuth + overwrites old token + immediate first sync
- **D6-13**: If "Sync now" and token is expired — show alert "Sign in again?" + trigger OAuth
- **D6-14**: Settings > Gmail section: Connected-as label, Last-synced timestamp, Sync now button, Sign out link
- **D6-15**: If not connected, show "Connect Gmail" button
- **D6-16**: Last-synced display format = "Last synced 2 hours ago" (relative)
- **D6-17**: Sign out removes refresh token from Keychain, clears expiry from UserDefaults
- **D6-18**: Network error → "Check your internet connection. [Retry]"
- **D6-19**: OAuth error → display raw error message from Google (debug-friendly)
- **D6-20**: Keychain error → "Couldn't save your Gmail credentials. Please try again."
- **D6-21**: Gmail API error → "[Error code]: [Error message from Gmail]" + Retry
- **D6-22**: No new `@Model` types; sync metadata in App Group UserDefaults; tokens in Keychain
- **D6-23**: Wrap `URLSession`/OAuth behind a port/protocol (mirrors `NotificationCenterPort`)
- **D6-24**: `URLSession.shared` with 60s timeout for OAuth token endpoint; no certificate pinning

### Claude's Discretion

- **D6-25**: Loading UX (spinner placement, "Syncing..." label, disabled button behaviour)
- **D6-26**: Where "Connect Gmail" appears in the Settings list structure
- **D6-27**: Keychain permanent-failure escape hatch (guidance to delete/reinstall app)

### Deferred Ideas (OUT OF SCOPE)

- Multi-account Gmail support
- Email search / advanced filtering (Phase 7 builds on Phase 6's raw fetch)
- Offline email caching
- Custom OAuth client
- BGAppRefreshTask (Phase 7)

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ING-01 | User can sign in to Gmail via `ASWebAuthenticationSession` + PKCE, scope = `gmail.readonly` only | ASWebAuthenticationSession + PKCE + Google OAuth endpoints documented in §Standard Stack and §Code Examples |
| ING-02 | First OAuth grant performs initial backfill bounded to `newer_than:30d` | Gmail API `q` parameter + D6-08 sync trigger flow documented in §Architecture Patterns |
| ING-03 | User can trigger ingestion on demand via "Sync now" in Settings | GmailSyncController pattern in §Architecture Patterns |
| ING-05 | Always-visible "Last synced at …" timestamp in Settings | `RelativeDateTimeFormatter` pattern in §Code Examples |
| ING-16 | When refresh token expires, show "Reconnect Gmail" CTA | Proactive expiry check + D6-11/13 flow in §Architecture Patterns |
| SEC-03 | Gmail OAuth refresh token stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Keychain wrapper pattern in §Standard Stack + §Code Examples |
| SET-04 | User can sign out of Gmail and reconnect | Sign-out/reconnect flow in §Architecture Patterns |
| SET-05 | Settings shows last-synced timestamp and manual "Sync now" button | GmailSyncController state + SettingsView integration in §Architecture Patterns |

</phase_requirements>

---

## Summary

Phase 6 proves the riskiest sub-system — Gmail OAuth + secure token storage + manual sync — in isolation before Phase 7 adds parsers and ingestion. The tech split is: (1) ASWebAuthenticationSession for the browser-based OAuth flow; (2) CryptoKit for custom PKCE math; (3) Security.framework for Keychain token storage; (4) URLSession for token exchange and Gmail REST calls; and (5) an `@Observable @MainActor` controller for sync state (mirroring Phase 5's LockController).

All of these are first-party Apple frameworks except the Gmail REST API itself — there is zero external dependency added in this phase, which aligns with the project's no-third-party-SDK constraint.

One critical redirect-URI finding is documented in the §Redirect URI Warning section: Google's documentation marks arbitrary custom URI schemes (like `myhome-oauth://callback`) as deprecated for iOS in favour of the reverse-client-ID scheme. The reverse-client-ID form (`com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect`) is still supported and is what all current Google OAuth examples for iOS use. The planner must decide whether to proceed with the locked D6-04 (`myhome-oauth://callback`) or adopt the reverse-client-ID pattern. This is a LOW-risk concern because the restriction targets Chrome Extensions and Android primarily, but it deserves a documented note.

**Primary recommendation:** Build `GmailSyncController` as a `@MainActor @Observable` class (exact mirror of `LockController`), with `GmailAuthPort` and `KeychainPort` protocol seams (exact mirror of `BiometricAuthPort`) injected at init. All async OAuth and network operations call through these ports, making every decision path unit-testable without hitting real OAuth or Keychain. Manual sign-in and sync validation is confirmed via TestFlight/device.

---

## Redirect URI Warning [MEDIUM confidence — verify before coding]

D6-04 locks the redirect URI to `myhome-oauth://callback`. Google's documentation for native apps states:

> "Custom URI schemes are no longer supported due to the risk of app impersonation."

**What is still allowed:** The **reverse-client-ID scheme** (`com.googleusercontent.apps.<YOUR_CLIENT_ID>:/oauth2redirect`) is explicitly listed as the iOS redirect URI in Cloud Console and in every current Google OAuth example for iOS (including AppAuth-iOS). This is distinct from arbitrary schemes and is actively supported. [CITED: developers.google.com/identity/protocols/oauth2/native-app]

**Risk assessment:** The ban primarily targets Chrome Extensions and Android. iOS with ASWebAuthenticationSession is not the primary enforcement target. Many iOS apps still use arbitrary schemes and they work. However, the redirect URI registered in Cloud Console must exactly match what the app sends — and if Google ever enforces stricter validation on the iOS client type, arbitrary schemes would be rejected server-side.

**Planner action:** Either:
1. Use the reverse-client-ID scheme as the registered redirect URI in Cloud Console and as the URL type in Xcode — this is zero additional code complexity and the safest choice.
2. Proceed with `myhome-oauth://callback` but document it as an `[ASSUMED]` decision; the flow will work in Testing mode.

The research recommendation is to use the reverse-client-ID scheme. However, since D6-04 is a locked user decision, the planner should flag this as a Wave 0 discussion point with Reo before coding begins. [ASSUMED: arbitrary custom scheme will continue to work for a private iOS app in Testing mode in the near term]

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OAuth browser flow | OS (ASWebAuthenticationSession) | GmailAuthPort protocol | System-owned browser handles credential entry securely; app only exchanges code |
| PKCE generation | App (pure logic) | — | Cryptographic math — no OS call except `SecRandomCopyBytes` |
| Token exchange (code → tokens) | App network layer (URLSession) | GmailAuthPort port | HTTPS POST to Google token endpoint; port seam enables mocking |
| Refresh token persistence | OS Keychain (Security.framework) | KeychainPort protocol | kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly per SEC-03 |
| Access token lifecycle | GmailSyncController (in-memory) | App Group UserDefaults (expiry only) | Short-lived token never touches disk; only expiry timestamp persisted |
| Sync state / last-synced | GmailSyncController (@Observable) | App Group UserDefaults | Mirrors LockController pattern for SwiftUI reactivity |
| Gmail API fetch | App network layer (URLSession) | GmailAuthPort port | Simple GET with Bearer header; port seam enables mocking |
| Settings UI | Frontend (SwiftUI SettingsView) | GmailSyncController binding | Adds Gmail section to existing Phase 5 SettingsView |
| Token expiry detection | GmailSyncController | scenePhase hook (RootView) | Proactive check on foreground mirrors LockController.scenePhaseChanged |

---

## Standard Stack

### Core (all first-party — zero new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `AuthenticationServices.ASWebAuthenticationSession` | iOS 12+ (13+ for `prefersEphemeralWebBrowserSession`) | OAuth browser flow | System-owned browser, no embedded WebView, handles redirect automatically [VERIFIED: Apple Docs] |
| `CryptoKit.SHA256` | iOS 13+ | PKCE `code_challenge` hashing | First-party, Sendable-compatible, no CommonCrypto import needed [ASSUMED: CryptoKit availability on iOS 17 well-established] |
| `Security` (SecItem*) | iOS 2+ | Keychain CRUD for refresh token | The only OS-level secure storage; no third-party wrapper needed [VERIFIED: Apple Docs] |
| `Foundation.URLSession` | iOS 7+ | Token exchange + Gmail API HTTP calls | Project already uses it; no new import [ASSUMED] |
| `Foundation.UserDefaults` | iOS 2+ | `access_token_expiry` + `last_synced_at` persistence | App Group suite already set up in Phase 1 [VERIFIED: existing code] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foundation.RelativeDateTimeFormatter` | iOS 13+ | "Last synced 2 hours ago" formatting | D6-16 timestamp display (note: CONTEXT.md names `DateComponentsFormatter` but `RelativeDateTimeFormatter` is the correct tool — it produces "X hours ago" natively) [CITED: hackingwithswift.com] |
| `Foundation.DateComponentsFormatter` | iOS 8+ | Duration formatting if needed | Only needed if formatting a duration, not a relative timestamp |
| `SwiftUI.@Environment(\.scenePhase)` | iOS 14+ | Foreground trigger for expiry check | Already wired in RootView from Phase 5 [VERIFIED: existing code] |

### Package Legitimacy Audit

This phase installs **zero external packages**. All APIs are first-party Apple frameworks plus the Google REST API called via raw URLSession. No `npm`, `pip`, or `spm` package audit is required.

### Google REST Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `https://accounts.google.com/o/oauth2/v2/auth` | GET (via browser) | Authorization code request [CITED: developers.google.com/identity/protocols/oauth2/native-app] |
| `https://oauth2.googleapis.com/token` | POST | Authorization code exchange + token refresh [CITED: developers.google.com/identity/protocols/oauth2/native-app] |
| `https://gmail.googleapis.com/gmail/v1/users/me/messages` | GET | List message IDs with `q` filter [CITED: developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list] |

---

## Architecture Patterns

### System Architecture Diagram

```
[Settings UI]
     |
     | reads/calls
     v
[GmailSyncController]  <── @Observable @MainActor (mirrors LockController)
     |                       isConnected, syncStatus, lastSyncedAt, connectedEmail
     |                       accessToken (in-memory), accessTokenExpiry (UserDefaults)
     |
     |── via GmailAuthPort protocol
     |        |
     |        ├── authorize() → ASWebAuthenticationSession (browser) → code
     |        |        |
     |        |        └── withCheckedThrowingContinuation wrapper
     |        |
     |        ├── exchangeCode(code, verifier) → URLSession POST /token → TokenResponse
     |        |
     |        └── refreshToken(refreshToken) → URLSession POST /token → TokenResponse
     |
     |── via KeychainPort protocol
     |        |
     |        ├── save(refreshToken)
     |        ├── load() → refreshToken?
     |        └── delete()
     |
     └── via GmailFetchPort protocol (or same GmailAuthPort, planner decides)
              |
              └── listMessages(q:, accessToken:) → [MessageID]
```

**Entry points:** Settings tab "Connect Gmail" button (ING-01); "Sync now" button (ING-03); scenePhase foreground trigger (ING-16)
**Exit points:** `last_synced_at` written to UserDefaults; `refresh_token` written to Keychain; `syncStatus` observable property drives UI

### Recommended Project Structure

```
MyHomeApp/
├── Features/
│   ├── Settings/
│   │   ├── SettingsView.swift           # Phase 5 — add Gmail section here
│   │   └── UnlockView.swift             # Phase 5 — unchanged
│   └── Gmail/                           # Phase 6 NEW folder
│       └── GmailSyncController.swift    # @Observable @MainActor state hub
├── Gmail/                               # Phase 6 NEW folder (ports + implementations)
│   ├── GmailAuthPort.swift              # Protocol seam for OAuth + token exchange
│   ├── SystemGmailAuth.swift            # Production URLSession conformer
│   ├── KeychainPort.swift               # Protocol seam for Keychain CRUD
│   └── SystemKeychainStore.swift        # Production Security.framework conformer
```

> **Planner note:** Mirror the exact naming convention of `BiometricAuthPort.swift` / `SystemBiometricAuth.swift` from Phase 5. Test doubles go in `MyHomeTests/Support/` as `SpyGmailAuth.swift` and `SpyKeychainStore.swift`.

### Pattern 1: PKCE Generation (Pure Swift, Fully Unit-Testable)

```swift
// Source: mickf.net/tech/oauth-pkce-swift-secure-code-verifiers-and-code-challenges
// Verified against RFC 7636: code_verifier = 43-128 unreserved chars; challenge = BASE64URL(SHA256(verifier))

import CryptoKit
import Security

enum PKCEError: Error {
    case failedToGenerateRandomBytes
}

struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() throws -> PKCE {
        // 32 random bytes → 43-char base64url verifier (well within 43-128 range)
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PKCEError.failedToGenerateRandomBytes
        }
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // SHA256 hash of ASCII bytes of the verifier → base64url
        guard let verifierData = verifier.data(using: .ascii) else {
            throw PKCEError.failedToGenerateRandomBytes
        }
        let digest = SHA256.hash(data: verifierData)
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        return PKCE(verifier: verifier, challenge: challenge)
    }
}
```

**Unit-testable:** `PKCE.generate()` is pure logic — call it in a Swift Testing test and assert `verifier.count >= 43`, `verifier.count <= 128`, challenge is non-empty and different from verifier.

### Pattern 2: ASWebAuthenticationSession (Async/Await Wrapper)

The `ASWebAuthenticationSession` API is callback-based. Wrap it with `withCheckedThrowingContinuation` to make it async-compatible. The session **must be created and started on `@MainActor`** because it presents UI.

```swift
// Source: derived from OAuthSwift's ASWebAuthenticationURLHandler pattern +
// withCheckedThrowingContinuation documentation

import AuthenticationServices

// Error mapping for D6-19
enum GmailAuthError: Error {
    case userCancelled               // User tapped Cancel in browser
    case callbackURLInvalid          // Redirect came back malformed
    case noAuthCode                  // URL has no "code" query param
    case networkError(Error)
    case oauthError(String)          // Raw Google error string (D6-19)
}

// PresentationContextProvider — wraps a UIWindowScene for SwiftUI compatibility
final class SceneContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // iOS 17+: find the first connected UIWindowScene's keyWindow
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow ?? UIWindow()
    }
}

// In GmailSyncController (or SystemGmailAuth production conformer):
// Must be called from @MainActor context
@MainActor
func authorize(authURL: URL, callbackScheme: String) async throws -> String {
    let contextProvider = SceneContextProvider()

    return try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    continuation.resume(throwing: GmailAuthError.userCancelled)
                } else {
                    continuation.resume(throwing: GmailAuthError.networkError(error))
                }
                return
            }

            guard let url = callbackURL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                continuation.resume(throwing: GmailAuthError.callbackURLInvalid)
                return
            }

            // Also extract "error" query param for D6-19 raw error display
            if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
                continuation.resume(throwing: GmailAuthError.oauthError(oauthError))
                return
            }

            continuation.resume(returning: code)
        }
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = false  // false = reuses browser cookies
        session.start()

        // Keep session alive for duration of continuation
        // Note: ASWebAuthenticationSession is internally retained until callback fires
    }
}
```

**Key pitfalls:**
- `ASWebAuthenticationSession` must stay alive until the callback fires — the local `session` variable must not go out of scope. Assign to an instance property on the controller or let it be captured by the continuation closure (the system retains it internally when `.start()` is called — safe).
- Only call `continuation.resume(...)` exactly once — use `guard` early-returns to prevent double-resume.
- Cancellation error code: `ASWebAuthenticationSessionError.canceledLogin` [CITED: developer.apple.com/documentation/authenticationservices/aswebauthenticationsessionerror]

### Pattern 3: Google OAuth Authorization URL

```swift
// Source: developers.google.com/identity/protocols/oauth2/native-app [CITED]
// All parameters verified against current Google OAuth 2.0 documentation.

func buildAuthorizationURL(
    clientID: String,
    redirectURI: String,  // e.g. "com.googleusercontent.apps.CLIENT_ID:/oauth2redirect"
    pkce: PKCE,
    state: String
) -> URL? {
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
    components?.queryItems = [
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
        URLQueryItem(name: "code_challenge", value: pkce.challenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "access_type", value: "offline"),  // Required to get refresh_token
        URLQueryItem(name: "state", value: state),            // CSRF protection
        URLQueryItem(name: "prompt", value: "consent"),       // Force consent on reconnect
    ]
    return components?.url
}
```

> **Important:** `access_type=offline` is required to receive a `refresh_token` in the token exchange response. Without it, Google only returns an access token. [CITED: developers.google.com/identity/protocols/oauth2/native-app]

> **Important:** `prompt=consent` should be set when reconnecting (D6-12) to force Google to re-issue a refresh token. Without it, re-authorization may not return a new refresh token if the user already consented.

### Pattern 4: Token Exchange (Authorization Code → Tokens)

```swift
// Source: developers.google.com/identity/protocols/oauth2/native-app [CITED]

struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int          // seconds until access token expires (typically 3599)
    let refresh_token: String?   // only present on first grant or forced consent
    let token_type: String
    let scope: String
}

func exchangeCode(
    code: String,
    codeVerifier: String,
    clientID: String,
    redirectURI: String
) async throws -> TokenResponse {
    let url = URL(string: "https://oauth2.googleapis.com/token")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60  // D6-24
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let bodyParams = [
        "client_id": clientID,
        "code": code,
        "code_verifier": codeVerifier,
        "grant_type": "authorization_code",
        "redirect_uri": redirectURI,
    ]
    request.httpBody = bodyParams
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
        .joined(separator: "&")
        .data(using: .utf8)

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(TokenResponse.self, from: data)
}
```

### Pattern 5: Refresh Token Grant

```swift
// Source: developers.google.com/identity/protocols/oauth2/native-app [CITED]

struct RefreshResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let token_type: String
}

func refreshAccessToken(
    refreshToken: String,
    clientID: String
) async throws -> RefreshResponse {
    let url = URL(string: "https://oauth2.googleapis.com/token")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let bodyParams = [
        "client_id": clientID,
        "refresh_token": refreshToken,
        "grant_type": "refresh_token",
    ]
    request.httpBody = bodyParams
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(RefreshResponse.self, from: data)
}
```

**Refresh token expiry (ING-16):** Google returns `invalid_grant` (HTTP 400) when the refresh token is expired. The controller must catch this specific error and set a `isTokenExpired = true` state to trigger the D6-11/D6-13 reconnect CTA. [CITED: nango.dev/blog/google-oauth-invalid-grant-token-has-been-expired-or-revoked]

### Pattern 6: Keychain Port (Protocol Seam + Production Conformer)

The Keychain cannot be used in plain XCTest/Swift Testing without a test host with proper entitlements. The solution is the same protocol-port pattern as `BiometricAuthPort`: define a protocol, inject it at init, and supply an in-memory `SpyKeychainStore` in tests.

```swift
// KeychainPort.swift — public protocol (mirrors BiometricAuthPort.swift shape)

public protocol KeychainPort: Sendable {
    func save(_ value: String, forKey key: String) throws
    func load(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}

// Keychain-specific errors surfaced to the controller
public enum KeychainError: Error {
    case itemNotFound
    case duplicateItem     // handled internally by upsert
    case unexpectedData
    case unexpectedStatus(OSStatus)
}

// SystemKeychainStore.swift — production conformer (Security.framework)
// kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (SEC-03, D6-05)
public struct SystemKeychainStore: KeychainPort, @unchecked Sendable {
    private let service: String  // e.g. "com.reojacob.myhome.gmail"

    public init(service: String = "com.reojacob.myhome.gmail") {
        self.service = service
    }

    public func save(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        // Try add first; if duplicate, update.
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
            ]
            let attributes: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    public func load(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    public func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

**Test double:**

```swift
// MyHomeTests/Support/SpyKeychainStore.swift
// Mirrors SpyBiometricAuth.swift structure exactly
public final class SpyKeychainStore: KeychainPort, @unchecked Sendable {
    private var store: [String: String] = [:]
    public var shouldThrowOnSave: Error? = nil
    public var shouldThrowOnLoad: Error? = nil

    public func save(_ value: String, forKey key: String) throws {
        if let error = shouldThrowOnSave { throw error }
        store[key] = value
    }
    public func load(forKey key: String) throws -> String? {
        if let error = shouldThrowOnLoad { throw error }
        return store[key]
    }
    public func delete(forKey key: String) throws {
        store.removeValue(forKey: key)
    }
}
```

### Pattern 7: GmailSyncController (@Observable @MainActor)

The controller is the sole state owner — mirrors `LockController` exactly.

```swift
// GmailSyncController.swift

@MainActor
@Observable
final class GmailSyncController {

    // MARK: - Persistent state (App Group UserDefaults)
    var lastSyncedAt: Date? {
        get { defaults.object(forKey: "gmail_last_synced_at") as? Date }
        set { defaults.set(newValue, forKey: "gmail_last_synced_at") }
    }
    var accessTokenExpiry: Date? {
        get { defaults.object(forKey: "gmail_access_token_expiry") as? Date }
        set { defaults.set(newValue, forKey: "gmail_access_token_expiry") }
    }
    var connectedEmail: String? {
        get { defaults.string(forKey: "gmail_connected_email") }
        set { defaults.set(newValue, forKey: "gmail_connected_email") }
    }

    // MARK: - In-memory state (D6-07)
    var accessToken: String? = nil     // Never persisted
    var syncStatus: SyncStatus = .idle
    var authError: GmailAuthError? = nil

    // MARK: - Derived
    var isConnected: Bool { (try? keychain.load(forKey: "refresh_token")) != nil }
    var isTokenExpired: Bool {
        guard let expiry = accessTokenExpiry else { return false }
        return expiry < Date()
    }
    var needsProactiveRefresh: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry.timeIntervalSinceNow < 300  // 5-minute window (D6-06)
    }

    // MARK: - Dependencies (injected — enables testing)
    private let auth: any GmailAuthPort
    private let keychain: any KeychainPort

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    init(auth: any GmailAuthPort = SystemGmailAuth(), keychain: any KeychainPort = SystemKeychainStore()) {
        self.auth = auth
        self.keychain = keychain
    }

    // MARK: - Scene phase hook (called from RootView .onChange — D6-11)
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active && isTokenExpired {
            syncStatus = .tokenExpired  // Triggers reconnect CTA in UI
        }
    }

    // MARK: - Sign in (D6-08: authorize → exchange → immediate sync)
    func signIn() async { /* see flow below */ }

    // MARK: - Sync (D6-09, D6-06)
    func sync() async { /* see flow below */ }

    // MARK: - Sign out (D6-17)
    func signOut() { /* clear keychain + defaults */ }
}

enum SyncStatus: Equatable {
    case idle
    case authorizing
    case syncing
    case done
    case tokenExpired
    case error(String)  // message for display
}
```

### Pattern 8: Gmail API Fetch

```swift
// Source: developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list [CITED]

struct MessageListResponse: Decodable {
    struct MessageRef: Decodable { let id: String; let threadId: String }
    let messages: [MessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

func listMessages(accessToken: String, query: String, maxResults: Int = 100) async throws -> MessageListResponse {
    // q=newer_than:30d for ING-02 initial backfill (D6-10)
    var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "maxResults", value: String(maxResults)),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 60
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(MessageListResponse.self, from: data)
}
// Usage: query = "newer_than:30d"
// Gmail search syntax: newer_than:Nd where N is number of days [CITED: Gmail search operators docs]
```

**Phase 6 returns only message IDs** (not full bodies). Phase 7 will add `messages.get` calls and parser logic.

### Pattern 9: Relative Timestamp Display (D6-16)

```swift
// D6-16 says "DateComponentsFormatter" but the correct formatter for "2 hours ago" output is:
// RelativeDateTimeFormatter — iOS 13+, produces "2 hours ago" / "just now" naturally [CITED: hackingwithswift.com]

extension Date {
    var relativeToNow: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
// Usage: "Last synced \(lastSyncedAt.relativeToNow)"
// → "Last synced 2 hours ago"
```

### Anti-Patterns to Avoid

- **Storing access_token in UserDefaults or @AppStorage:** Short-lived tokens must stay in memory (D6-07). Even if encrypted-at-rest, UserDefaults is accessible to any process in the same App Group.
- **Storing refresh_token in UserDefaults:** Must be in Keychain (SEC-03). UserDefaults is not encrypted.
- **Calling `session.start()` off the main thread:** ASWebAuthenticationSession presents UI and must run on `@MainActor`.
- **Resuming a continuation twice:** `withCheckedThrowingContinuation` will crash on double-resume. Use guard/early-return patterns in the callback closure.
- **Not sending `prompt=consent` on reconnect:** Google may not re-issue a refresh token if the user already consented without `prompt=consent`.
- **Not sending `access_type=offline`:** Without this, the token exchange does not return a refresh token.
- **Reusing a Keychain query dict for both search and data:** The `kSecReturnData` key should NOT be present in SecItemUpdate queries — it causes silent failures on some iOS versions.
- **Using `@StateObject` / `@ObservedObject` for GmailSyncController:** Must use `@Observable` + `@State` (Phase 5 PITFALLS.md rule). Never break this.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SHA256 hashing for PKCE | Custom SHA256 | `CryptoKit.SHA256` | Constant-time implementation, no side-channel risk, first-party |
| Random byte generation | `arc4random`, `drand48` | `SecRandomCopyBytes` | Cryptographically secure; required for PKCE spec compliance (RFC 7636) |
| Base64url encoding | Custom char-replace | `.base64EncodedString()` + 3-line fix | One-liner; more readable than rolling your own base-64 state machine |
| Secure token storage | Write tokens to files or UserDefaults | `Security.SecItem*` Keychain | OS-managed encryption, device-binding, survives app updates |
| Token expiry tracking | Parse JWT `exp` field | Store `expires_in` offset at token receipt | Simpler; no JWT parsing library needed for Google OAuth |
| Relative time display | Manual date arithmetic + string concat | `RelativeDateTimeFormatter` | Handles locale, plurals, and tense automatically |

**Key insight:** Every custom implementation of crypto primitives, secure storage, or token lifecycle management is a potential security regression. The first-party Apple stack provides exactly what this phase needs.

---

## Common Pitfalls

### Pitfall 1: ASWebAuthenticationSession continuations and session lifetime

**What goes wrong:** The `ASWebAuthenticationSession` object is created inside a `withCheckedThrowingContinuation` closure. On some implementations the session variable goes out of scope before the callback fires, causing a silent early deallocation. The completion handler is never called, and the continuation leaks.

**Why it happens:** Swift's ARC releases the session when the local variable leaves scope. The underlying system browser is still running, but the callback target is gone.

**How to avoid:** Assign the session to an instance property on the controller/conformer before calling `.start()`. Alternatively, rely on the internal retain the system applies once `start()` is called — this is documented behavior but worth verifying.

**Warning signs:** The sign-in sheet appears and dismisses after auth, but the completion handler is never called; the app stays on the sign-in screen.

### Pitfall 2: Missing `access_type=offline` in authorization URL

**What goes wrong:** Token exchange succeeds but `TokenResponse.refresh_token` is `nil`. The app receives only an access token. No refresh token is stored in Keychain. On next launch, there is no way to get a new access token without full OAuth.

**Why it happens:** Google's default `access_type` is `online` — no refresh token is issued.

**How to avoid:** Always include `access_type=offline` in the authorization URL (Pattern 3 above). Check for `refresh_token` nil in `TokenResponse` and handle as an error.

### Pitfall 3: Testing-mode 7-day refresh token expiry (ING-16)

**What goes wrong:** During development, the app uses an OAuth client in "Testing" status on Google Cloud Console. Google revokes refresh tokens after 7 days. This is the ING-16 scenario — Reo needs to reconnect every week. In production, refresh tokens can last ~45 days (or longer) with active use.

**Why it happens:** "Testing" publishing status + "External" user type → Google treats all authorizations as temporary. [CITED: google.com/cloud Manage App Audience docs]

**How to avoid:** For development testing: implement ING-16 proactive expiry check early so the reconnect CTA is exercised regularly. For production: change publishing status to "In production" before shipping (the app is for personal use only — verification is minimal). The 7-day expiry is a feature for testing the reconnect flow, not just a bug.

**Warning signs:** `invalid_grant` error from refresh token request within 7 days of sign-in.

### Pitfall 4: Double-resume on `withCheckedThrowingContinuation`

**What goes wrong:** `ASWebAuthenticationSession`'s completion handler fires once. But if the code mistakenly calls `continuation.resume(...)` in multiple code paths (e.g., both the error branch and the main branch), the Swift runtime crashes with "SWIFT TASK CONTINUATION MISUSE".

**How to avoid:** Use `guard` with explicit early `return` after each `continuation.resume(...)` call. Never have two paths that can both reach a resume.

### Pitfall 5: Keychain entitlement in test target

**What goes wrong:** Unit tests that directly call `SecItemAdd` / `SecItemCopyMatching` fail with OSStatus `-34018` (errSecMissingEntitlement) or the test suite crashes silently.

**Why it happens:** The plain test bundle (without a test host) doesn't have the Keychain entitlement. The system rejects all Keychain operations.

**How to avoid:** Never call Keychain directly in unit tests. Use the `SpyKeychainStore` mock instead. The test target already uses `@testable import MyHome` and mirrors the `SpyBiometricAuth` pattern — follow the same pattern for `SpyKeychainStore`. Integration testing of actual Keychain write/read is manual (device or simulator with entitlement). [CITED: build.thebeat.co/how-to-write-a-testable-keychain-wrapper-library]

### Pitfall 6: Swift 6.2 nonisolated async method on `@MainActor` caller

**What goes wrong (Swift 6.2 specific):** In Swift 6.2, `nonisolated async` functions **inherit the caller's actor context** by default (`NonisolatedNonsendingByDefault` feature). If `GmailAuthPort.refreshToken()` is `nonisolated async` and called from a `@MainActor` controller, it runs on the main thread, potentially blocking the UI during network calls.

**How to avoid:** Mark async network methods on port protocols as `@concurrent` if they should run off the main thread. Or call them inside `Task.detached { ... }` from the controller. For Phase 6's use cases (token exchange, Gmail fetch), the calls are user-triggered and short — running on the main actor is acceptable for simplicity. Add `@concurrent` only if UI jank is observed. [CITED: avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2]

### Pitfall 7: Arbitrary custom scheme vs. reverse-client-ID scheme in Cloud Console

**What goes wrong:** Registering `myhome-oauth://callback` in Cloud Console may fail validation for new iOS OAuth clients if Google tightens its scheme policy. The redirect URI from the app and from Cloud Console must match exactly.

**How to avoid:** Strongly prefer using the reverse-client-ID redirect URI (`com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect`) — this is the documented iOS pattern and what Google's own SDK uses. If the user decision to use `myhome-oauth://callback` is retained, test the registration flow in Cloud Console immediately as Wave 0 before writing any auth code.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SFSafariViewController` for OAuth | `ASWebAuthenticationSession` | iOS 12 | System-owned browser; no access to cookies by the app |
| CommonCrypto for SHA256 | `CryptoKit.SHA256` | iOS 13 | First-party, Swift-native, Sendable |
| Custom Keychain wrapper libraries (KeychainAccess, etc.) | Raw `SecItem*` + protocol seam | Ongoing preference | Zero external dependencies; seam provides testability |
| `DateComponentsFormatter` for "X ago" | `RelativeDateTimeFormatter` | iOS 13 | Handles tense, locale, plural rules automatically |
| Combine Future for async auth | `withCheckedThrowingContinuation` | iOS 15 / Swift 5.5 | Structured concurrency; no Combine dependency |
| Google SignIn SDK | Raw `ASWebAuthenticationSession` + PKCE | Project decision | Zero external deps; visibility into state |

**Deprecated/outdated:**

- `SFSafariViewController` for OAuth: Functional but leaks auth cookies back to the app. `ASWebAuthenticationSession` replaced it for auth flows.
- `keychain-swift` / `KeychainAccess` pods: Not needed here; the protocol seam achieves the same testability without a dependency.
- `access_type=online` (no refresh token): Only useful for web-session flows, not mobile apps that need offline access.

---

## Validation Architecture

### Overview

Phase 6 has a clean unit/integration boundary. Everything behind the port protocols is **fully unit-testable**. Everything that touches the real browser, real Keychain, real Google servers, or real network is **manual/TestFlight only**.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) — matches all Phase 3–5 tests |
| Config file | None (auto-discovered from `MyHomeTests` target) |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/GmailSyncControllerTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ING-01 (PKCE math) | `PKCE.generate()` produces verifier 43-128 chars | unit | `xcodebuild ... -only-testing:MyHomeTests/PKCETests` | ❌ Wave 0 |
| ING-01 (PKCE challenge) | `challenge` is SHA256(verifier) base64url-encoded; differs from verifier | unit | `xcodebuild ... -only-testing:MyHomeTests/PKCETests` | ❌ Wave 0 |
| ING-01 (Auth URL) | Authorization URL contains all required query params | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailAuthURLTests` | ❌ Wave 0 |
| ING-01 (real OAuth) | Browser sheet appears; user grants access; callback returns code | **manual** | — TestFlight/device | — |
| ING-02 (sync trigger) | After successful auth, `sync()` is called immediately | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| ING-02 (real sync) | `newer_than:30d` messages list fetched from real Gmail | **manual** | — TestFlight/device | — |
| ING-03 (manual sync) | `syncStatus` transitions idle→syncing→done on spy port | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| ING-05 (last-synced) | `lastSyncedAt` written to UserDefaults after sync | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| ING-16 (token refresh decision) | `needsProactiveRefresh` true when expiry < 5 min away | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| ING-16 (expired → CTA) | `isTokenExpired` true → `syncStatus == .tokenExpired` on foreground | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| ING-16 (real expiry) | App shows reconnect CTA after 7-day Testing token expiry | **manual** | — TestFlight/device | — |
| SEC-03 (Keychain write) | `SystemKeychainStore.save()` on-device with entitlement | **integration/device** | manual only | — |
| SEC-03 (spy round-trip) | `SpyKeychainStore` save/load/delete round-trip | unit | `xcodebuild ... -only-testing:MyHomeTests/KeychainPortTests` | ❌ Wave 0 |
| SEC-03 (refresh token on reconnect) | New refresh token overwrites old in spy keychain | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| SET-04 (sign out) | `signOut()` calls keychain.delete() + clears UserDefaults | unit | `xcodebuild ... -only-testing:MyHomeTests/GmailSyncControllerTests` | ❌ Wave 0 |
| SET-04 (real sign out) | Signing out and reconnecting works end-to-end | **manual** | — TestFlight/device | — |
| SET-05 (last-synced UI) | `RelativeDateTimeFormatter` output matches expected string | unit | `xcodebuild ... -only-testing:MyHomeTests/RelativeTimestampTests` | ❌ Wave 0 |

### What CAN Be Unit-Tested (Behind Port Seams)

1. **PKCE math:** `PKCE.generate()` verifier length, character set, challenge derivation
2. **Authorization URL builder:** All query params present and correctly encoded
3. **Token refresh decision:** `needsProactiveRefresh` logic (5-minute window) with injectable `now` closure
4. **Token expiry check:** `isTokenExpired` derived property with controlled `accessTokenExpiry` UserDefaults
5. **SyncStatus state machine:** idle→authorizing→syncing→done / error / tokenExpired transitions via `SpyGmailAuth`
6. **Sign-out:** `signOut()` calls `keychain.delete()`, clears `connectedEmail`, clears `lastSyncedAt`
7. **Reconnect overwrites token:** New refresh token replaces old in `SpyKeychainStore`
8. **Keychain spy CRUD:** `SpyKeychainStore.save/load/delete` round-trip
9. **Error mapping:** `invalid_grant` HTTP response → `syncStatus = .tokenExpired`
10. **Relative timestamp:** `RelativeDateTimeFormatter` output for known dates

### What Requires Manual / TestFlight Validation

1. **Real OAuth browser flow:** `ASWebAuthenticationSession` sheet presentation, user consent, callback
2. **Google Cloud Console configuration:** Client ID setup, redirect URI registration, test user list
3. **Real token exchange:** Code → access/refresh tokens from Google's `/token` endpoint
4. **Real Gmail API fetch:** `messages.list` with `newer_than:30d` returning actual messages
5. **Real Keychain write/read on device:** Entitlement-gated; cannot run in plain test bundle
6. **7-day refresh token expiry (ING-16 live path):** Requires waiting or simulating on-device
7. **Settings UI integration:** Gmail section visible in correct position; Sync now button state
8. **Sign-out/reconnect end-to-end:** Full flow including UI state resets

### Manual UAT Checklist Template (for VALIDATION.md)

```
UAT-6-01 [ING-01]: Tap "Connect Gmail" → ASWebAuthenticationSession browser sheet appears.
UAT-6-02 [ING-01]: Complete Google sign-in → redirect returns to app, loading indicator shown.
UAT-6-03 [ING-02]: After OAuth success → sync completes with newer_than:30d; last-synced timestamp updates.
UAT-6-04 [ING-03]: Tap "Sync now" → syncStatus shows syncing, then done; timestamp updates.
UAT-6-05 [ING-05]: Last-synced timestamp visible in Settings at all times (even "Never").
UAT-6-06 [ING-16]: After 7-day Testing expiry, open Settings → "Gmail connection expired" CTA visible.
UAT-6-07 [SEC-03]: Verify Keychain item exists post-sign-in via Xcode Instruments or simple device test.
UAT-6-08 [SET-04]: Tap "Sign out" → confirmation message; "Connect Gmail" button reappears; no token visible.
UAT-6-09 [SET-04]: Reconnect → OAuth re-runs; new token overwrites; sync completes.
UAT-6-10 [D6-19]: Cancel OAuth mid-flow → "Try again" button shown, no crash, no stuck state.
```

### Wave 0 Gaps (Files to Create Before Implementation)

- [ ] `MyHomeTests/PKCETests.swift` — covers ING-01 PKCE math
- [ ] `MyHomeTests/GmailAuthURLTests.swift` — covers ING-01 URL builder
- [ ] `MyHomeTests/GmailSyncControllerTests.swift` — covers ING-02, ING-03, ING-05, ING-16, SET-04, SET-05
- [ ] `MyHomeTests/KeychainPortTests.swift` — covers SEC-03 spy round-trip
- [ ] `MyHomeTests/RelativeTimestampTests.swift` — covers SET-05 display format
- [ ] `MyHomeTests/Support/SpyGmailAuth.swift` — test double for `GmailAuthPort`
- [ ] `MyHomeTests/Support/SpyKeychainStore.swift` — test double for `KeychainPort`

---

## Google Cloud Console Setup (Wave 0 prerequisite)

Before any code can be tested end-to-end, Reo must complete these steps in the Google Cloud Console:

1. **Create a project** (or use an existing one) at [console.cloud.google.com](https://console.cloud.google.com)
2. **Enable the Gmail API** under "APIs & Services > Library"
3. **Configure OAuth consent screen:**
   - App type: External
   - Publishing status: Testing (7-day refresh token — ING-16 intentional)
   - Add Reo's Gmail as test user
   - Scope: `https://www.googleapis.com/auth/gmail.readonly`
4. **Create an OAuth client:**
   - Application type: **iOS**
   - Bundle ID: `com.reojacob.myhome` (from `ModelContainer+App.swift` App Group ID)
   - This generates the `client_id` and **reverse-client-ID URL scheme**
5. **Register redirect URI:** Use the reverse-client-ID format shown by Cloud Console (`com.googleusercontent.apps.<YOUR_CLIENT_ID>:/oauth2redirect`) OR `myhome-oauth://callback` if D6-04 is retained
6. **Register URL scheme in Xcode:**
   - MyHome target → Info → URL Types → add scheme matching the redirect URI prefix
   - For reverse-client-ID: add `com.googleusercontent.apps.<YOUR_CLIENT_ID>`
   - For custom scheme: add `myhome-oauth`
7. **Store client_id** in a config file or plist (not hardcoded in source) — can be committed since it is not a secret for iOS native apps [CITED: developers.google.com/identity/protocols/oauth2/native-app]

> **Note:** For an iOS OAuth client, there is **no `client_secret`** — the token endpoint does not require it. The PKCE code_verifier replaces the secret for native apps. [CITED: developers.google.com/identity/protocols/oauth2/native-app]

---

## Security Domain

### Applicable ASVS Categories (ASVS Level 1, `security_enforcement: true`)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | ASWebAuthenticationSession — system-owned browser, no credential handling in app code |
| V3 Session Management | Yes | Refresh token in Keychain; access token in memory only; proactive 5-min expiry window |
| V4 Access Control | Partial | `gmail.readonly` scope limits API surface; no write operations |
| V5 Input Validation | Yes | Parse Google token response via `Codable`; validate callback URL scheme before processing |
| V6 Cryptography | Yes | `CryptoKit.SHA256` + `SecRandomCopyBytes` for PKCE; Keychain for storage |
| V7 Error Handling | Yes | Error mapping per D6-18/19/20/21; raw error display for D6-19 (debug-mode intent) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Authorization code interception | Spoofing, Elevation | PKCE code_verifier — code stolen without verifier is useless |
| Refresh token theft from disk | Information Disclosure | Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — not in UserDefaults or files |
| Access token theft from memory | Information Disclosure | Short-lived (1h); never persisted; only in process memory |
| Custom URI scheme hijacking | Spoofing | Prefer reverse-client-ID scheme (system-registered, harder to spoof); ASWebAuthenticationSession validates scheme |
| CSRF via forged redirect | Tampering | `state` parameter in authorization URL validated on callback |
| Open redirect / phishing via callback URL | Spoofing | `ASWebAuthenticationSession` validates that the returned URL matches the registered scheme before firing callback |
| Overly broad API scope | Elevation of Privilege | `gmail.readonly` only — no compose, no delete, no settings access |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build | ✓ | 26.5 (per memory) | — |
| iOS 17+ Simulator (iPhone 17) | Unit tests | ✓ | iOS 17+ (per memory) | — |
| CryptoKit | PKCE | ✓ | iOS 13+ | — |
| AuthenticationServices | OAuth flow | ✓ | iOS 12+ | — |
| Security.framework | Keychain | ✓ | iOS 2+ | — |
| Google Cloud Console account | OAuth client setup | ? | — | Manual prerequisite — must create before coding |
| Gmail test account with emails | ING-02 smoke test | ? | — | Manual prerequisite — any Gmail account works |
| Device with Face ID (or simulator passcode) | Phase 5 LockController (already shipped) | ✓ | — | — |

**Missing dependencies with no fallback:**

- Google Cloud Console setup (client_id, redirect URI registration) — must be done manually before Wave 0 testing; blocks all real OAuth paths

**Missing dependencies with fallback:**

- Real device for Keychain entitlement tests — simulator with test host works for most paths; SpyKeychainStore covers unit tests

---

## Open Questions

1. **Redirect URI scheme decision (D6-04 vs. reverse-client-ID)**
   - What we know: Google recommends reverse-client-ID; arbitrary custom schemes are deprecated for non-iOS platforms; iOS currently works with both
   - What's unclear: Whether Cloud Console will accept `myhome-oauth://callback` for an iOS client type, or enforce reverse-client-ID only
   - Recommendation: Reo should attempt to register `myhome-oauth://callback` in Cloud Console immediately. If Cloud Console rejects it, switch to reverse-client-ID. Document the actual client_id and final redirect URI in a Wave 0 config file.

2. **GmailAuthPort: single protocol or split into AuthPort + FetchPort?**
   - What we know: Authorization (browser flow) and fetching (URLSession GET) are separate operations with different spy behaviors
   - What's unclear: Whether combining them into one port makes the spy simpler or more complex
   - Recommendation: Split into `GmailAuthPort` (authorize, exchangeCode, refreshToken) and `GmailFetchPort` (listMessages) for focused spies and cleaner TDD seams. Planner decides.

3. **`access_type=offline` + `prompt=consent` on reconnect edge case**
   - What we know: Google may not re-issue a refresh token on re-authorization without `prompt=consent` if the user already consented
   - What's unclear: Whether this actually blocks reconnect flow in Testing mode
   - Recommendation: Always send `prompt=consent` in D6-12 reconnect flow and document why.

4. **Connected email display (D6-14)**
   - What we know: The token exchange response does not include the user's email; the `/token` endpoint returns only tokens
   - What's unclear: How to get `user@gmail.com` to show in Settings
   - Recommendation: After token exchange, make a GET request to `https://www.googleapis.com/oauth2/v3/userinfo?access_token=...` or to Gmail's profile endpoint (`https://gmail.googleapis.com/gmail/v1/users/me/profile`) to fetch the email address. Store it in UserDefaults as `gmail_connected_email`. This is a small additional call but necessary for D6-14's "Connected as: user@gmail.com" display. [ASSUMED: userinfo endpoint still available]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Arbitrary custom scheme `myhome-oauth://callback` is accepted by Google Cloud Console for iOS client type | Redirect URI Warning, Open Questions | OAuth flow fails at registration; must switch to reverse-client-ID scheme |
| A2 | `newer_than:30d` is valid Gmail search query syntax | Pattern 8, ING-02 | First sync returns wrong results; test with actual Gmail account in UAT |
| A3 | Google's `userinfo` endpoint returns the authenticated user's email after token exchange | Open Questions #4 | Cannot display "Connected as" in Settings; need alternative approach |
| A4 | `ASWebAuthenticationSession` session object is internally retained by the OS after `.start()` — won't be deallocated prematurely | Pattern 2 | Completion handler never fires; sign-in appears to hang |
| A5 | `prompt=consent` causes Google to re-issue a refresh token on reconnect | Pattern 3, Open Questions #3 | Reconnect flow receives no refresh_token; user is stuck |
| A6 | CryptoKit `SHA256` is available and Sendable-compatible in Swift 6.2 / iOS 17 | Standard Stack | Compilation error; fallback to CommonCrypto |

---

## Sources

### Primary (HIGH confidence)

- [developers.google.com/identity/protocols/oauth2/native-app](https://developers.google.com/identity/protocols/oauth2/native-app) — Authorization endpoint, token endpoint, PKCE params, redirect URI format, iOS client setup
- [developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list) — Gmail API messages.list: endpoint, q param, response structure
- Apple `AuthenticationServices.ASWebAuthenticationSession` documentation — ASWebAuthenticationSessionError.canceledLogin, presentationContextProvider
- Apple `Security` framework Keychain documentation — SecItemAdd/Update/Delete/CopyMatching, kSecAttrAccessible constants
- Existing codebase: `LockController.swift`, `BiometricAuthPort.swift`, `NotificationCenterPort.swift` — reusable port/seam patterns [VERIFIED: codebase]

### Secondary (MEDIUM confidence)

- [mickf.net/tech/oauth-pkce-swift-secure-code-verifiers-and-code-challenges](https://www.mickf.net/tech/oauth-pkce-swift-secure-code-verifiers-and-code-challenges/) — Swift PKCE implementation with CryptoKit + base64url encoding
- [avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/) — Swift 6.2 nonisolated async + @concurrent behavior
- [hackingwithswift.com — RelativeDateTimeFormatter](https://www.hackingwithswift.com/example-code/system/how-to-show-a-relative-date-and-time-using-relativedatetimeformatter) — "2 hours ago" display pattern
- [build.thebeat.co/how-to-write-a-testable-keychain-wrapper-library](https://build.thebeat.co/how-to-write-a-testable-keychain-wrapper-library-47ffbe3880ed) — Testable Keychain wrapper architecture (referenced for pattern; page was unreachable at research time)
- [nango.dev/blog/google-oauth-invalid-grant-token-has-been-expired-or-revoked](https://nango.dev/blog/google-oauth-invalid-grant-token-has-been-expired-or-revoked/) — `invalid_grant` error semantics for token expiry
- [github.com/openid/AppAuth-iOS/blob/master/Examples/README-Google.md](https://github.com/openid/AppAuth-iOS/blob/master/Examples/README-Google.md) — reverse-client-ID URL scheme format for iOS

### Tertiary (LOW confidence — flagged for validation)

- WebSearch snippets on Google's custom URI scheme deprecation policy — conflicts in sources; iOS impact unclear; marked [ASSUMED] where applied
- Google Groups threads on refresh token 7-day expiry — corroborates CONTEXT.md D6-11 mention

---

## Metadata

**Confidence breakdown:**

- Standard Stack: HIGH — all first-party Apple frameworks, zero new packages
- Architecture patterns: HIGH — direct mirror of existing Phase 5 LockController/BiometricAuthPort pattern
- PKCE implementation: HIGH — RFC 7636 compliant, verified against Swift CryptoKit examples
- Google OAuth endpoints/parameters: HIGH — cited from current Google developer docs
- Redirect URI custom scheme question: MEDIUM — conflicting signals; marked as open question
- Gmail API query syntax (`newer_than:30d`): MEDIUM — not in the reference page fetched; known Gmail search operator but not formally verified this session
- Keychain testing approach: HIGH — mirrors well-established BiometricAuthPort/SpyBiometricAuth pattern already in the codebase
- Swift 6.2 concurrency: MEDIUM — `NonisolatedNonsendingByDefault` behavior verified; specific URLSession changes not confirmed

**Research date:** 2026-06-02
**Valid until:** 2026-07-02 (stable APIs; Google OAuth endpoint URLs are stable; check for Swift 6.2 concurrency docs updates if planning is delayed)
