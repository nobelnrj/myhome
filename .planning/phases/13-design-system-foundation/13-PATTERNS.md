# Phase 13: Design System Foundation — Pattern Map

**Mapped:** 2026-06-21
**Files analyzed:** 6 (4 production + 2 test)
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MyHomeApp/DesignSystem/DesignTokens.swift` | token-constants (caseless enum) | compile-time constants | `MyHomeApp/Support/Color+Hex.swift` + `MyHomeApp/Features/Shared/CardStyle.swift` | role-match (no pure-token file exists; Color+Hex shows hex-to-Color; CardStyle shows the shadow constant it replaces) |
| `MyHomeApp/DesignSystem/NeuSurface.swift` | view-modifier | request-response (synchronous SwiftUI render) | `MyHomeApp/Features/Shared/CardStyle.swift` | exact — same ViewModifier + View extension pattern |
| `MyHomeApp/DesignSystem/NeuTabBar.swift` | container-view | event-driven (tab selection binding + notification deep-links) | `MyHomeApp/RootView.swift` | exact — owns the `$selectedTab` binding, contains the `TabView` + deep-link observers |
| `MyHomeApp/DesignSystem/RollingMoneyText.swift` | animated-component | transform (Decimal → formatted String → animated Text) | `MyHomeApp/Features/Shared/CardStyle.swift` (structural), `MyHomeApp/MyHomeApp.swift` (@Environment pattern) | partial-match — no animated text component yet; @Environment usage from MyHomeApp.swift |
| `MyHomeTests/DesignTokensTests.swift` | test | CRUD (assert token value equality) | `MyHomeTests/AccountBalanceTests.swift` | exact — same Swift Testing struct pattern |
| `MyHomeTests/RollingMoneyTextTests.swift` | test | transform-assert | `MyHomeTests/AccountBalanceTests.swift` | exact |
| `MyHomeApp/MyHomeApp.swift` (modify — add `.preferredColorScheme(.dark)`) | app-entry-point | request-response | `MyHomeApp/MyHomeApp.swift` (itself) | self-analog |
| `MyHomeApp/RootView.swift` (modify — add `.toolbar(.hidden, for: .tabBar)` + `NeuTabBar` overlay) | container-view | event-driven | `MyHomeApp/RootView.swift` (itself) | self-analog |

---

## Pattern Assignments

### `MyHomeApp/DesignSystem/DesignTokens.swift` (token-constants, DS-01)

**Analog 1:** `MyHomeApp/Support/Color+Hex.swift` — shows exact `Color(hex:)` call syntax

**Analog 2:** `MyHomeApp/Features/Shared/CardStyle.swift` — shows the single-shadow constant this file supersedes

**Imports pattern** (copy from `Color+Hex.swift` line 1):
```swift
import SwiftUI
```
No other imports needed — `DesignTokens` is a pure compile-time constant file.

**Color constant pattern** (from `Color+Hex.swift` lines 8-19 — the extension `DesignTokens` will call):
```swift
// Color+Hex.swift already handles:
// - "#" prefix stripping
// - 6-digit hex parsing → Double r/g/b / 255.0
// - .gray fallback on malformed input
// DesignTokens.swift calls it directly:
static let bgCanvas = Color(hex: "#1C1C23")
static let accent   = Color(hex: "#FFD60A")
// Opacity variants:
static let accentSoft = Color(hex: "#FFD60A").opacity(0.16)
// Non-hex (white/black with opacity):
static let separatorHairline = Color.white.opacity(0.05)
static let glassBorder       = Color.white.opacity(0.025)
```

**Nested struct pattern** (ShadowSpec — value type, not class):
```swift
// No analog exists in codebase. Structure from UI-SPEC:
struct ShadowSpec {
    let lightColor: Color; let lightRadius: CGFloat; let lightX: CGFloat; let lightY: CGFloat
    let darkColor: Color;  let darkRadius: CGFloat;  let darkX: CGFloat;  let darkY: CGFloat
}
static let shadowRaised = ShadowSpec(
    lightColor: .white.opacity(0.035), lightRadius: 7,  lightX: -6, lightY: -6,
    darkColor:  .black.opacity(0.55),  darkRadius:  9,  darkX:   7, darkY:   7
)
static let shadowFloat = ShadowSpec(
    lightColor: .white.opacity(0.04),  lightRadius: 11, lightX: -9, lightY: -9,
    darkColor:  .black.opacity(0.62),  darkRadius:  14, darkX:  11, darkY:  11
)
```

**Animation constant pattern** (no analog — new in Phase 13):
```swift
// Static Animation values — avoids repeating .spring(...) inline:
static let springBouncy: Animation = .spring(response: 0.4, dampingFraction: 0.65)
static let springSoft:   Animation = .spring(response: 0.4, dampingFraction: 0.90)
```

**CRITICAL — font tokens:** `@ScaledMetric` cannot be `static let` in an enum (Swift compiler error:
"property wrappers are not allowed on static stored properties"). Group B font base values are
documented as comments in `DesignTokens.swift` but the `@ScaledMetric` declarations live in each
component file that uses them (`RollingMoneyText.swift`, etc.).

**File header convention** (copy from `CardStyle.swift` line 1 style, adapted):
```swift
// DesignTokens.swift
// Single source of truth for all neumorphic visual tokens.
// Translated from design/design_handoff_myhome_neumorphic/src/tokens.jsx (neuro branch).
// Phase 13: DS-01

