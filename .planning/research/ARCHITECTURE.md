# Architecture Patterns

**Domain:** iOS SwiftUI/SwiftData personal-finance app — v1.2 Neumorphic Redesign milestone
**Researched:** 2026-06-20
**Confidence:** HIGH — grounded in direct codebase reading of 187 Swift files at SchemaV9

---

## Context: What Exists at v1.1 / SchemaV9

The app at v1.1 is fully functional. The design system does not yet exist as a layer; styling is scattered inline across views using stock SwiftUI semantic colors (`Color(.secondarySystemBackground)`, `.accentColor`, `.primary`, `.secondary`) with a thin shared abstraction in `Features/Shared/`:

| Shared abstraction | What it does | v1.2 status |
|--------------------|--------------|-------------|
| `CardStyle.swift` (ViewModifier) | Applies `Color(.secondarySystemBackground)` + 16px radius + shadow 0.04 | **Replace** with neumorphic surface modifier |
| `CategoryStyle.swift` (enum) | Maps Category → display Color + SF Symbol; uses iOS system palette | **Extend** with design-system cat colors; retain hashed fallback |
| `DonutChart.swift` (generic View) | Swift Charts `SectorMark` donut; used by Overview "Where it's going" | **Restyle** colors/glow; keep chart logic intact |
| `IconTile.swift` (View) | Rounded-square category badge | **Restyle** with neumorphic fill/glow |
| `StackBar.swift` | Horizontal stack bar for budget overview hero | **Restyle** |

Chart infrastructure (in `Support/`):
- `SpendOverTimeAggregator` — pure static; buckets `[Expense]` into `[SpendBucket]` (week/month/year). Uses in `SpendOverTimeChart` on existing Expenses tab.
- `OverviewAggregation` — pure static; top-3 categories, aggregate threshold, pinned note.
- `BudgetCalculator` — pure static; monthly spend map, uncategorized spend, month boundaries.
- `SpendByCategoryChart` — `BarMark` chart; used on existing screen; input: `[CategorySpendItem]`.

Root / navigation:
- `MyHomeApp.swift` — owns `ModelContainer`, `GmailSyncController`; registers BGTask.
- `RootView.swift` — `TabView` with 5 tabs (Home 0, Expenses 1, Budgets 2, Notes 3, Settings 4); owns service @State instances; wires `scenePhase` → all services.
- Each tab owns its own `NavigationStack`; no shared `NavigationPath`.
- Tab bar rendered by SwiftUI's built-in `TabView`; must be **replaced** with the floating capsule.

No existing theme/token file exists. No `Color+Theme.swift`, no `DesignTokens` enum. The neumorphic layer must be created from scratch.

---

## Three New Architecture Concerns

### 1. Neumorphic Design System Layer

#### Design Token Structure (from `tokens.jsx` analysis)

The `neuro` skin (the target) specifies these token groups that must be mirrored in Swift:

**Surface colors (charcoal)**
```
--bg:            #1C1C23   // page/screen background
--bg-elevated2:  #262630   // raised card surface
--fill:          #16161C   // inset/pressed surface
--fill2:         #191920
--fill3:         #15151B
--label:         #ECEDF4   // primary text
--label2:        rgba(220,223,238,0.56)
--label3:        rgba(220,223,238,0.32)
--label4:        rgba(220,223,238,0.16)
--sep:           rgba(255,255,255,0.05)
```

**Dual shadow (neumorphic extrusion)**
```
Raised shadow:  -6px -6px 14px rgba(255,255,255,0.035),
                 7px  7px 18px rgba(0,0,0,0.55)
Float shadow:   -9px -9px 22px rgba(255,255,255,0.04),
                11px 11px 28px rgba(0,0,0,0.62)
Inset rim:      inset 1px 1px 1px rgba(255,255,255,0.045),
                inset -1px -1px 1px rgba(0,0,0,0.30)
Card radius:    26px
```

**Accent palette**
```
--accent (canary yellow):  #FFD60A
--accent-soft:             rgba(255,214,10,0.16)
--pos (income/gain):       #34E29B
--neg (spend/loss):        #FF6B6B
Category colors: defined per-id in CAT_COLORS (teal, orange, pink, etc.)
```

**Tab bar** (from `ui.jsx` → `TabBar` component):
- Floating capsule, 62px height, 34px borderRadius, positioned 24px above screen bottom
- Glass body: `var(--glass-tint-strong)` = `#22222C` (neuro skin), no backdrop blur
- Active tab indicator: slides with spring animation, accent-soft background + accent glow
- Five icons + labels, 58px wide each

