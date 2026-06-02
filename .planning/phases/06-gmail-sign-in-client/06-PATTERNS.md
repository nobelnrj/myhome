# Phase 6: Gmail Sign-In & Client — Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 9 new files + 2 modified files
**Analogs found:** 9 / 11 (2 files have no direct codebase analog — use RESEARCH.md patterns)

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `MyHomeApp/Gmail/GmailAuthPort.swift` | port-protocol | request-response | `MyHomeApp/Security/BiometricAuthPort.swift` | exact |
| `MyHomeApp/Gmail/SystemGmailAuth.swift` | port-conformer | request-response | `MyHomeApp/Security/BiometricAuthPort.swift` (SystemBiometricAuth) | exact |
| `MyHomeApp/Gmail/KeychainPort.swift` | port-protocol | request-response | `MyHomeApp/Support/NotificationCenterPort.swift` | exact |
| `MyHomeApp/Gmail/SystemKeychainStore.swift` | port-conformer | request-response | `MyHomeApp/Security/BiometricAuthPort.swift` (SystemBiometricAuth) | role-match |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | controller / state hub | event-driven + request-response | `MyHomeApp/Security/LockController.swift` | exact |
| `MyHomeApp/Features/Settings/SettingsView.swift` | view (modified) | request-response | `MyHomeApp/Features/Settings/SettingsView.swift` | self (modify-in-place) |
| `MyHomeApp/RootView.swift` | view (modified) | event-driven | `MyHomeApp/RootView.swift` | self (modify-in-place) |
| `MyHomeTests/Support/SpyGmailAuth.swift` | test double | request-response | `MyHomeTests/Support/SpyBiometricAuth.swift` | exact |
| `MyHomeTests/Support/SpyKeychainStore.swift` | test double | request-response | `MyHomeTests/Support/SpyCenter.swift` | exact |
| `MyHomeTests/GmailSyncControllerTests.swift` | test | event-driven | `MyHomeTests/LockStateTests.swift` | exact |
| `MyHomeTests/PKCETests.swift` + `GmailAuthURLTests.swift` + `KeychainPortTests.swift` + `RelativeTimestampTests.swift` | test | batch | `MyHomeTests/LockSettingsTests.swift` | role-match |

---

## Pattern Assignments

### `MyHomeApp/Gmail/GmailAuthPort.swift` (port-protocol, request-response)

**Analog:** `MyHomeApp/Security/BiometricAuthPort.swift`

**Imports + public protocol declaration** (lines 1–20):
```swift
import Foundation
import LocalAuthentication

public protocol BiometricAuthPort: Sendable {
    func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?)
    func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?)
}
```

**Pattern to copy:** Replace the LA-specific signatures with async OAuth signatures. Keep `public`, `Sendable`, same file-level MARK block structure. Follow this exact naming convention:

```swift
// GmailAuthPort.swift — mirrors BiometricAuthPort.swift shape exactly
import Foundation
import AuthenticationServices

public protocol GmailAuthPort: Sendable {
    func authorize(authURL: URL, callbackScheme: String) async throws -> String
    func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse
    func refreshToken(_ refreshToken: String, clientID: String) async throws -> RefreshResponse
}
```

**Key rules from analog:**
- Protocol must be `public` (test double in `MyHomeTests` uses `@testable import MyHome` — the protocol must be visible)
- Protocol must be `Sendable` (Swift 6.2 strict concurrency — every port in this project is `Sendable`)
- All async throwing methods, no non-async variants

---

### `MyHomeApp/Gmail/SystemGmailAuth.swift` (port-conformer, request-response)

**Analog:** `MyHomeApp/Security/BiometricAuthPort.swift` — `SystemBiometricAuth` struct (lines 31–51)

**Production conformer shape** (lines 31–51):
```swift
public struct SystemBiometricAuth: BiometricAuthPort, Sendable {

    public init() {}

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        let context = LAContext()   // fresh per call — avoids Pitfall 2
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            return (ok, nil)
        } catch {
            return (false, error)
        }
    }

    public func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?) {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(policy, error: &error)
        return (ok, error)
    }
}
```

**Pattern to copy:**
- `public struct` (value type, not class) + `Sendable`
- `public init() {}`
- Each method creates its resources fresh (LAContext analogy → fresh URLRequest per call)
- `@MainActor` on `authorize()` only (ASWebAuthenticationSession must present UI on main thread — see RESEARCH.md Pattern 2)
- `@unchecked Sendable` if the type holds URLSession references (see RESEARCH.md Pattern 6 `SystemKeychainStore` for precedent)

