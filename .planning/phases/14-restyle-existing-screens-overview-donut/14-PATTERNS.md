# Phase 14: Restyle Existing Screens + Overview Donut — Pattern Map

**Mapped:** 2026-06-21
**Files analyzed:** 40 (1 new + 37 modified + 2 deleted)
**Analogs found:** 40 / 40

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Features/Overview/SpendDonutCard.swift` (NEW) | component | request-response | `Features/Assets/NetWorthCard.swift` + `Features/Overview/OverviewView.swift:WhereItsGoingCard` | exact — same DonutChart + HStack legend + tap-to-navigate pattern |
| `Features/Shared/CategoryStyle.swift` | utility | transform | self (rewrite in place) | self-analog |
| `Features/Shared/CardStyle.swift` | utility | — | DELETE | — |
| `DesignSystem/NeuTabBar.swift` | component | — | DELETE | — |
| `RootView.swift` | provider | event-driven | `RootView.swift` (self) | self |
| `Features/Overview/OverviewView.swift` | screen | request-response | `Features/Assets/NetWorthCard.swift` (DonutChart caller) | role-match |
| `Features/Overview/SpendBudgetCard.swift` | component | request-response | `Features/Overview/SpendBudgetCard.swift` (self — layout rewrite) | self |
| `Features/Overview/PinnedNoteCard.swift` | component | request-response | `Features/Overview/PinnedNoteCard.swift` (self) | self |
| `Features/Overview/SpendByCategoryChart.swift` | component | request-response | self | self |
| `Features/Overview/SpendOverTimeChart.swift` | component | request-response | self | self |
| `Features/Overview/TopCategoriesCard.swift` | component | request-response | self | self |
| `Features/Expenses/ExpenseListView.swift` | screen | CRUD | self | self |
| `Features/Expenses/ExpenseRow.swift` | component | request-response | `Features/Overview/OverviewView.swift:RecentExpenseRow` | role-match |
| `Features/Expenses/ReviewInboxRow.swift` | component | request-response | `Features/Expenses/ExpenseRow.swift` | role-match |
| `Features/Expenses/AddExpenseView.swift` | screen | CRUD | self | self |
| `Features/Expenses/EditExpenseView.swift` | screen | CRUD | self | self |
| `Features/Expenses/DecimalKeypadView.swift` | component | request-response | self | self |
| `Features/Expenses/AccountPickerView.swift` | component | request-response | self | self |
| `Features/Expenses/CategoryPickerView.swift` | component | request-response | self | self |
| `Features/Expenses/TransferPairRow.swift` | component | request-response | `Features/Expenses/ExpenseRow.swift` | role-match |
| `Features/Budgets/BudgetsView.swift` | screen | CRUD | self | self |
| `Features/Budgets/BudgetCategoryCard.swift` | component | request-response | `Features/Assets/NetWorthCard.swift:legendRow` | role-match |
| `Features/Budgets/BudgetProgressView.swift` | component | request-response | self | self |
| `Features/Budgets/EditBudgetSheet.swift` | screen | CRUD | self | self |
| `Features/Budgets/ManageCategoriesView.swift` | screen | CRUD | self | self |
| `Features/Budgets/FilteredExpenseListView.swift` | screen | CRUD | `Features/Expenses/ExpenseListView.swift` | role-match |
| `Features/Notes/NotesHomeView.swift` | screen | request-response | self | self |
| `Features/Notes/NotesListView.swift` | screen | CRUD | self | self |
| `Features/Notes/NoteRow.swift` | component | request-response | `Features/Expenses/ExpenseRow.swift` | role-match |
| `Features/Notes/AddNoteView.swift` | screen | CRUD | self | self |
| `Features/Notes/EditNoteView.swift` | screen | CRUD | self | self |
| `Features/Notes/CalendarView.swift` | screen | request-response | self | self |
| `Features/Notes/ReminderEditView.swift` | screen | CRUD | self | self |
| `Features/Notes/RoutineDetailView.swift` | screen | CRUD | self | self |
| `Features/Settings/SettingsView.swift` | screen | CRUD | self | self |
| `Features/Settings/UnlockView.swift` | screen | request-response | self | self |
| `Features/Settings/MigrationReviewSheet.swift` | screen | CRUD | self | self |
| `Features/Settings/AccountsListView.swift` | screen | CRUD | self | self |
| `Features/Settings/AccountDetailView.swift` | screen | CRUD | self | self |
| `Features/Settings/EditAccountView.swift` | screen | CRUD | self | self |
| `Features/Assets/NetWorthCard.swift` | component | request-response | self | self |
| `Features/Assets/AssetsListView.swift` | screen | CRUD | self | self |
| `Features/Assets/AssetDetailView.swift` | screen | CRUD | self | self |
| `Features/Assets/EditAssetView.swift` | screen | CRUD | self | self |
| `Features/Assets/NetWorthTrendChart.swift` | component | request-response | self | self |
| `Features/Assets/StalenessView.swift` | component | request-response | self | self |
| `Features/Assets/AMFISchemePickerView.swift` | screen | request-response | self | self |
| `Features/Assets/NPSSchemePickerView.swift` | screen | request-response | self | self |
| `Features/Assets/ReconcileView.swift` | screen | CRUD | self | self |
| `Features/Assets/SIPSetupView.swift` | screen | CRUD | self | self |
| `Features/Assets/ContributionLogView.swift` | screen | request-response | self | self |
| `Features/Shared/StackBar.swift` | component | transform | self | self |

---

## Pattern Assignments

### `Features/Overview/SpendDonutCard.swift` (NEW — component, request-response)

**Primary analogs:**
1. `Features/Assets/NetWorthCard.swift` — DonutChart caller with HStack legend, same `cardStyle` → `.neuSurface` target structure, `NSDecimalNumber` conversion pattern
2. `Features/Overview/OverviewView.swift` lines 301–351 (`WhereItsGoingCard` struct) — existing donut + legend structure being extracted into this new file

**Imports pattern** (copy from `NetWorthCard.swift` lines 1–3):
```swift
import SwiftUI
import Charts
import SwiftData
```

**File-level struct signature** (modeled on `WhereItsGoingCard` extracted to top-level):
```swift
struct SpendDonutCard: View {
    let ranked: [(category: Category, spent: Decimal)]  // top-4 only (caller trims)
    let total: Decimal
    let onCategoryTap: (UUID?) -> Void   // nil = "Others" segment
}
```
Data is pre-computed by `OverviewMonthContent.body` (lines 136–141 of `OverviewView.swift`). The existing `rankedSpend` variable already excludes confirmed self-transfers via `BudgetCalculator.monthlySpend`. Pass it directly; do NOT add a new `@Query` inside `SpendDonutCard`.

**Core pattern — DonutChart call with center closure** (from `NetWorthCard.swift` lines 51–54 AND `WhereItsGoingCard` lines 306–328):
```swift
// In SpendDonutCard.body — analogous to NetWorthCard.cardContent()
HStack(spacing: 18) {
    DonutChart(segments: segments, size: 132) {
        VStack(spacing: 2) {
            Text("SPENT")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DesignTokens.label2)
            // NOT RollingMoneyText — 21pt stat pattern (see Shared Patterns)
            Text(total.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
                .font(.system(size: 21, weight: .light, design: .rounded))
                .foregroundStyle(DesignTokens.label)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.78), value: total)
        }
    }

    VStack(alignment: .leading, spacing: 11) {
        ForEach(legendItems) { item in
            Button { onCategoryTap(item.categoryID) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.color)
                        .frame(width: 9, height: 9)
                        .shadow(color: item.color.opacity(0.6), radius: 5)
                    Text(item.label)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.label)
                    Spacer()
                    Text(item.amount.formattedINRWhole())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.label2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.label): \(item.amount.formattedINRWhole())")
        }
    }
}
.neuSurface(.raised, padding: 18)
// Do NOT add .clipped() here — shadow must remain visible (Pitfall 2)
```

**Segment preparation** (copy `NSDecimalNumber` conversion from `NetWorthCard.swift` lines 130–132):
```swift
// Safe Decimal → Double (T-11-13 pattern from NetWorthCard)
private func toDouble(_ v: Decimal) -> Double {
    NSDecimalNumber(decimal: max(v, .zero)).doubleValue
}