#### Recommended Swift Structure

```
MyHomeApp/DesignSystem/
├── DesignTokens.swift          NEW — Color + CGFloat constants
├── NeuSurface.swift            NEW — ViewModifier (raised/pressed/inset variants)
├── NeuTabBar.swift             NEW — floating capsule TabView replacement
├── RollingMoneyText.swift      NEW — animated odometer number view
├── DeltaChip.swift             NEW — ±% badge (green/red, glow border)
├── SegmentedRangeBar.swift     NEW — liquid-ink tab underline control (Analytics)
└── Color+Neumorphic.swift      NEW — Color extension for token lookups
```

**DesignTokens.swift** — single source of truth:
```swift
enum DesignTokens {
    // Surfaces
    static let bgPrimary        = Color(hex: "#1C1C23")
    static let bgElevated       = Color(hex: "#262630")
    static let fillInset        = Color(hex: "#16161C")
    // Text
    static let labelPrimary     = Color(hex: "#ECEDF4")
    static let labelSecondary   = Color(hex: "#DCDFEESS").opacity(0.56)
    static let labelTertiary    = Color(hex: "#DCDFEE").opacity(0.32)
    // Accent
    static let accentYellow     = Color(hex: "#FFD60A")
    static let accentSoft       = Color(hex: "#FFD60A").opacity(0.16)
    static let posGreen         = Color(hex: "#34E29B")
    static let negRed           = Color(hex: "#FF6B6B")
    // Shadows (CGSize/opacity used in View modifier)
    static let neuRaisedLight   = Shadow(color: .white.opacity(0.035), radius: 14, x: -6, y: -6)
    static let neuRaisedDark    = Shadow(color: .black.opacity(0.55),  radius: 18, x: 7,  y: 7)
    static let cardRadius: CGFloat = 26
    static let cardRadiusSmall: CGFloat = 16
    // Category palette (matches CAT_COLORS in tokens.jsx)
    static let catColors: [String: Color] = [
        "groceries":     Color(hex: "#2DD4BF"),
        "dining":        Color(hex: "#FB923C"),
        "fuel":          Color(hex: "#F472B6"),
        "utilities":     Color(hex: "#7DD3FC"),
        "rent":          Color(hex: "#818CF8"),
        "shopping":      Color(hex: "#E879F9"),
        "health":        Color(hex: "#A78BFA"),
        "subscriptions": Color(hex: "#22D3EE"),
        "entertainment": Color(hex: "#C084FC"),
        "other":         Color(hex: "#94A3B8"),
    ]
}
```

**NeuSurface.swift** — three variants, each a `ViewModifier`:
- `.raised` — default card surface: bgElevated + dual shadow + inset rim
- `.pressed` — inset/tapped state: fillInset + inverted shadow (dark top-left, light bottom-right)
- `.inset` — track/progress background: fillInset + no shadow

Usage: `view.neuSurface(.raised, radius: DesignTokens.cardRadius)`

**Light/dark adaptation**: The design is dark-only for the Neomorphism skin (no dynamic color needed for `neuro` style). `DesignTokens` constants are static. If future light mode is wanted, wrap in a `@Environment(\.colorScheme)` check — but for v1.2 the neuro skin is dark-only; this is a non-issue.

**Existing `CardStyle` modifier**: Replace call sites. `cardStyle(...)` → `neuSurface(.raised)`. The old modifier is removed after all call sites are updated (done per-screen during the restyle phase).

**CategoryStyle.swift**: Extend to read from `DesignTokens.catColors` by mapping the existing `symbolName` string to the new luminous palette. The hashed fallback logic is retained. No schema change needed.

**RollingMoneyText** — animated odometer view translating `RollingNumber`/`RollingMoney` from `motion.jsx`:
```swift
struct RollingMoneyText: View {
    let value: Decimal          // authoritative Decimal — never Double
    var duration: Double = 0.78 // seconds, matches design's 780ms
    var style: Font = .largeTitle

    // Internal state: animates a Double from previous to next value via
    // withAnimation(.easeOut(duration:)) + interpolation using a @State displayValue: Double.
    // Formats displayValue via Decimal(displayValue).formattedINRWhole() for display only.
    // Decimal → Double conversion happens only for animation interpolation, never for money math.
}
```

