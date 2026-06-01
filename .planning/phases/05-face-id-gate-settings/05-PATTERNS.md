# Phase 5: Face ID Gate & Settings — Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MyHomeApp/Security/BiometricAuthPort.swift` | protocol + production conformer | request-response | `MyHomeApp/Support/NotificationCenterPort.swift` | exact |
| `MyHomeTests/Support/SpyBiometricAuth.swift` | test double | request-response | `MyHomeTests/Support/SpyCenter.swift` | exact |
| `MyHomeApp/Security/LockController.swift` | @Observable controller | request-response + event-driven | `MyHomeApp/Features/Notes/EditNoteView.swift` (`Debouncer`) | role-match (`@MainActor` final class) |
| `MyHomeApp/Features/Settings/UnlockView.swift` | SwiftUI view | request-response | `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` (full-screen sheet) | role-match |
| `MyHomeApp/Features/Settings/SettingsView.swift` | SwiftUI view (tab shell) | request-response | `MyHomeApp/Features/Budgets/BudgetsView.swift` + `OverviewView.swift` | exact (List+NavigationStack pattern; Binding<Int> threading) |
| `MyHomeApp/RootView.swift` (modify) | TabView host | event-driven | self (existing file) | self-analog |
| `MyHomeTests/LockControllerTests.swift` | unit tests | request-response | `MyHomeTests/NotificationSchedulerTests.swift` | exact (Swift Testing `@Test`/`#expect`, spy injection) |

---

## Pattern Assignments

---

### `MyHomeApp/Security/BiometricAuthPort.swift` (protocol + conformer, request-response)

**Analog:** `MyHomeApp/Support/NotificationCenterPort.swift`

**Imports pattern** (lines 1–2):
```swift
import Foundation
import UserNotifications
```
Mirror for new file:
```swift
import Foundation
import LocalAuthentication
```

**Protocol declaration pattern** (lines 13–22):
```swift
public protocol NotificationCenterPort: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}
```
Key elements to copy:
- `public` visibility (required so test target can conform via `@testable import MyHome`)
- `: Sendable` constraint on the protocol
- Method signatures use async where the underlying OS call is async

**Production conformer pattern** (lines 30–53):
```swift
public final class SystemNotificationCenter: NotificationCenterPort, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }
    // ... remaining methods thin-wrap center.*
}
```
Key elements to copy:
- `public final class` + `@unchecked Sendable` (LAContext creates a new instance per call — `@unchecked` is correct because `SystemBiometricAuth` is stateless)
- Production init takes the real OS object with a default value
- All methods are thin pass-throughs; no business logic here

**Adapt for BiometricAuthPort:**
```swift
public protocol BiometricAuthPort: Sendable {
    func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?)
    func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?)
}

public struct SystemBiometricAuth: BiometricAuthPort, Sendable {
    public init() {}

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        let context = LAContext()                   // fresh per call — Pitfall 2
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
Note: `struct` (not `class`) is sufficient because `SystemBiometricAuth` holds no mutable state — it creates a fresh `LAContext` per call. Matches `Sendable` without `@unchecked`.

---

### `MyHomeTests/Support/SpyBiometricAuth.swift` (test double, request-response)

**Analog:** `MyHomeTests/Support/SpyCenter.swift`

**File header and import pattern** (lines 1–3):
```swift
import Testing
import UserNotifications
@testable import MyHome
```
Mirror for new file:
```swift
import Testing
import LocalAuthentication
@testable import MyHome
```

**Spy class structure pattern** (lines 16–71):
```swift
public final class SpyCenter: NotificationCenterPort, @unchecked Sendable {

    // MARK: - Settable stubs
    public var authorizationResult: Bool = true

    // MARK: - Recorded calls
    public private(set) var addedRequests: [UNNotificationRequest] = []
    public private(set) var removedIdentifierSets: [[String]] = []

    public init() {}

