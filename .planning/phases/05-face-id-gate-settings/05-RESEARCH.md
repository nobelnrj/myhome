# Phase 5: Face ID Gate & Settings - Research

**Researched:** 2026-06-02
**Domain:** LocalAuthentication (LAContext/LAError), SwiftUI scenePhase lifecycle, App Group UserDefaults, Settings tab composition, ManageCategoriesView reuse
**Confidence:** HIGH — all claims grounded in codebase inspection and verified Apple API surface; LAError.passcodeNotSet confirmed via web search against Apple canonical docs.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D5-01:** Gate triggers on cold launch AND return from background after ~3-min grace period (180s constant). Quick app-switches within the window do NOT re-prompt. Track backgrounding timestamp; compare elapsed on scenePhase foreground transition.
- **D5-02:** Locked/inactive UI = privacy blur overlay + dedicated unlock screen with an Unlock button. Never a blank gate or auto-only prompt.
- **D5-03:** `LAPolicy.deviceOwnerAuthentication` (Face ID first, then system passcode in same OS prompt). No custom passcode path.
- **D5-04:** On `.biometryNotAvailable`/`.biometryNotEnrolled`, `deviceOwnerAuthentication` auto-falls through to device passcode. No special UI needed.
- **D5-05:** When device has NO passcode (canEvaluatePolicy fails with `LAError.passcodeNotSet`) AND lock is enabled: hard-block with reachable escape. Show guidance. Re-evaluate on next foreground; no data loss.
- **D5-06:** On `.userCancel`, `.authenticationFailed`, `.systemCancel`, `.appCancel`, `.userFallback`, `.biometryLockout` — stay on unlock screen with visible Retry/Unlock button. For `.biometryLockout` add passcode-guidance text.
- **D5-07a:** Turning lock ON triggers auth prompt; only enables on success.
- **D5-07b:** Turning lock OFF requires auth first.
- **D5-07c:** Lock-enabled flag in App Group UserDefaults suite (existing `group.com.reojacob.myhome`). Not Keychain.
- **D5-08:** Budget editing stays on Budgets screen. Settings has a thin "Budgets" row that sets `selectedTab = 2`. No budget UI in Settings.
- **D5-09:** Category management: Settings entry presents `ManageCategoriesView` as-is. Mirror of Budgets tab entry; same view presented from both places.
- **D5-10:** Settings is minimal: lock toggle, category entry, Budgets link, About/version footer. No Gmail placeholder.
- **D5-11:** Settings = tab tag 4 (5th tab). Add to RootView TabView after Notes (tag 3). Budgets deep-link sets `selectedTab = 2`. Settings needs access to `selectedTab` binding.

### Claude's Discretion

- **D5-12:** Planner/researcher calls: Settings tab icon+label; exact grace constant (start 180s); scene-phase/lifecycle seam (App vs RootView); lock controller must be `@Observable`; protocol-port test seam mirroring NotificationCenterPort/SpyCenter; whether category entry is sheet or NavigationLink push; exact copy for unlock screen; About/version footer content.

### Deferred Ideas (OUT OF SCOPE)

- Gmail section in Settings (SEC-03, SET-04, SET-05) — Phase 6
- Custom in-app PIN/passcode
- Per-record/per-note encryption
- Configurable grace-period UI
- Biometric re-auth for individual sensitive actions

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-01 | User can require Face ID to open the app; toggle in Settings | LockController @Observable + UserDefaults flag (D5-07c); toggle wired in SettingsView |
| SEC-02 | Face ID falls back to device passcode via LAPolicy.deviceOwnerAuthentication; every LAError case handled explicitly | Full LAError enum surface documented below; protocol-port test seam for unit testability |
| SET-01 | User can toggle Face ID lock on/off | Toggle in SettingsView; auth-to-enable (D5-07a), auth-to-disable (D5-07b) |
| SET-02 | User can manage categories (add, rename, delete) | ManageCategoriesView reused verbatim from Budgets tab |
| SET-03 | User can manage per-category monthly budgets | "Budgets" deep-link row in SettingsView sets selectedTab = 2 (D5-08 deviation) |

</phase_requirements>

---

## Summary

Phase 5 adds two self-contained deliverables to a fully-implemented 4-tab app: (1) a LocalAuthentication gate with grace-period re-lock and full LAError coverage, and (2) a 5th Settings tab. No new `@Model` types. No schema migration. The lock-enabled flag lives in App Group UserDefaults. Category management reuses `ManageCategoriesView` verbatim.

The central design choice is a small `@Observable` `LockController` that owns all gate state (isLocked, isBlurred, backgroundedAt, lockEnabled). Wrapping `LAContext` behind a `BiometricAuthPort` protocol — modeled on the existing `NotificationCenterPort`/`SpyCenter` seam from Phase 3 — makes every LAError path unit-testable without a device. The gate is wired at the `RootView` level (not the App entry) so it can overlay the `TabView` and access the `selectedTab` binding without structural changes to `MyHomeApp.swift`.

The `ManageCategoriesView` is fully reusable from Settings as-is — it uses `@Environment(\.modelContext)` + `@Query` and presents its own `NavigationStack`, making it suitable for sheet presentation from either caller. The `selectedTab` binding pattern is already established in `OverviewView.swift` and threads identically into `SettingsView`.