The Decimal→Double→animate→format pattern is safe here because the *displayed* intermediate value is for animation only; the authoritative value is always the Decimal source and is the value used when animation completes.

**NeuTabBar** — replaces `TabView`'s built-in tab bar. Implemented as a `ZStack` overlay in `RootView`:
- Floating `HStack` of `NeuTabItem` views in a capsule `RoundedRectangle`
- `@Namespace` animation for the sliding active indicator
- Badge support via `ZStack` overlay count chip on individual tab icons
- `selectedTab: Binding<Int>` mirrors the existing `@State private var selectedTab` in `RootView`

**RootView integration**: The existing `TabView` loses `.tabItem {}` modifiers. The `TabView` becomes a plain page container with `tabViewStyle(.page(indexDisplayMode: .never))` or the tabs become manual `ZStack` with conditional visibility. The simpler approach: keep `TabView` for content hosting (so navigation stacks continue to work), add `NeuTabBar` as a `.overlay(alignment: .bottom)` on the `TabView`, and suppress the native bar with `.toolbar(.hidden, for: .tabBar)`.

---

### 2. FoundationModels AI Insight Service Layer

#### Framework Facts (HIGH confidence from Apple Developer documentation and verified community sources)

- Framework: `FoundationModels` (iOS 26+, Apple Intelligence required)
- On-device ~3B parameter model; no network calls; no API keys
- Availability check: `SystemLanguageModel.default.availability`
  - `.available` — ready
  - `.unavailable(reason:)` with `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`, `@unknown default`
- Session API: `LanguageModelSession(instructions:)` — maintains conversation history
- Response: `session.respond(to:)` async throws → `content: String`
- Streaming: `session.streamResponse(to:)` → `AsyncSequence` of partial types
- Structured output: `@Generable` macro on a struct; `session.respond(to:generating: MyStruct.self)`

#### Service Layer Design

```swift
// MyHomeApp/Features/AI/InsightService.swift   NEW

@Observable
final class InsightService {
    enum State {
        case idle
        case loading
        case ready(insight: SpendInsight)
        case unavailable(reason: String)
        case failed(error: Error)
    }

    var state: State = .idle
    private var session: LanguageModelSession?
    private var cachedForRange: AnalyticsRange?
    private var cachedAt: Date?

    /// Called by AnalyticsView when range changes or on-appear.
    @MainActor
    func refresh(summary: SpendSummary) async { ... }
}

@Generable
struct SpendInsight {
    @Guide(description: "2–3 sentence natural-language observation about spending patterns")
    var text: String

    @Guide(description: "The main category driving the observation, e.g. 'Dining'")
    var leadCategory: String?

    @Guide(description: "Whether total spend is trending up or down vs comparison period",
           anyOf: ["up", "down", "flat"])
    var trend: String
}
```

**Availability gating** — checked at `InsightService.refresh()` entry:
```swift
guard case .available = SystemLanguageModel.default.availability else {
    let reason = unavailabilityReason(SystemLanguageModel.default.availability)
    state = .unavailable(reason: reason)
    return
}
```

The `AnalyticsView` renders the `AIInsightCard` only when `insightService.state != .unavailable`. On unavailable devices, the card section is simply omitted — no error state shown, no placeholders. The rest of `AnalyticsView` (area chart, category bars) is unaffected.

**Input: SpendSummary** — a pure value type constructed by `AnalyticsAggregator` before being passed to `InsightService`. Never pass raw SwiftData `[Expense]` to the service:
```swift
struct SpendSummary {
    let range: AnalyticsRange
    let total: Decimal
    let previousTotal: Decimal          // for delta %
    let topCategories: [(name: String, amount: Decimal)]
    let buckets: [SpendBucket]          // already computed by AnalyticsAggregator
}
```

The `SpendSummary` is formatted into a compact prompt string inside `InsightService.refresh()` — no PII, only aggregate numbers and category names.

**Caching** — `InsightService` caches the last `SpendInsight` for the current `range`. Calling `refresh()` with the same range + same-day data skips the LLM call. Cache is invalidated when `range` changes or on new calendar day.

**Session lifecycle** — one `LanguageModelSession` per app session (created lazily on first use). Not recreated on each call. This matches the WWDC recommendation to reuse sessions.

**Ownership** — `InsightService` is owned as `@State private var insightService = InsightService()` in `AnalyticsView`, not in `RootView`. The service is scoped to the Analytics feature; no app-wide sharing needed. If `RootView` ever needs to warm up the model, it can call `SystemLanguageModel.default.availability` check only — not hold the service.