// Segment color — CategoryStyle.color(for:) after CategoryStyle rewrite
private var segments: [DonutSegment] {
    var result: [DonutSegment] = ranked.prefix(4).map { item in
        DonutSegment(
            id: item.category.id.uuidString,
            label: item.category.name ?? "—",
            value: toDouble(item.spent),
            color: CategoryStyle.color(for: item.category)   // returns DesignTokens.cat* after rewrite
        )
    }
    // "Others" roll-up
    if ranked.count > 4 {
        let othersTotal = ranked.dropFirst(4).reduce(Decimal.zero) { $0 + $1.spent }
        if othersTotal > .zero {
            result.append(DonutSegment(id: "others", label: "Others",
                                       value: toDouble(othersTotal),
                                       color: DesignTokens.catOther))
        }
    }
    return result
}
```

**Empty state** (zero spend month):
```swift
// When ranked.isEmpty, show inside the .neuSurface(.raised) card
VStack(spacing: DesignTokens.spacing8) {
    Image(systemName: "circle.dashed")
        .font(.system(size: 40))
        .foregroundStyle(DesignTokens.label3)
    Text("No spend this month")
        .font(.system(size: 14))
        .foregroundStyle(DesignTokens.label2)
}
.frame(maxWidth: .infinity)
.neuSurface(.raised, padding: 18)
```

**OVR-06 tap navigation** — the `onCategoryTap` closure is set by `OverviewMonthContent`. The caller:
1. Writes the UUID into a new `@State private var activityCategoryFilter: UUID? = nil` in `RootView`
2. Passes the UUID as a `Binding<UUID?>` to `ExpenseListView`
3. Sets `selectedTab = 1`

Pattern to copy from `RootView.swift` lines 35–36 (existing deep-link state) and lines 110–116 (deep-link observer):
```swift
// In RootView — add alongside existing deepLinkNoteID (line 35):
@State private var activityCategoryFilter: UUID? = nil