**Primary recommendation:** Build `LockController` (pure logic, `@Observable`) + `BiometricAuthPort` (protocol) first; wire the overlay in `RootView`; then add `SettingsView` as a thin composer.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Biometric/passcode evaluation | OS (LocalAuthentication) | LockController | LAContext calls happen inside LockController; the OS prompt is fully managed by the system |
| Lock state tracking (isLocked, grace, blur) | LockController (@Observable) | RootView | Pure value logic — testable without UI; RootView observes and applies overlays |
| Privacy blur overlay | RootView (SwiftUI) | LockController | scenePhase observation belongs at the view boundary where .blur modifier lives |
| Unlock screen presentation | UnlockView (SwiftUI) | RootView | Conditional overlay over TabView when isLocked == true |
| Lock-enabled preference | App Group UserDefaults | LockController | Preference, not secret; suite name `group.com.reojacob.myhome` already established |
| Settings tab shell | SettingsView (SwiftUI) | RootView | New tab tag 4; receives selectedTab Binding<Int> for Budgets deep-link |
| Category management | ManageCategoriesView (reuse) | SettingsView | Presented as sheet from SettingsView; same view presented from BudgetsView toolbar |
| Budgets deep-link | selectedTab binding | SettingsView | Sets selectedTab = 2; pattern already used by OverviewView |
| About/version footer | SettingsView | Bundle | Read from Bundle.main; no model involvement |

---

## Standard Stack

### Core (all already in the project)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| LocalAuthentication | iOS 17+ (built-in) | LAContext, LAPolicy, LAError evaluation | The only Apple-blessed biometric/passcode gate API; no third-party needed |
| SwiftUI | iOS 17+ | scenePhase observation, overlay, TabView | Project stack; no UIKit permitted |
| Foundation | iOS 17+ | UserDefaults(suiteName:), Date arithmetic for grace elapsed | Standard platform |

**No new package dependencies.** LocalAuthentication is a system framework — `import LocalAuthentication` only.

### Supporting patterns (new code in this phase)

| Component | Kind | Purpose |
|-----------|------|---------|
| `BiometricAuthPort` | Protocol | Wraps LAContext so LAError paths are unit-testable |
| `SystemBiometricAuth` | Struct | Production conformer; thin wrapper around LAContext |
| `SpyBiometricAuth` | Struct (test target) | In-memory fake; returns canned (Bool, LAError?) pairs |
| `LockController` | @Observable class | Owns isLocked, isBlurred, lockEnabled, backgroundedAt, grace logic |
| `UnlockView` | SwiftUI View | Dedicated locked screen with app icon + Unlock button + error state text |
| `SettingsView` | SwiftUI View | Settings tab shell: lock toggle, category entry, Budgets row, About footer |
| `LockGateOverlay` | SwiftUI ViewModifier | Applies blur + UnlockView overlay; attached to RootView's TabView |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| @Observable LockController in RootView | State in MyHomeApp.swift | App-level state works but makes the gate observable across the whole scene hierarchy; RootView is sufficient and matches existing pattern (deepLinkNoteID lives in RootView) |
| Protocol-port (BiometricAuthPort) | Direct LAContext in LockController | Direct use is simpler but makes LAError paths untestable without a device; mirror the NotificationCenterPort precedent |
| Sheet for ManageCategoriesView from Settings | NavigationLink push | Sheet matches existing BudgetsView presentation; keeps consistent UX |

**Installation:** No new packages. Add `import LocalAuthentication` to new files only.

---

## Package Legitimacy Audit

No external packages are introduced in this phase. `LocalAuthentication` is an Apple system framework. No npm/PyPI/cargo packages involved.

**Packages removed due to slopcheck:** none
**Packages flagged as suspicious:** none

---

## Architecture Patterns

### System Architecture Diagram

```
App launch / foreground
        │
        ▼
  MyHomeApp.swift (unchanged)
  .modelContainer(container)
        │
        ▼
  RootView
  ├─ @State selectedTab: Int          ← used by OverviewView AND SettingsView
  ├─ @State private var lockController = LockController()
  │          │
  │          │ reads App Group UserDefaults("group.com.reojacob.myhome")
  │          │ wraps BiometricAuthPort (SystemBiometricAuth in prod)
  │
  ├─ .onChange(of: scenePhase) ──────► LockController.scenePhaseChanged(_:)
  │     • .inactive / .background    ─► isBlurred = true; stamp backgroundedAt
  │     • .active                    ─► isBlurred = false; evaluate grace elapsed
  │          │                            if elapsed > 180s → isLocked = true
  │          │                            else → no re-lock
  │
  ├─ TabView(selection: $selectedTab)
  │   ├─ OverviewView(selectedTab: $selectedTab, ...)  tag 0
  │   ├─ ExpenseListView()                             tag 1
  │   ├─ BudgetsView()                                 tag 2
  │   ├─ NotesHomeView(...)                            tag 3
  │   └─ SettingsView(selectedTab: $selectedTab)       tag 4 (NEW)
  │
  ├─ Overlay A: privacy blur (active when isBlurred == true)
  │   .blur(radius: 20) — covers TabView snapshot in app switcher
  │
  └─ Overlay B: UnlockView (shown when isLocked == true AND lockEnabled == true)
      ├─ App icon + title
      ├─ "Unlock" button ──► LockController.authenticate()
      │     calls BiometricAuthPort.evaluate(.deviceOwnerAuthentication)
      │     on success: isLocked = false
      │     on failure: errorState updated → error text shown + Unlock button stays
      │
      └─ Error states (mapped from LAError):
          .userCancel / .appCancel / .systemCancel → stay on screen, no message
          .authenticationFailed → "Authentication failed. Try again."
          .userFallback → re-attempt (deviceOwnerAuthentication handles passcode prompt)
          .biometryLockout → "Too many attempts. Use your device passcode."
          .biometryNotAvailable / .biometryNotEnrolled → transparent (policy auto-falls to passcode)
          .passcodeNotSet → hard-block message + guidance to set passcode in Settings

SettingsView (tag 4)
  ├─ Section "Security"
  │   └─ Toggle "Face ID Lock" → LockController.setLockEnabled(true/false)
  │         • enabling: authenticate first, then set lockEnabled = true in UserDefaults
  │         • disabling: authenticate first, then set lockEnabled = false in UserDefaults
  ├─ Section "Data"
  │   ├─ "Manage Categories" row → .sheet(ManageCategoriesView)
  │   └─ "Budgets" row → selectedTab = 2 (Budgets deep-link)
  └─ Section "About"
      └─ version + build from Bundle.main
```