import SwiftUI

enum DesignTokens {
    // ...
}
```

---

### `MyHomeApp/DesignSystem/NeuSurface.swift` (view-modifier, DS-02)

**Analog:** `MyHomeApp/Features/Shared/CardStyle.swift` (lines 1–31) — exact structural match

**Full analog** (`CardStyle.swift` lines 1–31):
```swift
import SwiftUI

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat? = 16

    func body(content: Content) -> some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 16, padding: CGFloat? = 16) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
```

**NeuSurface replaces this with:**

1. `CardStyle` struct → `NeuSurface` struct (same `ViewModifier` conformance)
2. `padding` parameter: same optional `CGFloat?` pattern — copy `Group { if let padding { … } else { … } }` verbatim
3. `.frame(maxWidth: .infinity, alignment: .leading)` — copy verbatim
4. `.background(Color(.secondarySystemBackground))` → `.background(fill)` where `fill` is a computed `var` switching on `NeuSurfaceState`
5. `.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))` — copy verbatim, change default `cornerRadius` from 16 to `DesignTokens.radiusCard`
6. Single `.shadow(...)` → dual `.shadow()` from `DesignTokens.shadowRaised` / `.shadowFloat`
7. Add `.overlay { rimOverlay }` for raised/floating states
8. Add `NeuSurfaceState` enum (new — no analog)
9. Deprecate `CardStyle` in the same file or in `CardStyle.swift`:
   ```swift
   @available(*, deprecated, renamed: "neuSurface")
   ```

**Dual shadow application order** (light first, dark second — RESEARCH Pitfall 2):
```swift
// In NeuSurface.body, after .clipShape:
.shadow(color: spec.lightColor, radius: spec.lightRadius, x: spec.lightX, y: spec.lightY)
.shadow(color: spec.darkColor,  radius: spec.darkRadius,  x: spec.darkX,  y: spec.darkY)
```

**Rim overlay pattern** (no analog — derived from UI-SPEC):
```swift
.overlay {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(0.045), Color.black.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
}
```

**View extension pattern** (copy structure from `CardStyle.swift` lines 26–30):
```swift
extension View {
    func neuSurface(
        _ state: NeuSurfaceState,
        radius: CGFloat = DesignTokens.radiusCard,
        padding: CGFloat? = 16
    ) -> some View {
        modifier(NeuSurface(state: state, radius: radius, padding: padding))
    }
}
```

---

### `MyHomeApp/DesignSystem/NeuTabBar.swift` (container-view, DS-03)

**Analog:** `MyHomeApp/RootView.swift` — provides the `@State selectedTab: Int` pattern,
deep-link notification observers, and the existing `TabView` structure that `NeuTabBar` integrates with.

**selectedTab binding pattern** (`RootView.swift` lines 34, 66):
```swift
// RootView owns this; NeuTabBar receives it as Binding<Int>:
@State private var selectedTab: Int = 0