---

### `MyHomeApp/Gmail/KeychainPort.swift` (port-protocol, request-response)

**Analog:** `MyHomeApp/Support/NotificationCenterPort.swift` (lines 1–54)

**Protocol declaration shape** (lines 13–22):
```swift
public protocol NotificationCenterPort: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}
```

**Pattern to copy:** Same `public protocol … : Sendable` declaration. Mix synchronous and throwing methods — `save` and `delete` are synchronous-throwing (no async needed for Keychain); `load` is synchronous-throwing. See RESEARCH.md Pattern 6 for the exact method signatures.

**Also copy:** The MARK comment pattern and the "Production conformer" class header from `SystemNotificationCenter` (lines 30–35):
```swift
public final class SystemNotificationCenter: NotificationCenterPort, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }
```

For `SystemKeychainStore`, the `private let service: String` property plays the role of `private let center`.

---

### `MyHomeApp/Gmail/SystemKeychainStore.swift` (port-conformer, request-response)

**Analog:** `MyHomeApp/Security/BiometricAuthPort.swift` (`SystemBiometricAuth`) + `MyHomeApp/Support/NotificationCenterPort.swift` (`SystemNotificationCenter`)

The full implementation is in RESEARCH.md Pattern 6 (lines 471–536). The structural patterns to copy from the codebase:

1. **`@unchecked Sendable`** — used on `SystemNotificationCenter` (line 30) because it holds a reference type (`UNUserNotificationCenter`). `SystemKeychainStore` uses a `String` service identifier, so it can be `Sendable` without `@unchecked`, but follow the project pattern.

2. **`private let` dependency** — same as `private let center` in `SystemNotificationCenter`. Use `private let service: String`.

3. **`public init(... = default)`** — both `SystemBiometricAuth` and `SystemNotificationCenter` provide a public no-arg default init. Follow the same pattern: `public init(service: String = "com.reojacob.myhome.gmail")`.

---

### `MyHomeApp/Features/Gmail/GmailSyncController.swift` (controller / state hub, event-driven + request-response)

**Analog:** `MyHomeApp/Security/LockController.swift` (lines 1–197) — **exact match**

**Class declaration + imports** (lines 1–34):
```swift
import Foundation
import SwiftUI
import LocalAuthentication

@MainActor
@Observable
final class LockController {
```

Copy `@MainActor @Observable final class` verbatim. Replace `import LocalAuthentication` with `import AuthenticationServices`.

**Persistent state via App Group UserDefaults** (lines 40–43):
```swift
var lockEnabled: Bool {
    get { defaults.bool(forKey: "lockEnabled") }
    set { defaults.set(newValue, forKey: "lockEnabled") }
}
```

Apply this computed-property pattern for `lastSyncedAt`, `accessTokenExpiry`, and `connectedEmail` (each backed by the App Group suite, different key strings).

**Runtime (in-memory) state** (lines 49–55):
```swift
var isLocked: Bool = false
var isBlurred: Bool = false
var authError: LockAuthError? = nil
```

Mirror for: `var accessToken: String? = nil`, `var syncStatus: SyncStatus = .idle`, `var authError: GmailAuthError? = nil`.

**Injected dependencies** (lines 63–68):
```swift
private let auth: any BiometricAuthPort
private let now: () -> Date

private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
}
```

Copy the `private var defaults` pattern exactly (same suite name `"group.com.reojacob.myhome"`). Replace `auth` with `auth: any GmailAuthPort` and `keychain: any KeychainPort`. The `now` injectable closure can be reused for the 5-minute proactive refresh window check (D6-06).

**Init with injected defaults** (lines 77–82):
```swift
init(auth: any BiometricAuthPort = SystemBiometricAuth(), now: @escaping () -> Date = Date.init) {
    self.auth = auth
    self.now = now
    if lockEnabled { isLocked = true }
}
```

Copy the `= SystemXxx()` default argument pattern:
```swift
init(auth: any GmailAuthPort = SystemGmailAuth(), keychain: any KeychainPort = SystemKeychainStore(), now: @escaping () -> Date = Date.init) {
```

**Scene phase hook** (lines 87–108):
```swift
func scenePhaseChanged(_ phase: ScenePhase) {
    switch phase {
    case .active:
        isBlurred = false
        if lockEnabled, let bg = backgroundedAt {
            // ...
        }
    case .inactive, .background:
        isBlurred = true
        // ...
    @unknown default:
        break
    }
}
```

Copy the `func scenePhaseChanged(_ phase: ScenePhase)` signature and `@unknown default: break` pattern. The Phase 6 version checks `isTokenExpired` on `.active` (D6-11) instead of the grace period.