### Recommended Project Structure (additions only)

```
MyHomeApp/
├── Features/
│   └── Settings/                    # New feature folder
│       ├── SettingsView.swift       # Settings tab shell (tag 4)
│       └── UnlockView.swift         # Dedicated lock/unlock screen
├── Security/                        # New folder
│   ├── LockController.swift         # @Observable gate state + grace logic
│   └── BiometricAuthPort.swift      # Protocol + SystemBiometricAuth conformer
MyHomeTests/
└── Support/
    └── SpyBiometricAuth.swift       # Test double (mirrors SpyCenter.swift shape)
MyHomeTests/
└── LockControllerTests.swift        # Unit tests for grace math + error mapping
```

### Pattern 1: BiometricAuthPort (mirrors NotificationCenterPort)

**What:** Protocol port abstracting LAContext so test doubles can return canned errors.
**When to use:** Always — inject in LockController init, default to SystemBiometricAuth in production.

```swift
// Source: modeled on MyHomeApp/Support/NotificationCenterPort.swift

import LocalAuthentication

public protocol BiometricAuthPort: Sendable {
    /// Returns (success, error). Caller maps LAError to action.
    func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?)
    /// Returns whether the policy can be evaluated; sets error if not (e.g. passcodeNotSet).
    func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?)
}

public struct SystemBiometricAuth: BiometricAuthPort, Sendable {
    public init() {}
    
    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        let context = LAContext()
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

**Test double (SpyBiometricAuth) — in MyHomeTests/Support/:**

```swift
// Source: mirrors MyHomeTests/Support/SpyCenter.swift pattern

import LocalAuthentication
@testable import MyHome

public final class SpyBiometricAuth: BiometricAuthPort, @unchecked Sendable {
    // Settable stubs
    public var evaluateResult: (Bool, Error?) = (true, nil)
    public var canEvaluateResult: (Bool, Error?) = (true, nil)
    // Recorded calls
    public private(set) var evaluateCalls: [LAPolicy] = []
    public private(set) var canEvaluateCalls: [LAPolicy] = []

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        evaluateCalls.append(policy)
        return evaluateResult
    }
    public func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?) {
        canEvaluateCalls.append(policy)
        return canEvaluateResult
    }
}
```

### Pattern 2: LockController (@Observable)

**What:** `@Observable` class owned by RootView via `@State`. Holds all gate state. Grace logic is pure date math. [VERIFIED: codebase — matches @Observable rule from PITFALLS.md and RootView pattern]

```swift
// Source: @Observable pattern — mirrors established project pattern (PITFALLS.md Pitfall 10)

import Foundation
import SwiftUI
import LocalAuthentication

@Observable
final class LockController {
    // MARK: - Persistent
    var lockEnabled: Bool {
        get { UserDefaults(suiteName: "group.com.reojacob.myhome")?.bool(forKey: "lockEnabled") ?? false }
        set { UserDefaults(suiteName: "group.com.reojacob.myhome")?.set(newValue, forKey: "lockEnabled") }
    }

    // MARK: - Runtime state
    var isLocked: Bool = false
    var isBlurred: Bool = false
    var authError: LockAuthError? = nil

    private var backgroundedAt: Date? = nil
    private let gracePeriod: TimeInterval = 180  // D5-01: 180s constant

    private let auth: any BiometricAuthPort

    init(auth: any BiometricAuthPort = SystemBiometricAuth()) {
        self.auth = auth
        // Lock on cold launch if enabled (D5-01)
        if lockEnabled { isLocked = true }
    }

    // MARK: - Scene phase hook (called from RootView)

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isBlurred = false
            if lockEnabled, let bg = backgroundedAt {
                let elapsed = Date().timeIntervalSince(bg)
                if elapsed > gracePeriod { isLocked = true }
                backgroundedAt = nil
            }
        case .inactive, .background:
            isBlurred = true
            if backgroundedAt == nil { backgroundedAt = Date() }
        @unknown default:
            break
        }
    }

    // MARK: - Authentication

    func authenticate() async {
        authError = nil
        let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
        if !canEval {
            if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
                authError = .noPasscode    // D5-05 hard-block
            }
            return
        }
        let (success, error) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Unlock MyHome to access your data."
        )
        if success {
            isLocked = false
            authError = nil
        } else {
            authError = mapError(error)   // D5-06
        }
    }

    // MARK: - Toggle (D5-07a / D5-07b)

    func enableLock() async {
        let (success, _) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Verify your identity to enable the lock."
        )
        if success { lockEnabled = true }
    }

    func disableLock() async {
        let (success, _) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Verify your identity to disable the lock."
        )
        if success { lockEnabled = false }
    }

    // MARK: - Private

    private func mapError(_ error: Error?) -> LockAuthError? {
        guard let laError = error as? LAError else { return .unknown }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel: return nil  // stay on screen, no message
        case .authenticationFailed:                  return .failed
        case .userFallback:                          return nil  // OS passcode prompt follows
        case .biometryLockout:                       return .biometryLocked
        case .biometryNotAvailable, .biometryNotEnrolled: return nil  // auto-fallback, silent
        case .passcodeNotSet:                        return .noPasscode
        default:                                     return .unknown
        }
    }
}