// Pass to ExpenseListView (line 72) — add new binding param:
ExpenseListView(reviewBadgeCount: $reviewBadgeCount, categoryFilter: $activityCategoryFilter)

// In OverviewView / SpendDonutCard caller — write the UUID then switch tab:
onCategoryTap: { uuid in
    activityCategoryFilter = uuid
    selectedTab = 1
}
```

---

### `Features/Shared/CategoryStyle.swift` (utility, transform — FULL REWRITE)

**Analog:** self (rewrite the same file in place; no pbxproj edit needed)

**Current pattern to REPLACE** (lines 14–38, `CategoryStyle.swift`):
```swift
// BEFORE — stock system colors
private static let palette: [Color] = [
    Color(.systemGreen), Color(.systemOrange), ...
]
private static let bySymbol: [String: Color] = [
    "cart": Color(.systemGreen),
    "fork.knife": Color(.systemOrange),
    ...
]
```

**New pattern** (swap every stock color for its `DesignTokens.cat*` counterpart):
```swift
// AFTER — neumorphic category palette
private static let palette: [Color] = [
    DesignTokens.catGroceries, DesignTokens.catDining, DesignTokens.catFuel,
    DesignTokens.catUtilities, DesignTokens.catRent, DesignTokens.catAuto,
    DesignTokens.catShopping, DesignTokens.catHealth, DesignTokens.catSubscriptions,
    DesignTokens.catEntertainment, DesignTokens.catOther,
]

private static let bySymbol: [String: Color] = [
    "cart":                               DesignTokens.catGroceries,
    "fork.knife":                         DesignTokens.catDining,
    "fuelpump":                           DesignTokens.catFuel,
    "bolt":                               DesignTokens.catUtilities,
    "house":                              DesignTokens.catRent,
    "house.fill":                         DesignTokens.catRent,
    "car":                                DesignTokens.catAuto,
    "bag":                                DesignTokens.catShopping,
    "cross.case":                         DesignTokens.catHealth,
    "film":                               DesignTokens.catEntertainment,
    "antenna.radiowaves.left.and.right":  DesignTokens.catSubscriptions,
    "person.2":                           DesignTokens.catOther,
    "arrow.up.right":                     DesignTokens.catOther,
    "banknote":                           DesignTokens.catGroceries,
    "tray":                               DesignTokens.catOther,
]