**Error mapping pattern** (lines 178–196):
```swift
private func mapError(_ error: Error?) -> LockAuthError? {
    guard let laErr = error as? LAError else { return .unknown }
    switch laErr.code {
    case .userCancel, .appCancel, .systemCancel:
        return nil
    case .authenticationFailed:
        return .failed
    // ...
    }
}
```

Copy the `private func mapError` pattern for mapping `GmailAuthError`/HTTP status codes to `SyncStatus.error(String)`.

---

### `MyHomeApp/Features/Settings/SettingsView.swift` (view, modified in place)

**Analog:** Self — add Gmail section following the established Section pattern.

**Existing Section pattern** (lines 28–41):
```swift
Section("Security") {
    Toggle("Face ID Lock", isOn: Binding(
        get: { lockController.lockEnabled },
        set: { newValue in
            Task {
                if newValue {
                    await lockController.enableLock()
                } else {
                    await lockController.disableLock()
                }
            }
        }
    ))
}
```

**Pattern to copy for async button actions** — use `Task { await controller.method() }` inside button/toggle closures. Never call async directly from a sync closure.

**Existing Button pattern** (lines 47–60):
```swift
Button("Manage Categories") {
    showManageCategories = true
}

Button {
    selectedTab = 2
} label: {
    HStack {
        Text("Budgets")
        Spacer()
        Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
    }
}
.foregroundStyle(.primary)
```

**Prop injection pattern** (lines 15–19):
```swift
struct SettingsView: View {
    @Binding var selectedTab: Int
    let lockController: LockController
```

Add `let gmailSyncController: GmailSyncController` as a `let` (non-binding Observable) — same as `let lockController: LockController`. No `@ObservedObject`, no `@StateObject` (RESEARCH.md Anti-Patterns).

---

### `MyHomeApp/RootView.swift` (view, modified in place)

**Analog:** Self — add `@State private var gmailSyncController = GmailSyncController()` and wire `.onChange(of: scenePhase)`.

**Existing @State controller ownership** (line 33):
```swift
@State private var lockController = LockController()
```

Add immediately after: `@State private var gmailSyncController = GmailSyncController()`

**Existing scenePhase wiring** (lines 87–94):
```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```

Extend the same `.onChange` closure — add `gmailSyncController.scenePhaseChanged(newPhase)` on the line after `lockController.scenePhaseChanged(newPhase)`. Do NOT add a second `.onChange(of: scenePhase)` modifier — a single `.onChange` handles both controllers.

**SettingsView call site** (line 61):
```swift
SettingsView(selectedTab: $selectedTab, lockController: lockController)
```

Update to pass `gmailSyncController: gmailSyncController` as a second argument.

---

### `MyHomeTests/Support/SpyGmailAuth.swift` (test double, request-response)

**Analog:** `MyHomeTests/Support/SpyBiometricAuth.swift` (lines 1–55) — **exact structural match**

**File header + imports** (lines 1–13):
```swift
import Testing
import LocalAuthentication
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyBiometricAuth — in-memory BiometricAuthPort test double.
// ...
// ---------------------------------------------------------------------------
```

Replace `import LocalAuthentication` with `import AuthenticationServices`. Replace the description comment for `GmailAuthPort`.

**Spy class body** (lines 16–55):
```swift
public final class SpyBiometricAuth: BiometricAuthPort, @unchecked Sendable {

    // MARK: - Settable stubs
    public var evaluateResult: (Bool, Error?) = (true, nil)
    public var canEvaluateResult: (Bool, Error?) = (true, nil)

    // MARK: - Recorded calls
    public private(set) var evaluateCalls: [LAPolicy] = []
    public private(set) var canEvaluateCalls: [LAPolicy] = []

    public init() {}

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        evaluateCalls.append(policy)
        return evaluateResult
    }
    // ...

    public func reset() {
        evaluateCalls = []
        canEvaluateCalls = []
    }
}
```

**Copy these structural conventions:**
- `public final class Spy… : Port, @unchecked Sendable`
- Settable stubs as `public var` properties (one per method, named `<method>Result`)
- Recorded calls as `public private(set) var <method>Calls: [ArgType]`
- `public init() {}`
- `public func reset()` that clears all recorded state
- Throw stubs as `public var shouldThrowOn<Method>: Error? = nil` (pattern used in RESEARCH.md SpyKeychainStore, lines 545–546)

---

### `MyHomeTests/Support/SpyKeychainStore.swift` (test double, request-response)