**File location**: `MyHomeApp/Features/Analytics/InsightService.swift`

---

### 3. Analytics Data Aggregation

#### New Aggregator: AnalyticsAggregator

The existing `SpendOverTimeAggregator` handles bucketing for the week/month/year area chart — this is directly reusable. The Analytics screen adds:
- Spend vs previous period (delta %)
- Category bars sorted by amount
- The `SpendSummary` struct for the AI service

```swift
// MyHomeApp/Support/AnalyticsAggregator.swift   NEW (mirrors SpendOverTimeAggregator discipline)

enum AnalyticsAggregator {
    /// Buckets expenses and computes comparison-period delta.
    static func compute(
        expenses: [Expense],        // current-period expenses (from @Query in AnalyticsView)
        previousExpenses: [Expense], // prior period for delta (same window shifted back)
        range: AnalyticsRange,
        categories: [Category]
    ) -> AnalyticsResult

    struct AnalyticsResult {
        let buckets: [SpendBucket]                           // reused from SpendOverTimeAggregator
        let total: Decimal
        let previousTotal: Decimal
        let deltaPct: Double                                 // (total - previousTotal) / previousTotal
        let byCategory: [(category: Category, spent: Decimal)]   // sorted descending
        let summary: SpendSummary                           // feeds InsightService
    }
}
```

**Pure contract**: same as `SpendOverTimeAggregator` and `BudgetCalculator` — operates on already-fetched arrays, no SwiftData access, no `@Query`, no Charts import.

**Reuse of existing infrastructure**:
- Buckets: `SpendOverTimeAggregator.bucket(expenses:range:)` — called from `AnalyticsAggregator.compute()`, not duplicated.
- Category spend map: `BudgetCalculator.monthlySpend(for:categories:)` — reused for the by-category bars.
- `SpendRange` enum (existing): extend or alias as `AnalyticsRange` (or reuse directly if the same week/month/year cases fit).

**Where aggregation logic lives**: `AnalyticsAggregator` is a pure static helper in `Support/`. It is called from `AnalyticsView`'s `body` before any Chart DSL, identical to how `OverviewView` calls `BudgetCalculator.monthlySpend()` pre-body. No separate view model class is needed — the existing inline aggregation pattern in `body {}` (outside Chart DSL) is already established and works correctly.

**Overview donut reuse**: `WhereItsGoingCard` in `OverviewView` already uses `DonutChart` with `rankedSpend`. The Analytics "by category" bars use `AnalyticsAggregator.compute().byCategory`. Both share the same `BudgetCalculator.monthlySpend()` call path — no duplication of aggregation logic; only the input `[Expense]` scope differs (month-bounded for Overview, range-bounded for Analytics).

**@Query scope in AnalyticsView**:
```swift
// Current period
@Query private var currentExpenses: [Expense]
// Previous period (shifted date window)
@Query private var previousExpenses: [Expense]

init(range: AnalyticsRange) {
    // Dynamically construct predicates based on range
    // Pattern: same as OverviewMonthContent init with dynamic Query construction
    let (curStart, curEnd) = AnalyticsAggregator.windowBounds(for: range, offset: 0)
    let (prevStart, prevEnd) = AnalyticsAggregator.windowBounds(for: range, offset: -1)
    _currentExpenses = Query(filter: #Predicate { $0.date >= curStart && $0.date <= curEnd }, ...)
    _previousExpenses = Query(filter: #Predicate { $0.date >= prevStart && $0.date <= prevEnd }, ...)
}
```

This mirrors `OverviewMonthContent`'s dynamic `Query` init pattern exactly.

---

## Complete Component Map: New vs Modified

### New Components