enum LockAuthError {
    case failed         // "Authentication failed. Try again."
    case biometryLocked // "Too many attempts. Use your device passcode."
    case noPasscode     // "Set a device passcode in iOS Settings to unlock this app, then return."
    case unknown        // generic retry
}
```

### Pattern 3: scenePhase wiring in RootView

**What:** `.onChange(of: scenePhase)` observer on the TabView, forwarded to `LockController`. [VERIFIED: codebase — RootView.swift; createwithswift.com pattern]

```swift
// Source: createwithswift.com — scenePhase privacy blur; project RootView.swift pattern

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int = 0
    @State private var lockController = LockController()
    // ... existing deepLink states ...

    var body: some View {
        TabView(selection: $selectedTab) {
            // ... existing tabs 0-3 ...
            SettingsView(selectedTab: $selectedTab, lockController: lockController)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        // Privacy blur — covers all tab content in app switcher (D5-02)
        .blur(radius: lockController.isBlurred ? 20 : 0)
        // Unlock screen overlay (D5-02)
        .overlay {
            if lockController.isLocked && lockController.lockEnabled {
                UnlockView(lockController: lockController)
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            lockController.scenePhaseChanged(newPhase)
            // On .active and lock is triggered, attempt auth automatically
            if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
                Task { await lockController.authenticate() }
            }
        }
        // ... existing .onReceive for kOpenNoteNotification ...
    }
}
```

**Important:** The automatic `authenticate()` call on `.active` gives a smooth feel but the UnlockView must still show the manual Unlock button — if the user cancels or the error is `noPasscode`, the Unlock button is the recovery path (D5-02, D5-05).

### Pattern 4: App Group UserDefaults read/write

**What:** The lock-enabled flag persists in the same App Group suite already used by the app store. [VERIFIED: codebase — ModelContainer+App.swift line 23]

```swift
// Source: MyHomeApp/Persistence/ModelContainer+App.swift
// Suite name: "group.com.reojacob.myhome" (confirmed in file)

let suite = "group.com.reojacob.myhome"
let defaults = UserDefaults(suiteName: suite)
defaults?.set(true, forKey: "lockEnabled")        // write
let enabled = defaults?.bool(forKey: "lockEnabled") ?? false  // read
```

**Note:** `UserDefaults(suiteName:)` returns nil when the App Group entitlement is not active (free dev account / simulator without App Group). Fall back to `UserDefaults.standard` during testing only. In production, the entitlement is present.

### Pattern 5: selectedTab Binding<Int> threading

**What:** `SettingsView` receives `selectedTab: Binding<Int>` to implement the Budgets deep-link (D5-08). Pattern identical to `OverviewView`. [VERIFIED: codebase — OverviewView.swift line 17, RootView.swift lines 25, 43]

```swift
// Source: MyHomeApp/Features/Overview/OverviewView.swift — existing pattern

// In SettingsView:
struct SettingsView: View {
    @Binding var selectedTab: Int
    // ... lockController passed as let (read only from Settings)
    