**Analog:** `MyHomeTests/Support/SpyCenter.swift` (lines 1–71)

**Spy class body pattern** (lines 16–70):
```swift
public final class SpyCenter: NotificationCenterPort, @unchecked Sendable {

    // MARK: - Settable stubs
    public var authorizationResult: Bool = true

    // MARK: - Recorded calls
    public private(set) var addedRequests: [UNNotificationRequest] = []
    public private(set) var removedIdentifierSets: [[String]] = []

    public init() {}

    // MARK: - Computed inspection helpers
    public var addedIdentifiers: [String] { addedRequests.map(\.identifier) }
    // ...

    // MARK: - Reset
    public func reset() {
        addedRequests = []
        removedIdentifierSets = []
    }
}
```

**For SpyKeychainStore:** Add an in-memory `private var store: [String: String] = [:]` (since Keychain is a key-value store) plus `shouldThrowOnSave` / `shouldThrowOnLoad` error stubs (see RESEARCH.md Pattern 6, lines 545–560). The `reset()` method clears both `store` and the error stubs.

---

### `MyHomeTests/GmailSyncControllerTests.swift` (test, event-driven)

**Analog:** `MyHomeTests/LockStateTests.swift` (lines 1–254) — **exact structural match**

**Test file header + @MainActor** (lines 1–22):
```swift
import Testing
import LocalAuthentication
import Foundation
@testable import MyHome

// Requirements: SEC-01 ..., D5-01 ..., D5-05 ...
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/LockStateTests

@MainActor
struct LockStateTests {
```

Copy this header pattern verbatim:
- `import Testing` (not `import XCTest` — this project uses Swift Testing)
- `@testable import MyHome`
- `// Requirements: <req IDs>` comment
- `// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/GmailSyncControllerTests`
- `@MainActor` on the struct (GmailSyncController is `@MainActor`)

**Test isolation pattern** (lines 27–32):
```swift
let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
suite.set(false, forKey: "lockEnabled")
```

For Gmail tests, reset `gmail_last_synced_at`, `gmail_access_token_expiry`, `gmail_connected_email` in the same App Group suite at the top of each test that mutates UserDefaults. Use `defer { suite.removeObject(forKey: "gmail_...") }` to clean up.

**Inject spy + assert pattern** (lines 61–71):
```swift
@Test("successUnlocks: successful auth clears isLocked and authError — SEC-02")
func successUnlocks() async {
    let spy = SpyBiometricAuth()
    spy.canEvaluateResult = (true, nil)
    spy.evaluateResult = (true, nil)
    let controller = LockController(auth: spy)
    controller.isLocked = true

    await controller.authenticate()

    #expect(controller.isLocked == false, ...)
    #expect(controller.authError == nil, ...)
}
```

Copy this 3-part structure: **Arrange** (spy + controller), **Act** (`await controller.method()`), **Assert** (`#expect(...)` with human-readable message string). Use Swift Testing `#expect` — never `XCTAssert`.

---

### `MyHomeTests/PKCETests.swift` / `GmailAuthURLTests.swift` / `KeychainPortTests.swift` / `RelativeTimestampTests.swift` (tests)

**Analog:** `MyHomeTests/LockSettingsTests.swift` (lines 1–96)

**Non-async test pattern** (lines 30–43):
```swift
@Test("enableLockSetsFlagOnAuthSuccess: enableLock() sets lockEnabled=true when auth succeeds — SET-01")
func enableLockSetsFlagOnAuthSuccess() async {
    resetLockEnabled()
    defer { resetLockEnabled() }

    let spy = SpyBiometricAuth()
    spy.evaluateResult = (true, nil)
    let controller = LockController(auth: spy)

    await controller.enableLock()

    #expect(controller.lockEnabled == true, "enableLock() must set lockEnabled=true on auth success")
}
```

**Test naming convention:** `"<methodName>: <expected behavior> — <req ID>"` (string description before the function). Always include the requirement ID (e.g., `ING-01`, `SEC-03`) in the description string.

**UAT log comment pattern** (lines 98–123 of `LockSettingsTests.swift`):
```swift
// MARK: - UAT Verification Log (human_verify_mode = end-of-phase)
//
// UAT-1 [SEC-01, D5-07a]: ...
```

Append a `// MARK: - UAT Verification Log` block at the end of `GmailSyncControllerTests.swift` listing the 10 UAT items from RESEARCH.md.

---

## Shared Patterns

### @Observable + @State ownership (no @StateObject / @ObservedObject)