// Fallback for nil category and unknown symbols — was Color(.systemGray):
static func color(for category: Category?) -> Color {
    guard let category else { return DesignTokens.catOther }
    if let symbol = category.symbolName, let mapped = bySymbol[symbol] { return mapped }
    let key = category.name ?? category.symbolName ?? "?"
    let idx = abs(stableHash(key)) % palette.count
    return palette[idx]   // always a DesignTokens.cat* color now
}
```

The `stableHash` function (FNV-1a, lines 57–60) is unchanged. The `symbol(for:)` accessor is unchanged.

---

### `RootView.swift` (provider, event-driven — minimal edit)

**Analog:** self (single `.tint` modifier addition)

**The only required change** (after line 92 `}` that closes the `.tag(4)` block):
```swift
// Source: RootView.swift line 92 — add .tint modifier on TabView
TabView(selection: $selectedTab) { ... }
    .tint(DesignTokens.accent)    // replaces stock blue; canary yellow #FFD60A
```

**OVR-06 addition** — new state property alongside `deepLinkNoteID` (line 35):
```swift
@State private var activityCategoryFilter: UUID? = nil
```
Pass as `Binding<UUID?>` into `ExpenseListView`. The binding mirrors the existing `deepLinkNoteID: $deepLinkNoteID` parameter pattern.

---

### `Features/Overview/OverviewView.swift` (screen restyle — structural + cardStyle migration)

**Analog:** self (restyle pass) + `NeuSurface.swift` preview (lines 206–246) for `.neuSurface` call pattern

**cardStyle → neuSurface migration** (4 sites verified):

| Line | Old | New |
|------|-----|-----|
| 209 | `.cardStyle(cornerRadius: 16, padding: 16)` | `.neuSurface(.raised)` |
| 228 | `.cardStyle(cornerRadius: 16, padding: nil)` | `.neuSurface(.raised, padding: nil)` |
| 293 (ReviewBanner) | `.cardStyle(cornerRadius: 14, padding: 14)` | `.neuSurface(.raised, radius: 20, padding: 14, isInteractive: true)` |
| 349 (WhereItsGoingCard) | `.cardStyle(cornerRadius: 16, padding: 18)` | replaced entirely by `SpendDonutCard` call |

**Background token** (line 234 — `Color(.systemGroupedBackground)`):
```swift
// Replace:
.background(Color(.systemGroupedBackground))
// With:
.scrollContentBackground(.hidden)
.background(DesignTokens.bgCanvas)
```

**Section header `sectionHeader` helper** (lines 245–259) — replace:
```swift
// .foregroundStyle(.primary) on Text:
.foregroundStyle(DesignTokens.label)
// .tint(.accentColor) on Button:
.tint(DesignTokens.accent)
// Font: keep .title2 / .bold; add tracking for section headers
.font(.system(size: 22, weight: .bold))
```

**Month label** (line 164):
```swift
// Replace .foregroundStyle(.secondary) with:
.foregroundStyle(DesignTokens.label2)
```

**WhereItsGoingCard replacement** (lines 301–351 in `OverviewView.swift`):
Remove the `private struct WhereItsGoingCard` entirely. Replace the call site (line 195) with:
```swift
if !rankedSpend.isEmpty {
    Text("Where it's going")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(DesignTokens.label)
        .padding(.horizontal, DesignTokens.spacing16)
    SpendDonutCard(
        ranked: Array(rankedSpend.prefix(4)),
        total: totalSpend,
        onCategoryTap: { uuid in
            activityCategoryFilter = uuid
            selectedTab = 1
        }
    )
    .padding(.horizontal, DesignTokens.spacing16)
}
```

**ReviewBanner** (lines 272–297) — system color and `.cardStyle` replacements:
```swift
// .accentColor → DesignTokens.accent on IconTile
IconTile(symbol: "envelope", color: DesignTokens.accent, size: 38, cornerRadius: 10)
// .foregroundStyle(.primary) → DesignTokens.label
// .foregroundStyle(.secondary) → DesignTokens.label2
// .foregroundStyle(.tertiary) → DesignTokens.label3
// .cardStyle(cornerRadius: 14, padding: 14) → .neuSurface(.raised, radius: 20, padding: 14, isInteractive: true)
```

**BudgetGlanceRow + ProgressBarLine** (lines 355–410):
```swift
// Color(.systemRed) → DesignTokens.negative
// Color(.systemOrange) → DesignTokens.orange
// Color(.tertiarySystemFill) → DesignTokens.fillRecessed2
// .foregroundStyle(.secondary) → DesignTokens.label2
// .foregroundStyle(.tertiary) → DesignTokens.label3
```

**SpendBudgetCard call removal / NET CASH FLOW hero replacement:**
The existing `SpendBudgetCard` (stacked bar, spent+remaining layout) does NOT match the new UI-SPEC (income/spent split tiles). The planner must plan the `SpendBudgetCard.swift` internal layout rewrite (see `SpendBudgetCard.swift` section below).

---

### `Features/Overview/SpendBudgetCard.swift` (component — layout rewrite + cardStyle migration)

**Analog:** `Features/Assets/NetWorthCard.swift` (hero floating card with donut center + two split tiles)

**cardStyle migration** (line 101):
```swift
// Replace:
.cardStyle(cornerRadius: 16, padding: 18)
// With (hero tier):
.neuSurface(.floating, padding: 18)
```

**System colors to replace** (lines 38–39, 68–69):
```swift
// Color(.systemGreen) → DesignTokens.positive
// Color(.systemRed) → DesignTokens.negative
// .foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2)
// .tint(.accentColor) → .tint(DesignTokens.accent)
```

**Layout rewrite for NET CASH FLOW spec** (UI-SPEC Screen 1 — income/spent split tiles):
- The current stacked-bar + spend/remaining layout becomes income + spent tiles
- `RollingMoneyText` for the net cash flow total (hero, 46pt)
- Income tile and spent tile each use `.neuSurface(.recessed, radius: DesignTokens.radiusInner)` (nested surface pattern)
- Budget progress strip: flat, no `.neuSurface`, track `DesignTokens.fillRecessed2`, fill `DesignTokens.positive`/`DesignTokens.negative`

---

### `Features/Overview/PinnedNoteCard.swift` (component, request-response)

**Analog:** self

**Replacements** (lines 63–113):
```swift
// Color.accentColor → DesignTokens.accent (line 64)
// .foregroundStyle(.primary) → .foregroundStyle(DesignTokens.label)
// .foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2)
// .tint(.accentColor) → .tint(DesignTokens.accent)
// .padding(16).background(Color(.secondarySystemBackground))
//   .clipShape(RoundedRectangle(cornerRadius: 12))
//   .shadow(...)  →  .neuSurface(.raised, isInteractive: true)
```
The entire `VStack.padding(16).background(...).clipShape(...).shadow(...)` block at lines 109–114 is replaced with `.neuSurface(.raised, isInteractive: true)` since the card is tappable.

---

### `Features/Expenses/ExpenseRow.swift` (component, request-response)

**Analog:** `Features/Overview/OverviewView.swift` `RecentExpenseRow` struct (lines 415–452) — same role, same data

**Replacements** (lines 9–63):
```swift
// .foregroundStyle(.primary) → .foregroundStyle(DesignTokens.label) (line 22)
// .foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2) (line 35)
// Color(.systemGreen) → DesignTokens.positive (line 41)
// Color(.label) → DesignTokens.label (line 41)
```
The `IconTile` color is derived from `CategoryStyle.color(for: category)` which after the `CategoryStyle` rewrite returns `DesignTokens.cat*` automatically — no direct change needed in `ExpenseRow`.

---

### `Features/Budgets/BudgetCategoryCard.swift` (component, request-response)

**Analog:** `Features/Assets/NetWorthCard.swift` `legendRow` (lines 103–117) for the bullet dot + label + amount pattern

**cardStyle migration** (line 86):
```swift
// Replace:
.cardStyle(cornerRadius: 14, padding: 15)
// With:
.neuSurface(.raised, radius: 20, padding: 15, isInteractive: true)
```

**System colors to replace** (lines 26–29, 104–105):
```swift
// Color(.systemRed) → DesignTokens.negative
// Color(.systemOrange) → DesignTokens.orange
// Color(.tertiarySystemFill) → DesignTokens.fillRecessed2  (progress bar track, line 76)
// Color(.tertiaryLabel) → DesignTokens.label3
// Color(.secondaryLabel) → DesignTokens.label2
// .foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2)
// .foregroundStyle(.tertiary) → .foregroundStyle(DesignTokens.label3)
```

---

### `Features/Assets/NetWorthCard.swift` (component, request-response — cardStyle migration + color swap)

**Analog:** self (cardStyle migration + color swap only; chart data and `DonutSegment` building unchanged)

**cardStyle migration** (line 68):
```swift
// Replace:
.cardStyle(cornerRadius: 16, padding: 18)
// With:
.neuSurface(.floating, padding: 18)
```

**System colors to replace** (lines 95–98, 134–138):
```swift
// Color(.systemBlue) → DesignTokens.catSubscriptions  (Mutual Funds legend bullet)
// Color(.systemGreen) → DesignTokens.positive          (Stocks legend bullet + value)
// Color(.systemOrange) → DesignTokens.orange           (NPS legend bullet)
// Color(.systemTeal) → DesignTokens.catAuto            (Cash legend bullet)
// .foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2)
// Text in donutCenter: .foregroundStyle(.secondary) → DesignTokens.label2
//                      .foregroundStyle(.primary)   → DesignTokens.label
```

---

### `Features/Settings/AccountDetailView.swift` and `Features/Assets/AssetDetailView.swift` (screens — cardStyle migration)

**Analog:** `Features/Assets/NetWorthCard.swift` (same `.floating` hero pattern)

**cardStyle migration:**
```swift
// AccountDetailView.swift line 156:
.cardStyle()  →  .neuSurface(.floating)