| Component | Kind | Location | Purpose |
|-----------|------|----------|---------|
| `DesignTokens` | enum | `DesignSystem/DesignTokens.swift` | Single source of truth for all visual constants |
| `NeuSurface` | ViewModifier | `DesignSystem/NeuSurface.swift` | Raised/pressed/inset neumorphic surfaces |
| `NeuTabBar` | View | `DesignSystem/NeuTabBar.swift` | Floating capsule tab bar with spring animation |
| `RollingMoneyText` | View | `DesignSystem/RollingMoneyText.swift` | Animated odometer Decimal → formatted INR |
| `DeltaChip` | View | `DesignSystem/DeltaChip.swift` | ±% badge with pos/neg glow border |
| `SegmentedRangeBar` | View | `DesignSystem/SegmentedRangeBar.swift` | Liquid-ink sliding range control |
| `Color+Neumorphic` | extension | `DesignSystem/Color+Neumorphic.swift` | `Color(hex:)` initializer (already have `Color+Hex.swift` — check if exists) |
| `AnalyticsView` | View | `Features/Analytics/AnalyticsView.swift` | New Analytics tab (area chart + category bars + AI insight) |
| `AreaTrendChart` | View | `Features/Analytics/AreaTrendChart.swift` | Swift Charts `AreaMark` + `LineMark` with scanning dot simulation |
| `CategoryBarsView` | View | `Features/Analytics/CategoryBarsView.swift` | Horizontal liquid-glow category bars with tap tooltip |
| `AIInsightCard` | View | `Features/Analytics/AIInsightCard.swift` | Frosted glass card, typewriter text reveal, breathing orb |
| `InsightService` | @Observable | `Features/Analytics/InsightService.swift` | FoundationModels session, availability gate, caching |
| `AnalyticsAggregator` | enum | `Support/AnalyticsAggregator.swift` | Pure static analytics computation, delta %, SpendSummary |
| `SpendSummary` | struct | `Support/AnalyticsAggregator.swift` | Value type fed to InsightService |
| `AnalyticsResult` | struct | `Support/AnalyticsAggregator.swift` | Full output of AnalyticsAggregator.compute() |

### Modified Components

| Component | Location | What Changes |
|-----------|----------|-------------|
| `RootView` | `RootView.swift` | Add `NeuTabBar` overlay; suppress native tab bar; add Analytics tab (tag 5); own `insightService` only if pre-warming |
| `CardStyle` | `Features/Shared/CardStyle.swift` | Replace body with neumorphic surface; or delete and migrate call sites to `neuSurface(.raised)` |
| `CategoryStyle` | `Features/Shared/CategoryStyle.swift` | Extend `bySymbol` map to use `DesignTokens.catColors` luminous palette |
| `DonutChart` | `Features/Shared/DonutChart.swift` | No logic change; restyle colors to luminous cat palette + glow |
| `IconTile` | `Features/Shared/IconTile.swift` | Restyle background fill; add luminous glow shadow |
| `OverviewView` (all subviews) | `Features/Overview/` | Apply neumorphic tokens to all card containers; replace `cardStyle()` calls |
| `SpendByCategoryChart` | `Features/Overview/SpendByCategoryChart.swift` | Restyle bar colors to luminous cat palette |
| `SpendOverTimeChart` | `Features/Overview/SpendOverTimeChart.swift` | Restyle line/area colors to DesignTokens.negRed + accent |
| `BudgetsView` + subviews | `Features/Budgets/` | Apply neumorphic tokens |
| `ExpenseListView` + subviews | `Features/Expenses/` | Apply neumorphic tokens |
| `NotesHomeView` + subviews | `Features/Notes/` | Apply neumorphic tokens |
| `SettingsView` | `Features/Settings/SettingsView.swift` | Apply neumorphic tokens |
| `AssetsListView` + subviews | `Features/Assets/` | Apply neumorphic tokens |
| `AccountsListView` + subviews | `Features/Settings/` | Apply neumorphic tokens |

**No schema changes in v1.2.** SchemaV9 is not bumped. The AI Insight, Analytics aggregation, and design system are all presentation/service-layer concerns. No new `@Model` types needed.

---

## Data Flow

### Design System Token Flow
```
DesignTokens (constants)
    ↓
NeuSurface ViewModifier
    ↓
Applied to: every card/row/sheet container across all screens
            NeuTabBar (reads token constants directly)
            RollingMoneyText (reads labelPrimary, negRed, posGreen)
            DeltaChip (reads negRed/posGreen + accentSoft)
```

### Analytics Screen Data Flow
```
@Query currentExpenses (date-bounded)
@Query previousExpenses (prior period)
@Query categories
    ↓ (body, pre-Chart-DSL)
AnalyticsAggregator.compute(...)
    ↓
AnalyticsResult {
    .buckets    → AreaTrendChart (Swift Charts AreaMark+LineMark)
    .byCategory → CategoryBarsView (custom animated bars)
    .summary    → InsightService.refresh(summary:)
    .deltaPct   → DeltaChip
    .total      → RollingMoneyText (hero number)
}
    ↓
InsightService (async, @Observable)
    ↓ availability gate
SystemLanguageModel.default.availability == .available
    ↓
LanguageModelSession.respond(to: prompt, generating: SpendInsight.self)
    ↓
SpendInsight.text → AIInsightCard (typewriter animation)
```