**Source:** `MyHomeApp/RootView.swift` line 33 + RESEARCH.md Anti-Patterns section
**Apply to:** `RootView.swift` (GmailSyncController ownership), `SettingsView.swift` (controller passed as `let`)

```swift
// RootView.swift — ownership
@State private var gmailSyncController = GmailSyncController()

// SettingsView.swift — passed as non-binding let
struct SettingsView: View {
    let gmailSyncController: GmailSyncController
    // ...
}
```

Never use `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`. `@Observable` + `@State` is the only pattern in this codebase (Pitfall 10 referenced in `RootView.swift` line 33 comment).

### App Group UserDefaults suite

**Source:** `MyHomeApp/Security/LockController.swift` lines 67–69
**Apply to:** `GmailSyncController.swift`

```swift
private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
}
```

Suite name is `"group.com.reojacob.myhome"` — same as all prior phases. Do not use `.standard` as primary; use it only as a fallback.

### Port protocol shape (public + Sendable)

**Source:** `MyHomeApp/Security/BiometricAuthPort.swift` lines 13–19 + `MyHomeApp/Support/NotificationCenterPort.swift` lines 13–22
**Apply to:** `GmailAuthPort.swift`, `KeychainPort.swift`

```swift
public protocol XxxPort: Sendable {
    // All methods are declared; async methods marked async; throwing methods marked throws
}
```

### scenePhase wiring (single .onChange, multiple controllers)

**Source:** `MyHomeApp/RootView.swift` lines 87–94
**Apply to:** `RootView.swift` when adding `gmailSyncController.scenePhaseChanged(newPhase)`

```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)   // Phase 6 addition
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```

One `.onChange` modifier handles all scene-phase-dependent controllers — do not add a second `.onChange(of: scenePhase)`.

### Task { await } in sync SwiftUI closures

**Source:** `MyHomeApp/Features/Settings/SettingsView.swift` lines 32–38
**Apply to:** `SettingsView.swift` — "Sync now" button, "Sign out" link, "Connect Gmail" button

```swift
Button("Sync now") {
    Task { await gmailSyncController.sync() }
}
```

Never call async directly from a Button action or Toggle `set` closure. Always wrap in `Task { }`.

### Swift Testing test structure

**Source:** `MyHomeTests/LockStateTests.swift` lines 1–22
**Apply to:** All new test files

```swift
import Testing
import Foundation
@testable import MyHome

@MainActor
struct GmailSyncControllerTests {
    // ...
}
```

All test structs are `@MainActor` when the subject is `@MainActor`. Use `#expect(...)` not `XCTAssert`. Use `async` test functions when calling `await controller.method()`.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `MyHomeApp/Gmail/PKCE.swift` (utility struct) | utility | transform (pure) | No cryptographic utility exists in the codebase. Use RESEARCH.md Pattern 1 directly — the full CryptoKit + SecRandomCopyBytes implementation is ready to copy. |
| Config / plist for `client_id` | config | N/A | No OAuth config file exists. RESEARCH.md Cloud Console setup section and the note "can be committed since it is not a secret for iOS native apps" provides the guidance. Planner decides whether to use a `.plist`, `Secrets.swift`, or environment-injected constant. |

---

## Analog Search Scope

**Directories searched:** `MyHomeApp/Security/`, `MyHomeApp/Support/`, `MyHomeApp/Features/Settings/`, `MyHomeApp/`, `MyHomeTests/Support/`, `MyHomeTests/`
**Swift files scanned:** 67
**Pattern extraction date:** 2026-06-02

## Key Structural Notes for Planner

1. **Folder layout:** RESEARCH.md specifies `MyHomeApp/Features/Gmail/GmailSyncController.swift` (controller in Features) and `MyHomeApp/Gmail/` (ports + production conformers in a separate top-level Gmail folder). This mirrors the existing split between `MyHomeApp/Features/Settings/` (UI) and `MyHomeApp/Security/` (port + conformer).

2. **No new @Model types:** Phase 6 introduces zero SwiftData models. There are no migration plan changes. The `ModelContainer+App.swift` and `SchemaV3.swift` are untouched.

3. **Test target:** All new test files go in `MyHomeTests/` (not a separate target). The test double support files go in `MyHomeTests/Support/` alongside `SpyBiometricAuth.swift` and `SpyCenter.swift`.

4. **`@testable import MyHome`** (not `import MyHome`) — check `SpyBiometricAuth.swift` line 3. All test files in this project use `@testable import MyHome`.

5. **Swift Testing `#expect`, not XCTest `XCTAssert`** — the entire test suite uses Swift Testing. `import Testing` is the correct import, not `import XCTest`.