    var body: some View {
        NavigationStack {
            List {
                // ... sections ...
                Section {
                    Button("Budgets") { selectedTab = 2 }  // D5-08 deep-link
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

### Pattern 6: ManageCategoriesView reuse

**What:** Present `ManageCategoriesView` as a sheet from a Settings row. No modifications to `ManageCategoriesView`. [VERIFIED: codebase — ManageCategoriesView.swift; self-contained with NavigationStack + @Query + @Environment(\.modelContext)]

```swift
// Source: MyHomeApp/Features/Budgets/BudgetsView.swift — existing presentation pattern

// In SettingsView:
@State private var showManageCategories = false

Button("Manage Categories") { showManageCategories = true }

.sheet(isPresented: $showManageCategories) {
    ManageCategoriesView()  // reused verbatim — has its own NavigationStack
}
```

`ManageCategoriesView` has its own `NavigationStack` internally and uses `@Environment(\.dismiss)`, so it is fully self-contained when presented as a sheet from any parent. No modifications required.

### Anti-Patterns to Avoid

- **Using `LAPolicy.deviceOwnerAuthenticationWithBiometrics` instead of `.deviceOwnerAuthentication`:** The biometrics-only policy does NOT fall through to the device passcode automatically. The project requires the combined policy (SEC-02).
- **Locking in `MyHomeApp.body` (WindowGroup level):** Scene phase observation at the App level works, but the lock controller cannot easily access the `selectedTab` binding and RootView already owns all per-session state. Wire in RootView.
- **Using `@StateObject` or `@ObservedObject` for LockController:** The project enforces `@Observable`/`@State`/`@Bindable` only (PITFALLS.md Pitfall 10). LockController must be `@Observable`, owned via `@State private var lockController = LockController()` in RootView.
- **Storing lockEnabled in standard UserDefaults (not App Group suite):** The app already uses `group.com.reojacob.myhome` for the model store. Consistent. Also important for future Widget/Watch extensions.
- **Setting `isBlurred = false` before the auth completes:** The blur must stay active until `.active` phase is confirmed, not until the auth prompt appears. Otherwise the app content flashes briefly in the app switcher.
- **Not handling `.passcodeNotSet` separately:** This error comes from `canEvaluatePolicy`, not `evaluatePolicy`. Must call `canEvaluate` first; otherwise `evaluatePolicy` will throw immediately and `.passcodeNotSet` can be conflated with other failures.
- **Calling `authenticate()` inside `onChange` synchronously:** LAContext evaluation is `async`. Always use `Task { await lockController.authenticate() }`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Face ID + passcode fallback in one prompt | Custom passcode UI | `LAPolicy.deviceOwnerAuthentication` | The OS handles biometry → passcode fallback in a single system prompt; custom UI duplicates system UX and bypasses Apple's security model |
| Blur on app switcher | UIKit-based window snapshot override | `.blur(radius:)` + scenePhase `.inactive`/`.background` | Native SwiftUI approach; no UIKit WindowScene manipulation needed |
| App version string | Hand-crafted constant | `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` | Auto-updates with Xcode build config; no drift |
| LAContext mock for tests | Partial LAContext subclass | `BiometricAuthPort` protocol + `SpyBiometricAuth` | Protocol port is the established project pattern (NotificationCenterPort); LAContext cannot be meaningfully subclassed in test environments |
| UserDefaults wrapper | Custom persistence class | `UserDefaults(suiteName: "group.com.reojacob.myhome")` | The suite is already established; direct use is the project pattern |

**Key insight:** LocalAuthentication is designed to be called with a single policy and a reason string. The OS owns the prompt UX, the fallback sequencing, and the lockout policy. The developer owns only: what policy to use, what reason string to show, and how to handle the returned success/error. Everything else is Apple's problem.

---

## LAError Enum Surface (SEC-02 — Complete Reference)

All cases from `SEC-02` requirement and their recommended action in this app:

[VERIFIED: developer.apple.com/documentation/localauthentication/laerror/code — confirmed via WebSearch against Apple canonical docs]

| LAError.Code | When it fires | Source (canEvaluate vs evaluate) | Action in this app (D5-05/D5-06) |
|---|---|---|---|
| `.passcodeNotSet` | Device has no passcode configured | `canEvaluatePolicy` | Hard-block (D5-05): show guidance, re-evaluate on next foreground |
| `.biometryNotAvailable` | Device has no biometric hardware | `canEvaluatePolicy` or `evaluatePolicy` | Transparent: `deviceOwnerAuthentication` auto-falls to passcode; no special UI |
| `.biometryNotEnrolled` | Hardware present but no biometrics enrolled | `canEvaluatePolicy` or `evaluatePolicy` | Transparent: same auto-fallback to passcode |
| `.biometryLockout` | Too many failed biometric attempts | `evaluatePolicy` | D5-06: stay on unlock screen; add text "Use your device passcode" |
| `.userFallback` | User tapped "Enter Password" in biometric prompt | `evaluatePolicy` | D5-06: re-attempt; `deviceOwnerAuthentication` will have already shown passcode prompt |
| `.userCancel` | User explicitly dismissed the prompt | `evaluatePolicy` | D5-06: stay on unlock screen, no message (user chose to cancel) |
| `.appCancel` | App called `invalidate()` on LAContext | `evaluatePolicy` | D5-06: stay on unlock screen, no message |
| `.systemCancel` | System cancelled (incoming call, lock) | `evaluatePolicy` | D5-06: stay on unlock screen, no message |
| `.authenticationFailed` | Biometric/passcode scan failed | `evaluatePolicy` | D5-06: "Authentication failed. Try again." |

**`canEvaluatePolicy` vs `evaluatePolicy` semantics:**
- Call `canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)` first. If it returns `false`, check the error — `.passcodeNotSet` means D5-05 hard-block path. Other errors are edge cases.
- `evaluatePolicy` is async (use `try await context.evaluatePolicy(...)` in Swift 6). The completion-handler variant is deprecated in Swift 6 concurrency context.
- `deviceOwnerAuthentication`: Face ID → if biometry unavailable/fails/locked, OS automatically shows passcode. The app gets ONE result (success or error). No second call needed.

[ASSUMED: The exact conditions under which `.userFallback` fires with `deviceOwnerAuthentication` vs `deviceOwnerAuthenticationWithBiometrics` differ — with `deviceOwnerAuthentication`, tapping "Enter Password" in the Face ID prompt is handled by the OS internally and may not surface `.userFallback` to the app at all. The safe handling is: treat `.userFallback` as "stay on unlock screen, OS already transitioned to passcode input."]

---

## Common Pitfalls

### Pitfall 1: scenePhase `.inactive` fires before `.background` — blur must cover both

**What goes wrong:** If blur is only applied on `.background`, the app content is briefly visible in the app switcher snapshot (taken during `.inactive`).
**Why it happens:** iOS takes the app switcher screenshot during the `.inactive` phase, before `.background`. Watching only `.background` is too late.
**How to avoid:** Apply blur on both `.inactive` AND `.background`. The `scenePhaseChanged` implementation above sets `isBlurred = true` on either. [VERIFIED: createwithswift.com pattern]
**Warning signs:** App content visible in app switcher after implementing blur.

### Pitfall 2: LAContext reuse across multiple evaluate calls

**What goes wrong:** Reusing a single `LAContext` instance for sequential auth attempts causes errors or silent no-ops after the first evaluation completes.
**Why it happens:** LAContext is single-use per evaluation. After one `evaluatePolicy` call (success or failure), the context's state is consumed.
**How to avoid:** Create a new `LAContext()` for each `evaluate` call. The `SystemBiometricAuth.evaluate` implementation above creates a fresh context inside the function every time.
**Warning signs:** Second auth attempt silently fails or returns stale results.

### Pitfall 3: Thread safety of LockController from scenePhase

**What goes wrong:** `scenePhaseChanged` mutates `@Observable` state from a non-main-actor context, triggering Swift 6 strict concurrency warnings or crashes.
**Why it happens:** scenePhase `.onChange` fires on the main thread in SwiftUI, but explicit `Task { }` blocks inside can escape to a background executor.
**How to avoid:** Mark `LockController` with `@MainActor` isolation, OR ensure all state mutations go through `await MainActor.run {}`. Since `RootView` already runs on the main actor, and `LockController` is owned by a `@State` in `RootView`, marking `LockController` `@MainActor` is the clean path. The `authenticate()` function is `async` and safe to call from `Task { await lockController.authenticate() }` inside `onChange`.
**Warning signs:** Swift 6 "Sending non-sendable value" errors; Xcode warning about main actor isolation.

### Pitfall 4: Grace period timestamp persists across cold launches

**What goes wrong:** `backgroundedAt` stored as an instance property resets to `nil` on app kill. On cold launch after a long absence, `backgroundedAt == nil` so no elapsed-time check runs — the app would not re-lock even though it should.
**Why it happens:** Cold launch is a separate code path from foreground-from-background.
**How to avoid:** Cold launch is handled separately by the LockController initializer: `if lockEnabled { isLocked = true }`. The grace period only applies to foreground-from-background transitions within the same process lifetime (D5-01: "cold launch AND return from background"). This is correct as specified — grace period is an intra-session concept.
**Warning signs:** App does not lock on cold launch even when lock is enabled.

### Pitfall 5: Toggle auth prompt blocks SettingsView UI

**What goes wrong:** Calling `enableLock()` or `disableLock()` as async from a SwiftUI Button without `Task {}` causes a compiler error. Calling with `Task {}` but forgetting to show feedback leaves the toggle in an ambiguous state.
**Why it happens:** Async functions cannot be called directly in synchronous SwiftUI action closures.
**How to avoid:** Use `Button { Task { await lockController.enableLock() } }`. The toggle's `isOn` binding must reflect `lockController.lockEnabled` directly (an `@Observable` property backed by UserDefaults), so it updates automatically when `enableLock()` completes.
**Warning signs:** Toggle snaps back to previous state before auth completes.

### Pitfall 6: App Group UserDefaults returns nil in simulator without entitlement

**What goes wrong:** `UserDefaults(suiteName: "group.com.reojacob.myhome")` returns `nil` in the simulator if the App Group entitlement is not active (free dev account).
**Why it happens:** App Groups require the entitlement to be provisioned; in development without a paid account, the container URL may not resolve.
**How to avoid:** The existing codebase already has this fallback in `ModelContainer+App.swift` (lines 22-33). For `LockController.lockEnabled`, add the same guard: fall back to `UserDefaults.standard` if the suite returns nil. In practice, the App Group is active in the existing app (the store is using it), so this is a test-context concern only.
**Warning signs:** `UserDefaults(suiteName:)` always returns `false` for `lockEnabled` even after setting it.

---

## Code Examples

### Version string for About footer

```swift
// Source: Apple Bundle API — standard pattern
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
// Display: "MyHome v1.0 (build 42)"
```

### Minimal UnlockView sketch

```swift
// Source: D5-02 decisions — "real screen with an Unlock button"; never blank
struct UnlockView: View {
    let lockController: LockController

    var body: some View {
        VStack(spacing: 32) {
            Image("AppIcon")  // or Image(systemName: "house.circle.fill")
                .resizable().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 18))
            Text("MyHome").font(.title2).fontWeight(.semibold)

            if let error = lockController.authError {
                Text(errorMessage(for: error))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Button("Unlock") { Task { await lockController.authenticate() } }
                .buttonStyle(.borderedProminent).controlSize(.large)

            // D5-05 escape: guidance text when noPasscode
            if lockController.authError == .noPasscode {
                Text("Open the Settings app → Face ID & Passcode to set a device passcode, then return here.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func errorMessage(for error: LockAuthError) -> String {
        switch error {
        case .failed:         return "Authentication failed. Try again."
        case .biometryLocked: return "Too many failed attempts. Use your device passcode."
        case .noPasscode:     return "No device passcode is set."
        case .unknown:        return "Authentication unavailable. Try again."
        }
    }
}
```

### Settings toggle wiring (D5-07a/b)

```swift
// In SettingsView — D5-07a (enable) and D5-07b (disable) auth-to-toggle pattern
Toggle("Face ID Lock", isOn: Binding(
    get: { lockController.lockEnabled },
    set: { newValue in
        Task {
            if newValue {
                await lockController.enableLock()   // auth-to-enable
            } else {
                await lockController.disableLock()  // auth-to-disable
            }
        }
    }
))
```

---

## Runtime State Inventory

No rename/refactor/migration involved in this phase. Greenfield additions only. Phase 5 introduces no new `@Model` types and no schema migration — explicitly confirmed in CONTEXT.md.

**Nothing found in any category** — verified by phase scope review. All changes are additive new files. No stored data, live service config, OS-registered state, secrets, or build artifacts need updating.

---

## Open Questions

1. **Automatic auth on foreground vs manual-only**
   - What we know: D5-02 requires a visible Unlock button; D5-01 says the gate triggers on foreground after grace expires.
   - What's unclear: Whether the app should auto-trigger the LAContext prompt immediately on foreground (banking-app feel), or wait for the user to tap Unlock.
   - Recommendation: Auto-trigger on foreground (provides banking-app feel per D5 specifics) but always leave the Unlock button visible so the user can retry if they cancel. Implemented in the `onChange(of: scenePhase)` pattern above.
   [ASSUMED: Auto-trigger on foreground is the right UX call; planner should confirm if user wants explicit tap-to-trigger instead.]

2. **LockController ownership: @State in RootView vs .environment injection**
   - What we know: `deepLinkNoteID` and `deepLinkBlockID` are `@State` in RootView; SettingsView needs to call `lockController.enableLock()/disableLock()`.
   - What's unclear: Whether LockController should be passed as a let parameter to SettingsView or injected via `.environment`.
   - Recommendation: Pass as `let lockController: LockController` (same as how `OverviewView` receives its dependencies). `.environment` injection is appropriate for app-wide services, but LockController is only needed by RootView (for overlay logic) and SettingsView (for the toggle). Direct parameter passing is simpler.

3. **BiometricAuthPort module visibility**
   - What we know: `NotificationCenterPort` is declared `public` (file line 13) so `SpyCenter` can conform from the test target with `@testable import MyHome`.
   - What's unclear: Whether `BiometricAuthPort` and `SystemBiometricAuth` should be `public` or `internal` with `@testable`.
   - Recommendation: Match the existing precedent — declare `BiometricAuthPort` as `public` and `SystemBiometricAuth` as `public final class`. `SpyBiometricAuth` lives in the test target with `@testable import MyHome`.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| LocalAuthentication.framework | Face ID gate | ✓ | iOS 17+ built-in | — |
| Xcode 26.5 | Build/run | ✓ | 26.5 (from memory context) | — |
| iPhone 17 simulator | Testing | ✓ | iOS 17+ runtime | — |
| App Group entitlement (`group.com.reojacob.myhome`) | UserDefaults lock flag | ✓ (existing) | Already in project | Fall back to UserDefaults.standard in tests |
| Face ID simulator support | Manual gate testing | ✓ | Simulator → Features → Face ID | Device for production validation |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** App Group entitlement may not resolve on free dev account / CI; LockController.lockEnabled should fall back to `UserDefaults.standard` in that case (match ModelContainer+App.swift fallback pattern).

**LAError testing note:** Simulator supports Face ID faking via **Features → Face ID → Matching Face / Non-matching Face**. `.biometryLockout`, `.passcodeNotSet`, and `.systemCancel` cannot be triggered via simulator UI — use `SpyBiometricAuth` to inject these error paths in unit tests. Manual device testing required for `.biometryLockout` (repeated failed scans).

---

## Validation Architecture

`workflow.nyquist_validation: true` in `.planning/config.json` — section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (xcodebuild test, `@Test` / `#expect`) |
| Config file | MyHome.xcodeproj (existing test target: MyHomeTests) |
| Quick run command | `xcodebuild test -project "MyHome.xcodeproj" -scheme MyHome -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:MyHomeTests/LockControllerTests` |
| Full suite command | `xcodebuild test -project "MyHome.xcodeproj" -scheme MyHome -destination "platform=iOS Simulator,name=iPhone 17"` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-01 | Lock flag persists via UserDefaults; toggling reads/writes correctly | unit | `-only-testing:MyHomeTests/LockControllerTests/lockEnabledPersists` | ❌ Wave 0 |
| SEC-01 | enableLock() calls auth then sets lockEnabled=true; disableLock() calls auth first | unit | `-only-testing:MyHomeTests/LockControllerTests/enableLockRequiresAuth` | ❌ Wave 0 |
| SEC-02 | authenticate() with passcodeNotSet sets authError=.noPasscode (D5-05) | unit | `-only-testing:MyHomeTests/LockControllerTests/passcodeNotSetHardBlock` | ❌ Wave 0 |
| SEC-02 | authenticate() success → isLocked=false | unit | `-only-testing:MyHomeTests/LockControllerTests/successUnlocks` | ❌ Wave 0 |
| SEC-02 | .userCancel / .appCancel / .systemCancel → authError=nil, isLocked stays true | unit | `-only-testing:MyHomeTests/LockControllerTests/cancelKeepsLocked` | ❌ Wave 0 |
| SEC-02 | .biometryLockout → authError=.biometryLocked | unit | `-only-testing:MyHomeTests/LockControllerTests/biometryLockoutMapped` | ❌ Wave 0 |
| SEC-02 | .authenticationFailed → authError=.failed | unit | `-only-testing:MyHomeTests/LockControllerTests/authFailedMapped` | ❌ Wave 0 |
| D5-01 | Grace period: elapsed < 180s → isLocked stays false on foreground | unit | `-only-testing:MyHomeTests/LockControllerTests/graceWindowNoRelock` | ❌ Wave 0 |
| D5-01 | Grace period: elapsed > 180s → isLocked=true on foreground | unit | `-only-testing:MyHomeTests/LockControllerTests/expiredGraceRelocks` | ❌ Wave 0 |
| D5-01 | Cold launch with lockEnabled=true → isLocked=true initially | unit | `-only-testing:MyHomeTests/LockControllerTests/coldLaunchLocked` | ❌ Wave 0 |
| D5-07a | enableLock auth-to-enable: spy returns false → lockEnabled stays false | unit | `-only-testing:MyHomeTests/LockControllerTests/enableLockAuthFailed` | ❌ Wave 0 |
| SET-02/SET-03 | ManageCategoriesView reuse / Budgets deep-link | manual | Tap "Manage Categories" from Settings; tap "Budgets" verifies tab switches to 2 | — |

### Sampling Rate

- **Per task commit:** `xcodebuild test ... -only-testing:MyHomeTests/LockControllerTests`
- **Per wave merge:** full suite `xcodebuild test -project "MyHome.xcodeproj" -scheme MyHome -destination "platform=iOS Simulator,name=iPhone 17"`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/LockControllerTests.swift` — covers all SEC-01, SEC-02, D5-01, D5-07a/b test cases above
- [ ] `MyHomeTests/Support/SpyBiometricAuth.swift` — test double for BiometricAuthPort (mirrors SpyCenter.swift)
- [ ] `MyHomeApp/Security/BiometricAuthPort.swift` — protocol + SystemBiometricAuth
- [ ] `MyHomeApp/Security/LockController.swift` — @Observable lock controller

*(All existing test infrastructure — Swift Testing, in-memory ModelContainer helpers, SpyCenter pattern — is directly applicable. No new framework install needed.)*

---

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1` in `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | YES | LAPolicy.deviceOwnerAuthentication (biometric + passcode fallback); SEC-02 explicit error handling |
| V3 Session Management | YES (limited) | Grace period (180s) acts as session timeout; isLocked state enforces re-authentication |
| V4 Access Control | YES | Lock gate blocks all tab content until authenticated; lockEnabled toggle itself requires auth |
| V5 Input Validation | no | No new user text input in this phase (category management reuses existing validated ManageCategoriesView) |
| V6 Cryptography | no | Lock flag in UserDefaults is not a secret; no encryption needed. Gmail OAuth token (Keychain) is Phase 6. |

### Known Threat Patterns for LocalAuthentication Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Bypass lock by killing app (no re-lock on cold launch) | Elevation of Privilege | LockController init: `if lockEnabled { isLocked = true }` (D5-01 cold launch requirement) |
| Attacker disables lock on unlocked phone | Tampering | D5-07b: disableLock() requires authentication before clearing lockEnabled |
| App switcher snapshot leaks content | Information Disclosure | Privacy blur overlay on `.inactive` + `.background` scenePhase (D5-02) |
| User without passcode gets indefinite access | Elevation of Privilege | D5-05: canEvaluatePolicy check; `.passcodeNotSet` → hard block with guidance |
| Biometry lockout leaves user stranded | Denial of Service | D5-06: `.biometryLockout` maps to guidance text + Unlock button stays; `deviceOwnerAuthentication` allows passcode entry |
| LAContext reuse across evaluations | Spoofing | Create fresh LAContext per evaluate call (SystemBiometricAuth creates new instance per call) |

**No third-party security libraries.** LocalAuthentication is Apple's security framework; wrapping it in a protocol port is the only abstraction layer.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | With `deviceOwnerAuthentication`, tapping "Enter Password" in the Face ID UI is handled OS-internally and `.userFallback` may not be surfaced to the app | LAError Enum Surface | If `.userFallback` IS surfaced, treat it as "stay on unlock screen" — safe default behavior either way; no data risk |
| A2 | Auto-triggering LAContext prompt on `.active` scenePhase provides the intended "banking app feel" | Pattern 3 / Open Questions | If user prefers explicit tap-to-trigger, planner needs to change `onChange` behavior; no data risk |
| A3 | LockController should be passed as a `let` parameter (not `.environment`) to SettingsView | Architecture | If `.environment` is preferred for testability, requires adding an environment key; low risk |

**All other claims in this research were verified against the codebase or Apple documentation.**

---

## Sources

### Primary (HIGH confidence)

- Codebase: `MyHomeApp/Persistence/ModelContainer+App.swift` — App Group suite name `group.com.reojacob.myhome` confirmed (line 23)
- Codebase: `MyHomeApp/RootView.swift` — `selectedTab: Binding<Int>` pattern, existing tab tags 0-3
- Codebase: `MyHomeApp/Features/Overview/OverviewView.swift` — `@Binding var selectedTab: Int` template (line 17)
- Codebase: `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — self-contained sheet with NavigationStack + @Query + @Environment(\.modelContext)
- Codebase: `MyHomeApp/Support/NotificationCenterPort.swift` — protocol-port test seam template to mirror
- Codebase: `MyHomeTests/Support/SpyCenter.swift` — test double shape to mirror for SpyBiometricAuth
- Codebase: `MyHomeApp/MyHomeApp.swift` — `scenePhase` not yet observed; gate wires in RootView

### Secondary (MEDIUM confidence)

- [LAError.Code — Apple Developer Documentation](https://developer.apple.com/documentation/localauthentication/laerror/code) — LAError enum cases confirmed via WebSearch against Apple canonical documentation
- [canEvaluatePolicy + passcodeNotSet — Apple Developer Documentation](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication) — confirmed `LAError.passcodeNotSet` is returned by `canEvaluatePolicy` when no device passcode is set
- [scenePhase privacy blur pattern — createwithswift.com](https://www.createwithswift.com/implement-blurring-when-multitasking-in-swiftui/) — `.inactive`/`.background` blur pattern; iOS takes switcher screenshot during `.inactive`
- [App Lock implementation — Medium/Gaurav Harkhani](https://medium.com/@gauravharkhani01/implementing-app-lock-in-ios-everything-you-need-to-know-918d65dff9c0) — grace period timestamp tracking pattern
- `.planning/research/PITFALLS.md` Pitfall 11 — Face ID + LAError edge cases, `deviceOwnerAuthentication` requirement, `@Observable` state management rule

### Tertiary (LOW confidence)

- [ASSUMED] `.userFallback` behavior with `deviceOwnerAuthentication` vs `deviceOwnerAuthenticationWithBiometrics` — training knowledge; verify on device

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — LocalAuthentication is a stable Apple framework; all patterns verified in codebase
- Architecture: HIGH — grounded in existing RootView/OverviewView/NotificationCenterPort patterns in codebase
- LAError enum surface: HIGH — verified via Apple canonical docs (WebSearch)
- Pitfalls: HIGH — grounded in PITFALLS.md, codebase inspection, and Apple API semantics
- UserFallback behavior: LOW — not verifiable without device; marked [ASSUMED]

**Research date:** 2026-06-02
**Valid until:** 2026-07-02 (LocalAuthentication API is stable; ScenePhase is SwiftUI stable)