### AI Insight Availability Gate
```
AnalyticsView.onAppear / range change
    ↓
InsightService.refresh(summary:)
    ↓
SystemLanguageModel.default.availability
    ├── .available           → create/reuse session, call respond(), update .state = .ready(insight:)
    ├── .unavailable(reason) → .state = .unavailable(reason:) — AIInsightCard section hidden
    └── throws               → .state = .failed(error:) — AIInsightCard shows retry button
    ↓
AnalyticsView observes insightService.state
    ├── .idle/.loading → skeleton shimmer in AIInsightCard
    ├── .ready         → show insight text (typewriter animation on text change)
    ├── .unavailable   → AIInsightCard not rendered (section omitted entirely)
    └── .failed        → "Couldn't generate insight" + retry button
```

### Existing App Unaffected Path
```
Devices without Apple Intelligence:
SystemLanguageModel.default.availability == .unavailable(deviceNotEligible)
    ↓
InsightService.state = .unavailable
    ↓
AIInsightCard not rendered in AnalyticsView
    ↓
Everything else (charts, tab bar, tokens, all screens) unaffected — zero dependency on FoundationModels
```

---

## Recommended Build Order (Dependency-Aware)

```
Phase A: Design System Foundation        ← MUST come first; everything depends on this
    - DesignTokens.swift
    - NeuSurface.swift (ViewModifier, testable with Previews)
    - NeuTabBar.swift (replaces native tab bar in RootView)
    - RollingMoneyText.swift
    - DeltaChip.swift
    - Color+Hex.swift audit (file exists at Support/Color+Hex.swift — verify if reusable)
    - Update CategoryStyle to use DesignTokens.catColors
    - Update CardStyle → neuSurface(.raised) or delete CardStyle entirely
    - Deliverable: app looks neumorphic on RootView entry; existing tabs use new tab bar

Phase B: Restyle Existing Screens        ← Depends on Phase A tokens being stable
    Ordered by screen complexity (Overview is the most complex):
    B1. Overview (most components: hero, donut, budget glance, recent)
    B2. Expenses + ExpenseRow + ReviewInboxRow
    B3. Budgets + BudgetCategoryCard
    B4. Notes (NotesHomeView, NoteRow, CalendarView)
    B5. Settings + AccountsListView + AssetsListView + AccountDetailView
    - Deliverable: every screen restyled; no stock SwiftUI colors visible

Phase C: Analytics Screen (net-new)      ← Depends on Phase A; independent of Phase B
    C1. AnalyticsAggregator (pure static, write tests first)
    C2. AnalyticsView shell (tabs, data flow, @Query wiring)
    C3. AreaTrendChart (Swift Charts; reuse SpendOverTimeAggregator output)
    C4. CategoryBarsView (custom animated view; no Charts dependency)
    C5. Add Analytics tab to RootView (NeuTabBar gets 6th item, or Analytics is
        pushed from Overview "Analytics" entry row — match design intent)
    - Deliverable: Analytics screen with real data, no AI card yet

Phase D: AI Insight Card                 ← Depends on Phase C (needs AnalyticsView + SpendSummary)
    D1. InsightService (availability gate, session, caching; iOS 26 only)
    D2. SpendInsight @Generable struct
    D3. AIInsightCard view (typewriter animation, breathing orb, skeleton)
    D4. Wire InsightService into AnalyticsView
    - Deliverable: AI Insight working on iOS 26 / Apple Intelligence devices;
      invisible (section hidden) on all other devices
```

**Why this order:**
- Phase A must precede B because the token constants are the foundation all screen restyling depends on. Building B without A means all styling gets written twice.
- Phase B and Phase C are independent and can be interleaved by screen if needed (e.g. restyle Overview in B1 while building Analytics shell in C1). However, running B to completion first means the restyle pass is done in one focused context, reducing the risk of token drift.
- Phase D depends on Phase C because `InsightService.refresh()` takes a `SpendSummary` from `AnalyticsAggregator`, which is built in C1. The AI card also lives inside `AnalyticsView`, built in C2.

---

## Integration Constraints from Codebase