// NeuTabBar is passed it as:
NeuTabBar(selectedTab: $selectedTab)
```

**Tab index stability** (`RootView.swift` lines 66–97 — current tag mapping to preserve):
```swift
// Tag assignments that deep-links depend on:
OverviewView(...)    .tag(0)   // home
ExpenseListView(...) .tag(1)   // expenses
BudgetsView()        .tag(2)   // budgets
NotesHomeView(...)   .tag(3)   // notes — kOpenNoteNotification sets selectedTab = 3
SettingsView(...)    .tag(4)   // settings
```

**Deep-link observer pattern** (`RootView.swift` lines 115–129 — must keep working after NeuTabBar is added):
```swift
.onReceive(NotificationCenter.default.publisher(for: kOpenNoteNotification)) { notification in
    if let noteID = notification.userInfo?["noteID"] as? UUID {
        deepLinkNoteID = noteID
        deepLinkBlockID = notification.userInfo?["blockID"] as? UUID
        selectedTab = 3   // NeuTabBar reads $selectedTab — this still works
    }
}
```

**RootView integration pattern** (how NeuTabBar is added to `RootView.swift`):
```swift
// In RootView.body — replace the existing TabView block with:
TabView(selection: $selectedTab) {
    OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
        .tabItem { Label("Home", systemImage: "house") }   // keep — TabView needs .tabItem
        .tag(0)
    // … other tabs unchanged …
}
.toolbar(.hidden, for: .tabBar)   // DS-03: suppress native chrome
.overlay(alignment: .bottom) {
    NeuTabBar(selectedTab: $selectedTab)
}
```

**NeuTabBar internal structure** (no analog — new component; key patterns from UI-SPEC):
```swift
struct NeuTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    // Tab model sourced from UI-SPEC DS-03 tab definitions:
    private let tabs: [(id: Int, label: String, icon: String, activeIcon: String)] = [
        (0, "Home",     "house",       "house.fill"),
        (1, "Activity", "creditcard",  "creditcard.fill"),
        (2, "Budgets",  "chart.pie",   "chart.pie.fill"),
        (3, "Notes",    "note.text",   "note.text"),
        (4, "Settings", "gear",        "gear"),
    ]

    var body: some View {
        // Floating capsule — use GeometryReader in overlay to read safeAreaInsets.bottom
        // ...
    }
}
```

**Active pill animation** (matchedGeometryEffect — no analog, from UI-SPEC / RESEARCH Pattern 3):
```swift
@Namespace private var pillNamespace

// Inside HStack of tab buttons:
if selectedTab == index {
    RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(DesignTokens.accentSoft)
        .matchedGeometryEffect(id: "activePill", in: pillNamespace)
        .animation(reduceMotion ? nil : DesignTokens.springBouncy, value: selectedTab)
}
```

**Safe area bottom inset** (use GeometryReader in overlay — RESEARCH Pitfall 5):
```swift
// NeuTabBar positions itself using GeometryReader or passes safeAreaInsets down:
.padding(.bottom, max(DesignTokens.tabBarBottomOffset,
                      geometry.safeAreaInsets.bottom + 8))
```

---

### `MyHomeApp/DesignSystem/RollingMoneyText.swift` (animated-component, DS-04)

**Analog:** No direct animated-text analog exists. Structural patterns drawn from:
- `MyHomeApp/Features/Shared/CardStyle.swift` — `View` struct + `import SwiftUI` header
- `MyHomeApp/RootView.swift` lines 31–32 — `@Environment` property usage pattern
- `MyHomeApp/MyHomeApp.swift` lines 27–28 — `@State` + `@Environment` in app context

**@Environment usage pattern** (`RootView.swift` lines 31–32):
```swift
@Environment(\.scenePhase) private var scenePhase
@Environment(\.modelContext) private var modelContext
// New in RollingMoneyText:
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

**@ScaledMetric usage pattern** (no analog in codebase — new pattern for Phase 13):
```swift
// Declared as instance property (NOT static) inside the View struct:
@ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46
// For stat variant: @ScaledMetric(relativeTo: .title2) private var statSize: CGFloat = 21
```

**Full RollingMoneyText implementation skeleton** (from RESEARCH Pattern 4 / UI-SPEC DS-04):
```swift
import SwiftUI

struct RollingMoneyText: View {
    let amount: Decimal
    var currencyCode: String = "INR"
    var locale: Locale = Locale(identifier: "en_IN")
    var animationDuration: Double = 0.78

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46

    private var formatted: String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: baseSize, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth(duration: animationDuration), value: amount)
            .accessibilityLabel("₹\(formatted)")
    }
}
```