// AssetDetailView.swift line 153:
.cardStyle()  →  .neuSurface(.floating)
```

---

### `Features/Notes/RoutineDetailView.swift` (screen — cardStyle migration)

**cardStyle migration** (line 122):
```swift
.cardStyle()  →  .neuSurface(.raised)
```

---

### `Features/Settings/SettingsView.swift` (screen — icon color map + cardStyle migration)

**cardStyle migration** (line 341):
```swift
.cardStyle(cornerRadius: 14)  →  .neuSurface(.raised, radius: 20)
```

**Icon tile color map** (replace all `Color(.systemX)` per UI-SPEC Screen 5):
```swift
// Face ID Lock:        Color(.systemGreen)  → DesignTokens.positive
// Notifications/bell:  Color(.systemRed)    → DesignTokens.negative
// Connect Gmail:       Color(.systemRed)    → DesignTokens.negative
// Sync now:            Color(.systemBlue)   → DesignTokens.accent
// Reconnect Gmail:     Color(.systemOrange) → DesignTokens.orange
// Accounts:            Color(.systemBlue)   → DesignTokens.catSubscriptions
// Assets:              Color(.systemPurple) → DesignTokens.catHealth
// Manage Categories:   Color(.systemIndigo) → DesignTokens.catRent
// Budget period:       Color(.systemOrange) → DesignTokens.orange
// About MyHome:        Color(.systemGreen)  → DesignTokens.accent
// .foregroundStyle(.accentColor) / .tint(.accentColor) → DesignTokens.accent
```

---

### `Features/Budgets/BudgetsView.swift` (screen — 3 cardStyle migrations + system colors)

**cardStyle migrations** (lines 211, 258, 304):
```swift
// Line 211: .cardStyle(cornerRadius: 12)          → .neuSurface(.raised, radius: 20)
// Line 258: .cardStyle(cornerRadius: 16, padding: 22) → .neuSurface(.floating, padding: 22)
// Line 304: .cardStyle(cornerRadius: 16, padding: 20) → .neuSurface(.raised, padding: 20)
```

**System colors (lines vary)**:
```swift
// Color(.systemBackground) → DesignTokens.bgCanvas
// Color(.systemRed)        → DesignTokens.negative
// Color(.systemOrange)     → DesignTokens.orange
// Color(.systemGreen)      → DesignTokens.positive
// Color(.tertiarySystemFill) → DesignTokens.fillRecessed2
```

---

## Shared Patterns

### 1. NeuSurface Call Pattern
**Source:** `MyHomeApp/DesignSystem/NeuSurface.swift` lines 194–201 + Preview lines 206–246
**Apply to:** All 14 `cardStyle` call sites; every file with inline `.background + .clipShape + .shadow`

```swift
// Standard card
someView.neuSurface(.raised)