### Xcode pbxproj — Critical
Per `xcodeproj-explicit-file-refs.md` (memory): every new `.swift` file requires 4 manual edits to `project.pbxproj`. The `DesignSystem/` folder is new; all 7+ files in it must be explicitly registered. Phase A will produce the most new files at once — allocate time for pbxproj wiring.

### Schema Footgun Guard
Per `schema-version-mutation-footgun.md` (memory): v1.2 makes **no schema changes**. No SchemaV10, no typealias flips. This eliminates the entire category of typealias/schema migration bugs.

### Swift 6 Concurrency
`InsightService` is `@Observable` + `@MainActor`-isolated. `LanguageModelSession` calls are `async throws`; they must be wrapped in `Task { await ... }` from `onChange(of:)` or called from `.task {}` modifier in `AnalyticsView`. Pattern mirrors `LockController.authenticate()` in `RootView`:
```swift
.task(id: selectedRange) {
    let summary = AnalyticsAggregator.compute(...).summary
    await insightService.refresh(summary: summary)
}
```

### iOS Minimum Version
`FoundationModels` requires iOS 26. The app's current minimum is iOS 17. This means:
- `InsightService` must gate on both `#available(iOS 26, *)` AND `SystemLanguageModel.default.availability`.
- `import FoundationModels` must be wrapped in `#if canImport(FoundationModels)` or placed in a file with `@available(iOS 26, *)` annotation on the entire class.
- Recommended: mark `InsightService` with `@available(iOS 26, *)`. In `AnalyticsView`, use `if #available(iOS 26, *) { InsightServiceSection(...) }` to conditionally render the AI card section.

### TabBar Navigation
Adding an Analytics tab changes `selectedTab` integer values. Design shows Analytics as a NavigationStack push from the Overview "Analytics" entry row (not a new tab), which avoids renumbering. The design handoff's `AnalyticsScreen` component is a slide-in `PushView` overlay, not a tab. Confirm with roadmapper: **Analytics as push from Overview** (no new tab slot, tab bar stays at 5 items) vs **Analytics as 6th tab** (requires NeuTabBar to accommodate). The simpler approach — push from Overview — avoids tab count changes and matches the `home.jsx` code exactly (`openAnalytics` callback shows `AnalyticsScreen` as a slide-over).

---

## Patterns to Follow

### Token Usage — Always Indirect
Views never hardcode hex values. All colors come from `DesignTokens.*` or `CategoryStyle.color(for:)`. This is what makes the system a *system* — a single token change propagates everywhere.

### Aggregation Before Chart DSL
Established pattern (Pitfall A from existing codebase): all `BudgetCalculator`, `SpendOverTimeAggregator` calls happen in `body {}` BEFORE entering `Chart {}`. `AnalyticsAggregator.compute()` follows the same rule. Never pass `@Query` arrays directly into Chart DSL.

### Decimal-Safe Double Conversion
Established pattern (Pitfall B): `Decimal → Double` via `NSDecimalNumber(decimal:).doubleValue` at aggregation boundary only. `RollingMoneyText` internally interpolates `Double` for animation but formats from the authoritative `Decimal` source at the end state.

### @Observable Services, Not @StateObject
All existing services (`LockController`, `AMFINavService`, `RoutineResetService`, etc.) use `@Observable` + `@State`. `InsightService` follows the same pattern. No `ObservableObject`, no `@Published`.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Scattered Token Values
**What goes wrong:** Colors and radii inlined in each view file (the current state).
**Why it's bad:** One design token change requires editing 30+ files; inconsistency creeps in.
**Prevention:** All visual constants in `DesignTokens`. Phase A establishes this before any screen restyling begins.

### Anti-Pattern 2: FoundationModels Import Without Availability Guard
**What goes wrong:** `import FoundationModels` at top of file → compile failure on iOS 17 targets.
**Prevention:** Either wrap the entire `InsightService` class with `@available(iOS 26, *)` or use `#if canImport(FoundationModels)`. Test that the app builds and runs on iOS 17 simulator after wiring.

### Anti-Pattern 3: Passing Raw [Expense] to InsightService
**What goes wrong:** LLM prompt includes individual transaction records (PII risk, prompt too long).
**Prevention:** Always construct `SpendSummary` (aggregate totals, category names, no merchant names, no dates) in `AnalyticsAggregator` before calling `InsightService.refresh(summary:)`.