**contentTransition + animation pairing** — these MUST appear together; omitting `.animation` makes
the transition silent (RESEARCH Pitfall 6):
```swift
// Always paired:
.contentTransition(reduceMotion ? .identity : .numericText())
.animation(reduceMotion ? nil : .smooth(duration: 0.78), value: amount)
```

---

### `MyHomeTests/DesignTokensTests.swift` (test, DS-01)

**Analog:** `MyHomeTests/AccountBalanceTests.swift` (lines 1–15) — exact Swift Testing struct pattern

**Full test file header pattern** (`AccountBalanceTests.swift` lines 1–10):
```swift
import Testing
import Foundation
@testable import MyHome

@MainActor
struct DesignTokensTests {

    @Test("DesignTokens.accent equals #FFD60A")
    func accentColorMatchesSpec() throws {
        // Use Color+Hex to round-trip: hex → Color → hexString → compare
        #expect(DesignTokens.accent.hexString.uppercased() == "#FFD60A")
    }

    @Test("DesignTokens.shadowRaised light x=-6, dark x=7")
    func shadowRaisedSpec() throws {
        #expect(DesignTokens.shadowRaised.lightX == -6)
        #expect(DesignTokens.shadowRaised.darkX  == 7)
    }

    @Test("DesignTokens.radiusCard equals 26")
    func radiusCard() throws {
        #expect(DesignTokens.radiusCard == 26)
    }

    @Test("DesignTokens.tabBarClearance equals 100")
    func tabBarClearance() throws {
        #expect(DesignTokens.tabBarClearance == 100)
    }
}
```

Note: `SwiftData` import is NOT needed here (no model operations). `import Testing` + `import Foundation` only.

---

### `MyHomeTests/RollingMoneyTextTests.swift` (test, DS-04)

**Analog:** `MyHomeTests/AccountBalanceTests.swift` — same struct pattern

**Test file pattern** (copy header from `AccountBalanceTests.swift` lines 1–10, adapt):
```swift
import Testing
import Foundation
@testable import MyHome

@MainActor
struct RollingMoneyTextTests {

    @Test("INR formatting: Decimal(123456) formats with lakh grouping")
    func inrLakhFormatting() throws {
        let amount = Decimal(123456)
        let formatted = amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
        // Lakh grouping: ₹1,23,456.00
        #expect(formatted.contains("1,23,456"))
    }

    // Note: reduceMotion behavior is an @Environment concern — cannot be unit-tested
    // without a hosting view. The DS-06 gate is: manual preview test in Xcode Simulator
    // with Accessibility > Reduce Motion ON. Document this as a manual gate.
}
```

---

### `MyHomeApp/MyHomeApp.swift` (modify — add DS-05)

**Self-analog** — read from `MyHomeApp/MyHomeApp.swift` lines 32–34.

**Current WindowGroup body** (lines 32–35):
```swift
WindowGroup {
    RootView(gmailSyncController: gmailSyncController)
        .onAppear {
            setupNotifications()
        }
}
```

**Modification — add `.preferredColorScheme(.dark)` between `RootView(...)` and `.onAppear`**:
```swift
WindowGroup {
    RootView(gmailSyncController: gmailSyncController)
        .preferredColorScheme(.dark)   // DS-05: neumorphic dark-mode-only; applied once at root
        .onAppear {
            setupNotifications()
        }
}
```

No other changes to `MyHomeApp.swift` in Phase 13.

---

### `MyHomeApp/RootView.swift` (modify — DS-03 TabView chrome replacement)

**Self-analog** — read from `MyHomeApp/RootView.swift` lines 65–97.

**Minimal surgical changes required:**

1. After the closing `}` of the `TabView` block (line 97), add:
   ```swift
   .toolbar(.hidden, for: .tabBar)
   ```

2. After `.toolbar(.hidden, for: .tabBar)`, add the NeuTabBar overlay:
   ```swift
   .overlay(alignment: .bottom) {
       NeuTabBar(selectedTab: $selectedTab)
   }
   ```

All existing `.tabItem { }` modifiers, `.tag()` values, `.badge()`, `.onReceive`, `.overlay` (UnlockView), `.blur`, `.onChange`, `.environment`, and deep-link state remain untouched. The NeuTabBar overlay is appended after the existing modifier chain — it does not restructure it.