// Hero/floating card (net-cash-flow, budget ring, account/asset header)
someView.neuSurface(.floating, padding: 18)

// Tappable/interactive card (adds glassBorder affordance — WCAG 1.4.11)
Button { action() } label: { someView }
    .neuSurface(.raised, isInteractive: true)

// Input well / progress track
someView.neuSurface(.recessed, radius: DesignTokens.radiusInner)

// Custom radius (e.g. compact cards in Budgets):
someView.neuSurface(.raised, radius: 20, padding: 15)
```

### 2. Canvas Background (every screen)
**Source:** `DesignSystem/NeuSurface.swift` Preview body + `14-UI-SPEC.md` Global Rules
**Apply to:** Every `ScrollView`, `List`, `NavigationStack`

```swift
// List:
List { ... }
    .scrollContentBackground(.hidden)
    .background(DesignTokens.bgCanvas)

// ScrollView:
ScrollView { ... }
    .background(DesignTokens.bgCanvas)

// List row background:
.listRowBackground(DesignTokens.surfaceRaised)
```

Replace `Color(.systemGroupedBackground)` (e.g. `OverviewView.swift` line 234) and `Color(.systemBackground)` everywhere.

### 3. Label Tier Replacements (all views)
**Source:** `DesignTokens.swift` lines 29–32
**Apply to:** All 209 `.primary/.secondary/.tertiary` occurrences across all files

```swift
.foregroundStyle(.primary)   → .foregroundStyle(DesignTokens.label)
.foregroundStyle(.secondary) → .foregroundStyle(DesignTokens.label2)
.foregroundStyle(.tertiary)  → .foregroundStyle(DesignTokens.label3)
// Color(.label)             → DesignTokens.label
```

### 4. Accent Color Replacement
**Source:** `DesignTokens.swift` line 21
**Apply to:** All `.tint(.accentColor)`, `Color.accentColor`, `.foregroundStyle(.accentColor)` occurrences

```swift
.tint(.accentColor) → .tint(DesignTokens.accent)
Color.accentColor   → DesignTokens.accent
```

### 5. Semantic Color Replacements
**Source:** `DesignTokens.swift` lines 23–25
**Apply to:** All files with income/spend/warning states

```swift
Color(.systemGreen)  → DesignTokens.positive   // income amounts, positive net
Color(.systemRed)    → DesignTokens.negative   // spend amounts, over-budget, destructive
Color(.systemOrange) → DesignTokens.orange     // warnings, overdue, staleness
```

### 6. 21pt Animated Stat (non-hero money text)
**Source:** `DesignSystem/RollingMoneyText.swift` lines 86–89 (Preview stat variant)
**Apply to:** Donut center, income/spent split tiles, balance readouts that are NOT the 46pt hero

```swift
// Use this pattern — NOT RollingMoneyText — for any text smaller than 46pt
Text(amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
    .font(.system(size: 21, weight: .light, design: .rounded))
    .foregroundStyle(DesignTokens.label)
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(.smooth(duration: 0.78), value: amount)
```

### 7. RollingMoneyText (46pt hero)
**Source:** `DesignSystem/RollingMoneyText.swift` lines 29–61
**Apply to:** Net cash flow total in Overview hero card, budget left-to-spend in Budgets hero, account detail balance

```swift
// Default (label color):
RollingMoneyText(amount: balance)

// Negative/spent amount:
RollingMoneyText(amount: spent, color: DesignTokens.negative)

// Positive/income amount:
RollingMoneyText(amount: income, color: DesignTokens.positive)
```

### 8. DonutChart Call Pattern
**Source:** `Features/Shared/DonutChart.swift` lines 17–47 + `Features/Assets/NetWorthCard.swift` lines 51–54
**Apply to:** `SpendDonutCard.swift` (new), `Features/Budgets/BudgetsView.swift` (budget summary ring)

```swift
DonutChart(segments: segments, size: 132) {
    // center: closure — any View
    VStack(spacing: 0) {
        Text("LABEL")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(DesignTokens.label2)
        // money text here (21pt or RollingMoneyText depending on size)
    }
}
// DonutChart is .accessibilityHidden(true) built-in — legend rows MUST carry .accessibilityLabel
```

### 9. Decimal → Double Conversion (for DonutSegment.value)
**Source:** `Features/Assets/NetWorthCard.swift` lines 130–132 (T-11-13 pattern)

```swift
// Safe conversion — never use Double(truncating:) or Double(d as NSNumber)
private func toDouble(_ v: Decimal) -> Double {
    NSDecimalNumber(decimal: max(v, .zero)).doubleValue
}
```

### 10. TabView Tint (RootView only)
**Source:** `RootView.swift` line 66 area + `14-UI-SPEC.md` Native Tab Bar Restyle

```swift
TabView(selection: $selectedTab) { ... }
    .tint(DesignTokens.accent)
```

### 11. selectedTab Deep-link Pattern (OVR-06 navigation)
**Source:** `RootView.swift` lines 35–36, 110–116 + `OverviewView.swift` lines 17–19
**Apply to:** `SpendDonutCard` tap callback, `RootView` new state, `ExpenseListView` new binding param

```swift
// RootView — new state alongside existing deepLinkNoteID:
@State private var activityCategoryFilter: UUID? = nil

// Existing deep-link pattern (kOpenNoteNotification at line 110):
.onReceive(NotificationCenter.default.publisher(for: kOpenNoteNotification)) { notification in
    if let noteID = notification.userInfo?["noteID"] as? UUID {
        deepLinkNoteID = noteID
        selectedTab = 3
    }
}
// OVR-06 mirrors this: closure writes activityCategoryFilter UUID, then selectedTab = 1
```

### 12. Progress Bar Track
**Source:** `Features/Overview/OverviewView.swift` `ProgressBarLine` struct (lines 395–411)
**Apply to:** `BudgetCategoryCard.swift` progress bar, `BudgetsView.swift` bars

```swift
// Track color replacement:
Color(.tertiarySystemFill) → DesignTokens.fillRecessed2

// Fill colors:
// On-budget: CategoryStyle.color(for: category) → DesignTokens.cat* (after CategoryStyle rewrite)
// Warning (>85%): Color(.systemOrange) → DesignTokens.orange
// Over: Color(.systemRed) → DesignTokens.negative
```

---

## Files with No Analog (new patterns)

None for this phase. All patterns are derivable from existing codebase analogs. `SpendDonutCard.swift` (the only new file) is a direct extraction + restyle of the existing `WhereItsGoingCard` private struct in `OverviewView.swift`, plus the `NetWorthCard` legend pattern.

---

## Files to Delete (pbxproj edits required)

| File | pbxproj edits | Reason |
|------|---------------|--------|
| `MyHomeApp/DesignSystem/NeuTabBar.swift` | 4 removals (PBXFileReference, PBXBuildFile, PBXSourcesBuildPhase, PBXGroup) | Orphaned — zero non-self references confirmed by grep |
| `MyHomeApp/Features/Shared/CardStyle.swift` | 4 removals (same 4 sections) | Deprecation shim; all 14 call sites migrated in this phase |

After deleting both files, verify with:
```
grep -r "NeuTabBar\|CardStyle" MyHomeApp/ --include="*.swift"
```
Expected: zero results (only comments acceptable).

---

## Metadata

**Analog search scope:** `MyHomeApp/DesignSystem/`, `MyHomeApp/Features/`, `MyHomeApp/RootView.swift`
**Files read directly:** DesignTokens.swift, NeuSurface.swift, RollingMoneyText.swift, DonutChart.swift, CategoryStyle.swift, CardStyle.swift, NetWorthCard.swift, OverviewView.swift, SpendBudgetCard.swift, PinnedNoteCard.swift, ExpenseListView.swift (partial), ExpenseRow.swift, BudgetCategoryCard.swift, RootView.swift
**Pattern extraction date:** 2026-06-21