### Anti-Pattern 4: Creating a New LanguageModelSession Per Request
**What goes wrong:** Each new session discards conversation context and incurs model warm-up cost.
**Prevention:** `InsightService` creates session lazily once. Cache is checked before calling `respond()`. Session is retained for the `InsightService` lifetime.

### Anti-Pattern 5: Storing Decimal in RollingMoneyText Animation as Double
**What goes wrong:** `Decimal(displayValue: Double)` reconstruction loses precision; displayed amount drifts from authoritative value at animation completion.
**Prevention:** `RollingMoneyText` holds `var displayValue: Double` for animation interpolation only. When animation completes, render from the original `Decimal` parameter (not from `Decimal(displayValue)`). Format calls always use the source Decimal.

### Anti-Pattern 6: Making Analytics a Sixth Tab Before Confirming Design Intent
**What goes wrong:** NeuTabBar with 6 items needs layout adjustment (narrower items); changes selectedTab integer values, potentially breaking deep links.
**Prevention:** Default to the `home.jsx` pattern: Analytics is a push/slide from Overview. Only add as a tab if the roadmapper explicitly requires it after reviewing the design.

---

## Sources

- Direct codebase reading (HIGH confidence):
  - `MyHomeApp/RootView.swift` — tab structure, service ownership, scenePhase wiring
  - `MyHomeApp/Features/Shared/CardStyle.swift` — current card surface approach
  - `MyHomeApp/Features/Shared/CategoryStyle.swift` — current color mapping
  - `MyHomeApp/Features/Overview/OverviewView.swift` — aggregation before Chart DSL pattern; WhereItsGoingCard; dynamic @Query init
  - `MyHomeApp/Features/Overview/SpendByCategoryChart.swift` — CategorySpendItem, BarMark pattern
  - `MyHomeApp/Features/Overview/SpendOverTimeChart.swift` — existing AreaMark+LineMark, reusable for Analytics
  - `MyHomeApp/Support/SpendOverTimeAggregator.swift` — pure static bucketing; directly reusable in Analytics
  - `MyHomeApp/Support/OverviewAggregation.swift` — pure static aggregation discipline
  - `MyHomeApp/Support/BudgetCalculator.swift` — monthlySpend reusable for category bars
  - `MyHomeApp/Features/Shared/DonutChart.swift` — existing SectorMark donut
  - `MyHomeApp/Persistence/Schema/SchemaV9.swift` — confirmed schema at 11 model types; no v1.2 changes needed
  - `MyHomeApp/Persistence/Models/Expense.swift` — typealias pattern, STAB-08 lesson
  - `MyHomeApp/MyHomeApp.swift` — ModelContainer, BGTask, service ownership pattern
- Design handoff (HIGH confidence — primary design specification):
  - `design/design_handoff_myhome_neumorphic/src/tokens.jsx` — neuro skin token values
  - `design/design_handoff_myhome_neumorphic/src/ui.jsx` — TabBar, Screen, GroupedList, Row components
  - `design/design_handoff_myhome_neumorphic/src/analytics.jsx` — Analytics screen, AIInsight card, AreaChart, CategoryBars, LiquidTabs
  - `design/design_handoff_myhome_neumorphic/src/home.jsx` — HomeScreen, Analytics entry row, push-not-tab pattern
  - `design/design_handoff_myhome_neumorphic/src/motion.jsx` — RollingNumber/RollingMoney animation spec
- Apple FoundationModels framework (MEDIUM confidence — iOS 26, released 2025/2026; verified via AppCoda tutorial and CreateWithSwift documentation):
  - `SystemLanguageModel.default.availability` enum cases: `.available`, `.unavailable(reason:)`
  - `LanguageModelSession(instructions:)` init; `.respond(to:)` async; `.streamResponse(to:)` AsyncSequence
  - `@Generable` macro; `@Guide` for constrained fields
  - Minimum: iOS 26, Apple Intelligence enabled hardware
  - Source: [AppCoda Foundation Models guide](https://www.appcoda.com/foundation-models/), [CreateWithSwift framework exploration](https://www.createwithswift.com/exploring-the-foundation-models-framework/)
- Memory context (HIGH confidence — established project conventions):
  - `schema-version-mutation-footgun.md` — no schema bump in v1.2
  - `xcodeproj-explicit-file-refs.md` — 4 manual pbxproj edits per new .swift file
  - `AccountBalance sign convention` — Decimal money handling

---

*Architecture research for: MyHome v1.2 — Neumorphic Redesign + Analytics + AI Insight*
*Researched: 2026-06-20*