---

## Shared Patterns

### SwiftUI `import` header
**Source:** `MyHomeApp/Features/Shared/CardStyle.swift` line 1, `MyHomeApp/Support/Color+Hex.swift` line 1
**Apply to:** All 4 new DesignSystem files
```swift
import SwiftUI
```

### `Color(hex:)` usage
**Source:** `MyHomeApp/Support/Color+Hex.swift` (entire file, 37 lines — no changes needed; reused as-is)
**Apply to:** `DesignTokens.swift` — every color constant uses `Color(hex: "#RRGGBB")`
```swift
// Extension already handles: "#" stripping, 6-digit parse, .gray fallback
// Usage in DesignTokens.swift:
static let accent = Color(hex: "#FFD60A")
```

### Optional-padding `Group` block
**Source:** `MyHomeApp/Features/Shared/CardStyle.swift` lines 12–17
**Apply to:** `NeuSurface.swift`
```swift
Group {
    if let padding {
        content.padding(padding)
    } else {
        content
    }
}
```

### `@Environment(\.accessibilityReduceMotion)`
**Source:** No existing analog in codebase. `RootView.swift` shows `@Environment(\.scenePhase)` (line 31) as the structural pattern.
**Apply to:** `NeuTabBar.swift`, `RollingMoneyText.swift`
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

### Swift Testing struct structure
**Source:** `MyHomeTests/AccountBalanceTests.swift` lines 1–10
**Apply to:** `DesignTokensTests.swift`, `RollingMoneyTextTests.swift`
```swift
import Testing
import Foundation
@testable import MyHome

@MainActor
struct <Name>Tests {
    @Test("<description>")
    func <testName>() throws {
        #expect(…)
    }
}
```

---

## pbxproj Registration Pattern (4 edits per file)

**Source:** `MyHome.xcodeproj/project.pbxproj` — verified against `CardStyle.swift` and `Color+Hex.swift` registrations

**ID convention in this project:**
- Build file IDs: prefix `A`, then phase+mnemonic (e.g., `A803SH` for CardStyle phase 8)
- File reference IDs: prefix `F`, same suffix (e.g., `F803SH`)
- Group IDs: prefix `G`, numeric (e.g., `G100`, `G140`)

**Recommended IDs for Phase 13 DesignSystem files:**

| File | Build File ID | FileRef ID |
|------|---------------|------------|
| `DesignTokens.swift` | `A13DS1` | `F13DS1` |
| `NeuSurface.swift` | `A13NS` | `F13NS` |
| `NeuTabBar.swift` | `A13NTB` | `F13NTB` |
| `RollingMoneyText.swift` | `A13RMT` | `F13RMT` |
| `DesignTokensTests.swift` | `A13DST` | `F13DST` |
| `RollingMoneyTextTests.swift` | `A13RMTT` | `F13RMTT` |

### Edit 1 — PBXBuildFile section (line ~84 area)

Copy pattern from line 84:
```
A803SH /* CardStyle.swift in Sources */ = {isa = PBXBuildFile; fileRef = F803SH /* CardStyle.swift */; };
```
Add for each new file:
```
A13DS1 /* DesignTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13DS1 /* DesignTokens.swift */; };
A13NS /* NeuSurface.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13NS /* NeuSurface.swift */; };
A13NTB /* NeuTabBar.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13NTB /* NeuTabBar.swift */; };
A13RMT /* RollingMoneyText.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13RMT /* RollingMoneyText.swift */; };
A13DST /* DesignTokensTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13DST /* DesignTokensTests.swift */; };
A13RMTT /* RollingMoneyTextTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13RMTT /* RollingMoneyTextTests.swift */; };
```

### Edit 2 — PBXFileReference section (line ~375 area)

Copy pattern from line 375:
```
F803SH /* CardStyle.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CardStyle.swift; sourceTree = "<group>"; };
```
Add for each new production file:
```
F13DS1 /* DesignTokens.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DesignTokens.swift; sourceTree = "<group>"; };
F13NS /* NeuSurface.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NeuSurface.swift; sourceTree = "<group>"; };
F13NTB /* NeuTabBar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NeuTabBar.swift; sourceTree = "<group>"; };
F13RMT /* RollingMoneyText.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RollingMoneyText.swift; sourceTree = "<group>"; };
```
Add for test files (in PBXFileReference section, same format):
```
F13DST /* DesignTokensTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DesignTokensTests.swift; sourceTree = "<group>"; };
F13RMTT /* RollingMoneyTextTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RollingMoneyTextTests.swift; sourceTree = "<group>"; };
```