    // MARK: - NotificationCenterPort
    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationResult
    }
    // ... stub methods return stored values, record calls
}
```
Key elements to copy verbatim in structure:
- `public final class` + `@unchecked Sendable` (mutable stubs; single-threaded test use)
- `public var …Result` for settable stubs (one per protocol method)
- `public private(set) var …Calls: [T]` for recorded call arrays
- `public init() {}`
- Protocol method bodies: record call in array, return stub value
- Optional `reset()` helper for reuse between tests

**Adapt for SpyBiometricAuth:**
```swift
public final class SpyBiometricAuth: BiometricAuthPort, @unchecked Sendable {

    // MARK: - Settable stubs
    public var evaluateResult: (Bool, Error?) = (true, nil)
    public var canEvaluateResult: (Bool, Error?) = (true, nil)

    // MARK: - Recorded calls
    public private(set) var evaluateCalls: [LAPolicy] = []
    public private(set) var canEvaluateCalls: [LAPolicy] = []

    public init() {}

    // MARK: - BiometricAuthPort
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

---

### `MyHomeApp/Security/LockController.swift` (@Observable controller, event-driven + request-response)

**Analog:** `MyHomeApp/Features/Notes/EditNoteView.swift` lines 13–37 (`Debouncer` — `@MainActor final class` with `@State` ownership pattern)

**@MainActor final class pattern** (lines 13–14):
```swift
@MainActor
final class Debouncer {
```
Copy verbatim — `LockController` must be `@MainActor` to satisfy Swift 6 strict concurrency when `onChange(of: scenePhase)` mutates `@Observable` state (RESEARCH Pitfall 3).

**Init pattern** (lines 18–20):
```swift
init(delay: TimeInterval = 0.5) {
    self.delay = delay
}
```
Copy structure — LockController init takes `auth: any BiometricAuthPort = SystemBiometricAuth()` as default, enabling injection in tests.

**Async Task pattern** (lines 22–35 — the task-cancel-restart pattern):
```swift
func schedule(action: @MainActor @escaping () -> Void) {
    task?.cancel()
    task = Task { [delay] in
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            action()
        } catch { /* cancelled */ }
    }
}
```
Key element: calling async work inside `Task { }` from a sync context — same pattern used in LockController's `authenticate()` calls from `.onChange`.

**App Group UserDefaults pattern** — from `MyHomeApp/Persistence/ModelContainer+App.swift` lines 22–26:
```swift
if let groupURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.reojacob.myhome") {
    // use group URL
} else {
    // fall back to applicationSupportDirectory
}
```
Apply same fallback discipline for `LockController.lockEnabled`:
```swift
private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
}
var lockEnabled: Bool {
    get { defaults.bool(forKey: "lockEnabled") }
    set { defaults.set(newValue, forKey: "lockEnabled") }
}
```
Suite name `"group.com.reojacob.myhome"` confirmed in ModelContainer+App.swift line 23.

**`@Observable` discipline** — PITFALLS.md Pitfall 10 (confirmed throughout codebase):
- `@Observable` macro on the class declaration
- Owned by RootView via `@State private var lockController = LockController()`
- Never `@StateObject` / `@ObservedObject` / `@Published`
- Passed to child views as `let lockController: LockController` (value-type reference — `@Observable` classes are observable without wrapping)

---

### `MyHomeApp/Features/Settings/UnlockView.swift` (SwiftUI view, request-response)

**Analog:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift`

**Imports pattern** (line 1):
```swift
import SwiftUI
```
UnlockView needs only SwiftUI (no SwiftData — no @Query, no modelContext).

**Full-screen layout pattern** — ManageCategoriesView uses `NavigationStack { List { … } }` with `.navigationTitle`. UnlockView does NOT use NavigationStack — it is an overlay, not a nav destination. Use plain `VStack` on `Color(.systemBackground)`.

**Error text pattern** (ManageCategoriesView lines 64–68):
```swift
if let error = nameError {
    Text(error)
        .font(.caption)
        .foregroundStyle(Color(.systemRed))
}
```
Adapt for UnlockView error display:
```swift
if let error = lockController.authError {
    Text(errorMessage(for: error))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
}
```
Note: error text uses `.secondary` (not `.systemRed`) per UI-SPEC — muted, not alarming.

**Async button action pattern** (ManageCategoriesView lines 57–60):
```swift
Button("Done") {
    addCategory(name: newCategoryName)
}
```
For async actions, wrap in Task:
```swift
Button("Unlock") {
    Task { await lockController.authenticate() }
}
.buttonStyle(.borderedProminent)
.controlSize(.large)
```

**Accessibility pattern** (ManageCategoriesView lines 48–49):
```swift
.accessibilityHidden(true)   // decorative icons
```
Apply `.accessibilityHidden(true)` to the app icon image on UnlockView. Apply `.accessibilityAddTraits(.isHeader)` to the "MyHome" title label.

---

### `MyHomeApp/Features/Settings/SettingsView.swift` (SwiftUI view, tab shell, request-response)

**Analog A:** `MyHomeApp/Features/Budgets/BudgetsView.swift` (NavigationStack + List + sheet pattern)
**Analog B:** `MyHomeApp/Features/Overview/OverviewView.swift` (Binding<Int> selectedTab threading)

**Imports pattern** (BudgetsView lines 1–2):
```swift
import SwiftUI
import SwiftData
```
SettingsView needs no SwiftData import (no @Query — ManageCategoriesView self-contains SwiftData). Import SwiftUI only.

**`@Binding var selectedTab: Int` pattern** (OverviewView lines 16–18):
```swift
struct OverviewView: View {
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
```
Copy for SettingsView:
```swift
struct SettingsView: View {
    @Binding var selectedTab: Int
    let lockController: LockController
```
`lockController` is `let` (not `@Binding` / `@Bindable`) — `@Observable` classes propagate changes automatically; no wrapper needed.

**NavigationStack + List pattern** (BudgetsView lines 31–53):
```swift
NavigationStack {
    VStack(spacing: 0) { … }
    .navigationTitle("Budgets")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { … }
    .sheet(isPresented: $showManageCategories) {
        ManageCategoriesView()
    }
}
```
Copy the NavigationStack + `.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)` + `.sheet` structure.

**Sheet presentation pattern** (BudgetsView lines 50–52):
```swift
.sheet(isPresented: $showManageCategories) {
    ManageCategoriesView()
}
```
Copy verbatim for SettingsView's category management entry. `ManageCategoriesView` is self-contained (owns its NavigationStack + @Environment(\.dismiss)).

**Sheet trigger state** (BudgetsView line 20):
```swift
@State private var showManageCategories: Bool = false
```
Copy verbatim.

**Async Toggle pattern** — no direct analog in codebase (no existing auth-gated Toggle). From RESEARCH.md Pattern (SettingsView toggle):
```swift
Toggle("Face ID Lock", isOn: Binding(
    get: { lockController.lockEnabled },
    set: { newValue in
        Task {
            if newValue { await lockController.enableLock() }
            else        { await lockController.disableLock() }
        }
    }
))
```
This is required because the toggle action is async. Do NOT use `$lockController.lockEnabled` directly — that would bypass the auth-to-enable/disable requirement (D5-07a/b).

**Budgets deep-link row pattern** — from RootView lines 51–55 (notification deep-link sets selectedTab):
```swift
.onReceive(…) { notification in
    // …
    selectedTab = 3
}
```
The tab-switch mechanism is identical; in SettingsView it's triggered by a Button tap:
```swift
Button {
    selectedTab = 2
} label: {
    HStack {
        Text("Budgets")
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
    }
}
.foregroundStyle(.primary)
```
Use a plain `Button` (not `NavigationLink`) — this is a tab switch, not a push navigation.

---

### `MyHomeApp/RootView.swift` (modify — TabView host)

**Self-analog** — existing file is the pattern source.

**Existing tab pattern** (RootView lines 24–48):
```swift
TabView(selection: $selectedTab) {
    OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
        .tabItem { Label("Home", systemImage: "house") }
        .tag(0)
    ExpenseListView()
        .tabItem { Label("Expenses", systemImage: "list.bullet") }
        .tag(1)
    BudgetsView()
        .tabItem { Label("Budgets", systemImage: "chart.bar") }
        .tag(2)
    NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
        .tabItem { Label("Notes", systemImage: "note.text") }
        .tag(3)
}
```
Add Settings as tag 4 — copy the `.tabItem { Label(…) }.tag(n)` chain:
```swift
SettingsView(selectedTab: $selectedTab, lockController: lockController)
    .tabItem { Label("Settings", systemImage: "gearshape") }
    .tag(4)
```

**`@State` ownership pattern** (RootView lines 17–21):
```swift
@State private var selectedTab: Int = 0
@State private var deepLinkNoteID: UUID? = nil
@State private var deepLinkBlockID: UUID? = nil
```
Add alongside existing state:
```swift
@State private var lockController = LockController()
```
`LockController()` is `@Observable` — owned with `@State`, never `@StateObject`.

**scenePhase + .onChange pattern** — not present in current RootView (scenePhase unwired in MyHomeApp.swift too — confirmed by reading MyHomeApp.swift). Add to RootView:
```swift
@Environment(\.scenePhase) private var scenePhase
```
And in body, after the `.onReceive` block:
```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```
`.onChange(of:)` two-argument form (`{ _, newPhase in }`) matches Swift 5.9+ / iOS 17+ API — the project targets iOS 17+.

**Overlay pattern** — no existing overlay in RootView. Add after the TabView's modifier chain:
```swift
.blur(radius: lockController.isBlurred ? 20 : 0)
.animation(.easeInOut(duration: 0.2), value: lockController.isBlurred)
.overlay {
    if lockController.isLocked && lockController.lockEnabled {
        UnlockView(lockController: lockController)
            .transition(.opacity)
    }
}
```

---

### `MyHomeTests/LockControllerTests.swift` (unit tests, request-response)

**Analog:** `MyHomeTests/NotificationSchedulerTests.swift`

**File header pattern** (lines 1–8):
```swift
import Testing
import UserNotifications
import Foundation
@testable import MyHome
```
Mirror for new file:
```swift
import Testing
import LocalAuthentication
import Foundation
@testable import MyHome
```

**Test struct + @MainActor pattern** (lines 17):
```swift
@MainActor
struct NotificationSchedulerTests {
```
Copy verbatim — LockController is `@MainActor`, so tests must run on MainActor:
```swift
@MainActor
struct LockControllerTests {
```

**Test method pattern** (lines 21–23):
```swift
@Test("buildRequestsLeadAlerts: timed reminder with 2 lead offsets builds 3 requests — SC-R1")
func buildRequestsLeadAlerts() throws {
    let spy = SpyCenter()
    let scheduler = NotificationScheduler(center: spy)
```
Copy the spy-injection setup per test:
```swift
@Test("successUnlocks: successful auth clears isLocked — SEC-02")
func successUnlocks() async throws {
    let spy = SpyBiometricAuth()
    spy.canEvaluateResult = (true, nil)
    spy.evaluateResult = (true, nil)
    let controller = LockController(auth: spy)
    controller.isLocked = true
    await controller.authenticate()
    #expect(controller.isLocked == false)
}
```

**Assertion pattern** (lines 41–48):
```swift
#expect(requests.count == 3, "Expected 3 requests (main + 2 leads), got \(requests.count)")
#expect(identifiers.contains("\(reminderID)-main"), "Missing main identifier")
```
Use `#expect(condition, "message")` — Swift Testing style used throughout the project. Never XCTest `XCTAssertEqual`.

**Stub configuration pattern** (lines 27–36):
```swift
let info = ReminderInfo(
    id: reminderID,
    // ... fields
    leadMinutes: [60, 1440]
)
```
For LockController tests, configure the spy before act:
```swift
spy.canEvaluateResult = (false, LAError(.passcodeNotSet))
spy.evaluateResult = (false, nil)
```

---

## Shared Patterns

### @Observable + @State Ownership
**Source:** `MyHomeApp/Features/Notes/EditNoteView.swift` lines 13–14 (`@MainActor final class Debouncer`)
**Apply to:** `LockController.swift`
```swift
@MainActor
final class Debouncer { … }
// → LockController mirrors: @MainActor + @Observable + final class
```
`@Observable` replaces manual property observation. `@State private var lockController = LockController()` in RootView — never `@StateObject`.

### Protocol-Port Test Seam
**Source:** `MyHomeApp/Support/NotificationCenterPort.swift` full file
**Apply to:** `BiometricAuthPort.swift`
- Protocol: `public`, `: Sendable`
- Production conformer: `public final class` + `@unchecked Sendable` (or `public struct` if stateless) + thin OS wrappers
- Test double: separate file in `MyHomeTests/Support/`, `@testable import MyHome`, `@unchecked Sendable`, settable stubs + recorded calls

### Async Button → Task Pattern
**Source:** `MyHomeApp/Features/Notes/EditNoteView.swift` (Debouncer.schedule uses Task internally)
**Apply to:** `UnlockView.swift`, `SettingsView.swift`
```swift
Button("Unlock") {
    Task { await lockController.authenticate() }
}
```
All async LockController calls from SwiftUI action closures must go through `Task { await … }`. Never call async functions directly from synchronous Button actions.

### NavigationStack + List + Sheet
**Source:** `MyHomeApp/Features/Budgets/BudgetsView.swift` lines 31–53
**Apply to:** `SettingsView.swift`
```swift
NavigationStack {
    List { … }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
}
.sheet(isPresented: $showManageCategories) {
    ManageCategoriesView()
}
```

### selectedTab Binding Threading
**Source:** `MyHomeApp/Features/Overview/OverviewView.swift` line 17; `MyHomeApp/RootView.swift` lines 25, 43
**Apply to:** `SettingsView.swift` initializer + `RootView.swift` tab instantiation
```swift
// RootView passes:
SettingsView(selectedTab: $selectedTab, lockController: lockController)

// SettingsView receives:
struct SettingsView: View {
    @Binding var selectedTab: Int
    let lockController: LockController
```

### App Group UserDefaults Suite Name
**Source:** `MyHomeApp/Persistence/ModelContainer+App.swift` line 23
**Apply to:** `LockController.swift` (lockEnabled computed property)
Suite name: `"group.com.reojacob.myhome"` — confirmed in source. Fall back to `.standard` if suite returns nil (mirrors ModelContainer+App.swift fallback pattern lines 22–33).

### Error Handling — assertionFailure + print
**Source:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` lines 197–200:
```swift
} catch {
    assertionFailure("Failed to save new category: \(error)")
    print("Failed to save new category: \(error)")
}
```
LockController does not throw — it returns `(Bool, Error?)` tuples. Map errors via `mapError(_:)` to `LockAuthError` enum cases. No try/catch in LockController beyond what's inside `SystemBiometricAuth.evaluate`.

---

## No Analog Found

All files have close analogs in the codebase. No novel patterns required.

| File | Reason |
|------|--------|
| (none) | All patterns are grounded in existing code |

The one net-new API surface is `import LocalAuthentication` — but the wrapper pattern (`BiometricAuthPort`) is identical to `NotificationCenterPort`, so the seam design is fully grounded.

---

## Metadata

**Analog search scope:** `MyHomeApp/`, `MyHomeTests/`
**Files read:** `NotificationCenterPort.swift`, `SpyCenter.swift`, `RootView.swift`, `OverviewView.swift` (lines 1–40), `ManageCategoriesView.swift`, `BudgetsView.swift` (lines 1–60), `ModelContainer+App.swift`, `MyHomeApp.swift`, `EditNoteView.swift` (lines 1–50), `NotificationSchedulerTests.swift` (lines 1–60)
**Pattern extraction date:** 2026-06-02