### Edit 3 — PBXGroup section (line ~432 area)

**Step 3a — Add new group `G_DS` for the DesignSystem/ directory:**
```
G_DS /* DesignSystem */ = {
    isa = PBXGroup;
    children = (
        F13DS1 /* DesignTokens.swift */,
        F13NS /* NeuSurface.swift */,
        F13NTB /* NeuTabBar.swift */,
        F13RMT /* RollingMoneyText.swift */,
    );
    path = DesignSystem;
    sourceTree = "<group>";
};
```

**Step 3b — Add `G_DS` reference to `G100 /* MyHomeApp */` children list** (line ~434–445):

Current `G100` children (lines 434–444):
```
G100 /* MyHomeApp */ = {
    isa = PBXGroup;
    children = (
        F101 /* MyHomeApp.swift */,
        F102 /* RootView.swift */,
        F106 /* MyHome.entitlements */,
        F105 /* Info.plist */,
        G110 /* Resources */,
        G120 /* Features */,
        G130 /* Persistence */,
        G140 /* Support */,
        G150 /* Security */,
        G160 /* Gmail */,
    );
```
Insert `G_DS /* DesignSystem */,` as the FIRST child (before `F101`) or after `F106`/`F105` to keep
files before groups. Recommended position: after `F105 /* Info.plist */,`:
```
        F105 /* Info.plist */,
        G_DS /* DesignSystem */,    ← INSERT HERE
        G110 /* Resources */,
```

**Step 3c — Add test files to `G200 /* MyHomeTests */` children list:**

Find the `G200` group (mirrors `G100` for tests) and add:
```
F13DST /* DesignTokensTests.swift */,
F13RMTT /* RollingMoneyTextTests.swift */,
```

### Edit 4 — PBXSourcesBuildPhase section

**Production files → `P001 /* Sources */`** (line ~957 area, alongside existing A803SH):
```
A13DS1 /* DesignTokens.swift in Sources */,
A13NS /* NeuSurface.swift in Sources */,
A13NTB /* NeuTabBar.swift in Sources */,
A13RMT /* RollingMoneyText.swift in Sources */,
```

**Test files → `P003 /* Sources */`** (line ~1069 area, alongside existing A904ABT):
```
A13DST /* DesignTokensTests.swift in Sources */,
A13RMTT /* RollingMoneyTextTests.swift in Sources */,
```

**Prerequisite:** The `MyHomeApp/DesignSystem/` directory MUST be created on disk BEFORE these pbxproj
edits are made. Xcode does not create filesystem directories from group references.

---

## No Analog Found

| File aspect | Reason |
|-------------|---------|
| Inset (recessed) shadow implementation | SwiftUI has no `.shadow(inset:)`. Two approaches exist; the overlay-gradient path is recommended (RESEARCH Pattern 2 / Open Question 1). No existing codebase code to copy from — implement from scratch per UI-SPEC spec. |
| `NeuSurfaceState` enum | No state-switching enum exists in current ViewModifiers. New pattern — three cases: `.raised`, `.floating`, `.recessed`. |
| `@ScaledMetric(relativeTo:)` usage | No existing use in the codebase. New in Phase 13. Must be instance property in each consumer view — not static in DesignTokens. |
| `matchedGeometryEffect` for pill slide | No existing animation uses `@Namespace` / `matchedGeometryEffect`. New pattern for tab pill. |
| `.contentTransition(.numericText())` | No animated text component in codebase. Pure first-party iOS 16+ API — no analog to copy. |
| `.toolbar(.hidden, for: .tabBar)` on `TabView` | Not used anywhere in codebase currently. New modifier for DS-03. |

---

## Metadata

**Analog search scope:** `MyHomeApp/`, `MyHomeTests/`, `MyHome.xcodeproj/`
**Files read:** 7 source files + 1 test file + pbxproj (targeted sections)
**Pattern extraction date:** 2026-06-21
