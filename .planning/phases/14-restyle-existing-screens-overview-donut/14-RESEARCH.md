# Phase 14: Restyle Existing Screens + Overview Donut — Research

**Researched:** 2026-06-21
**Domain:** SwiftUI neumorphic skin application, Swift Charts SectorMark, pbxproj file registration
**Confidence:** HIGH (all findings verified directly from codebase — no third-party packages)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **SKIN = Neomorphism, NOT Liquid Glass.** DesignTokens/NeuSurface used AS-IS. Do NOT rework toward translucent glass / `backdropFilter` / iOS 26 `glassEffect`. Opaque charcoal surfaces with dual soft shadow are the target material.
- **Tab bar = native iOS, restyled colors only.** NeuTabBar reverted (commit 92e3e61). Do NOT rebuild a custom/floating tab bar. Phase 14 restyles the native bar's accent/tint only. `NeuTabBar.swift` is orphaned — delete it during Phase 14 (needs the 4 manual pbxproj edits).
- **Dark-mode-only retained** (DS-05, single `.preferredColorScheme(.dark)` at app root in `MyHomeApp.swift:34`). Keep.
- **Migrate `CardStyle` → `.neuSurface(.raised)`.** `CardStyle.swift` is a deprecation shim marked "removed in Phase 14". Replace every `.cardStyle()` call site and delete the shim.
- **Hero rupee figures use `RollingMoneyText`** (e.g. net-cash-flow total, donut center, budget left-to-spend).
- **Match the reference layout/content structure** (not material): Overview gets a "NET CASH FLOW" hero card (income/spent split), the "N expenses to review" card, the Analytics push affordance, and the donut. Category icons use the luminous category palette (`DesignTokens.cat*`).

### Claude's Discretion
- (None specified in CONTEXT.md)

### Deferred Ideas (OUT OF SCOPE)
- Liquid Glass skin (explicitly rejected for v1.2).
- Floating/custom tab bar (reverted; native only).
- The dedicated Analytics screen (Phase 15) and AI Insight card (Phase 16).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SKIN-01 | Overview restyled to neumorphic look | OverviewView.swift + WhereItsGoingCard + SpendBudgetCard + PinnedNoteCard fully audited; cardStyle → neuSurface migration map confirmed |
| SKIN-02 | Activity / Expenses (list + add/edit) restyled | ExpenseListView, ExpenseRow, ReviewInboxRow, AddExpenseView, EditExpenseView, DecimalKeypadView, AccountPickerView, CategoryPickerView all audited |
| SKIN-03 | Budgets restyled | BudgetsView, BudgetCategoryCard, BudgetProgressView, EditBudgetSheet, ManageCategoriesView, FilteredExpenseListView audited |
| SKIN-04 | Notes, calendar, and day-agenda restyled | NotesHomeView, NotesListView, NoteRow, AddNoteView, EditNoteView, CalendarView, ReminderEditView, RoutineDetailView audited |
| SKIN-05 | Settings restyled | SettingsView, UnlockView, MigrationReviewSheet audited; icon color map confirmed |
| SKIN-06 | Accounts restyled | AccountsListView, AccountDetailView, EditAccountView audited |
| SKIN-07 | Assets / Net-worth restyled | AssetsListView, AssetDetailView, NetWorthCard, NetWorthTrendChart, StalenessView, AMFISchemePickerView, NPSSchemePickerView, ReconcileView, SIPSetupView, ContributionLogView, EditAssetView audited |
| SKIN-08 | Transfer Inbox and Gmail Review Inbox restyled | TransferPairRow, ReviewInboxRow covered by SKIN-02 audit |
| SKIN-09 | No regression in existing flows | Regression surface fully mapped; pbxproj discipline confirmed |
| OVR-05 | "Where it's going" donut on Overview — current-month top-4 + Others, center total, grow-in, self-transfer exclusion | BudgetCalculator.monthlySpend exclusion pattern confirmed (isTransfer != true); DonutChart.swift API verified |
| OVR-06 | Tapping donut segment navigates to Activity pre-filtered to category | ExpenseListView.CategoryFilter.category(UUID) enum variant confirmed; selectedTab binding pattern available |
</phase_requirements>

---

## Summary

Phase 14 is a broad but mechanical restyle pass: all 67 feature view files get system colors swapped for DesignTokens values and `.cardStyle()` calls replaced with `.neuSurface()`. The design system (DesignTokens, NeuSurface, RollingMoneyText) is fully built and verified in Phase 13 — Phase 14 consumes it without modifying it. There are **no new dependencies**, no schema changes, and no new architectural patterns; the work is token substitution at scale plus one new composable card (`SpendDonutCard.swift`).

The two riskiest sub-tasks are: (1) the Overview rework, which restructures the hero card layout and adds the donut/tap-to-filter flow — this requires understanding the existing `WhereItsGoingCard`, `SpendBudgetCard`, and the `CategoryFilter` navigation pattern in `ExpenseListView`; (2) `CategoryStyle.swift` must be rewritten to map SF Symbol names → `DesignTokens.cat*` colors, replacing 33 stock system color references across all icon tiles.

The self-transfer exclusion for the donut is already implemented in `BudgetCalculator.monthlySpend` (`filter { $0.isTransfer != true }`) — the donut data pipeline must follow the same pattern. The `Expense.isTransfer: Bool?` field on `SchemaV9.Expense` is the canonical flag: `true` = confirmed self-transfer (exclude from spend totals); `nil` = unevaluated; only `false` never appears.

**Primary recommendation:** Split the work into 5 waves: (1) CategoryStyle rewrite + global bg/List/NavigationStack tokens (unblocks all other waves); (2) Overview restyle + new SpendDonutCard + pbxproj registration; (3) Activity/Expenses + Budgets restyle; (4) Notes/Settings/Accounts restyle; (5) Assets restyle + CardStyle/NeuTabBar deletion + build gate.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Token application (colors, spacing) | View layer — each screen | DesignTokens (enum constants) | Purely presentational; no data layer involvement |
| Donut data aggregation | View layer (OverviewMonthContent) | BudgetCalculator support layer | Follows existing `monthlySpend` pattern — in-memory reduce on already-fetched `[Expense]` |
| Self-transfer exclusion in donut | Aggregation (BudgetCalculator pattern) | — | `isTransfer != true` filter, mirroring existing `monthlySpend` and `uncategorizedSpend` |
| Donut tap → category filter | RootView tab binding | ExpenseListView.CategoryFilter | `selectedTab = 1` + category UUID passed via new binding or notification, same as existing deep-link patterns |
| NeuTabBar deletion | pbxproj only | — | File is orphaned; no view currently instantiates `NeuTabBar` (confirmed grep) |
| CardStyle migration | Each call-site view | NeuSurface modifier | 14 call sites across 8 files |

---

## Standard Stack

### Core (all first-party — zero new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | Xcode 26.5 / iOS 17+ | All views | Project standard |
| Swift Charts (`SectorMark`) | Xcode 26.5 | `DonutChart.swift` (already exists) | Used by existing Assets donut; no new import |
| SwiftData | SchemaV9 | `@Query` for expenses | No schema changes this phase |
| DesignTokens.swift | Phase 13 | All token constants | Already built; consumed AS-IS |
| NeuSurface.swift | Phase 13 | `.neuSurface(.raised/.floating/.recessed)` modifier | Already built; consumed AS-IS |
| RollingMoneyText.swift | Phase 13 | Hero money readout (46pt ultraLight rounded, `@ScaledMetric`) | Already built; consumed AS-IS |

### Package Legitimacy Audit

> This phase adds NO external packages. The design system is pure first-party Swift.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Screen Group → File Inventory

This is the canonical mapping for wave planning. Files marked ★ also have `.cardStyle()` call sites to migrate.

### Group 1 — Overview (SKIN-01)
| File | System colors | cardStyle calls | Notes |
|------|--------------|-----------------|-------|
| `Features/Overview/OverviewView.swift` | `systemGroupedBackground`, `systemRed`, `systemOrange`, `.accentColor`, `.secondary`, `.tertiary`, `.primary`, `tertiarySystemFill` | 2 (lines 209, 228) ★ | Also contains `WhereItsGoingCard` + `ReviewBanner` structs — full restyle + donut replacement |
| `Features/Overview/SpendBudgetCard.swift` | `systemGreen`, `systemRed`, `systemOrange`, `systemPink`, `.accentColor` | 1 (line 101) ★ | Hero card — becomes `.neuSurface(.floating)` |
| `Features/Overview/PinnedNoteCard.swift` | `secondarySystemBackground`, `.accentColor` | 0 (but `.background(Color(.secondarySystemBackground))` at line 112) | Migrate `.background` → `.neuSurface(.raised)` |
| `Features/Overview/SpendByCategoryChart.swift` | `secondarySystemBackground`, `.accentColor` | 0 | Remove/replace; this chart may be superseded by SpendDonutCard |
| `Features/Overview/SpendOverTimeChart.swift` | `secondarySystemBackground`, `.accentColor` | 0 | Overview charts to review; may be removed from Overview layout |
| `Features/Overview/TopCategoriesCard.swift` | `secondarySystemBackground` | 0 | May be superseded by SpendDonutCard legend |
| `Features/Overview/OverviewView.swift:293` | — | 1 ★ | ReviewBanner card (`.cardStyle(cornerRadius: 14, padding: 14)`) |
| `Features/Overview/OverviewView.swift:349` | — | 1 ★ | WhereItsGoingCard (`.cardStyle(cornerRadius: 16, padding: 18)`) |

**New file required:**
- `MyHomeApp/Features/Overview/SpendDonutCard.swift` — "Where it's going" card composing `DonutChart`; needs 4 pbxproj edits [VERIFIED: codebase]

### Group 2 — Activity / Expenses (SKIN-02)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Expenses/ExpenseListView.swift` | `.accentColor` | 0 |
| `Features/Expenses/ExpenseRow.swift` | `systemGreen`, `Color(.label)` | 0 |
| `Features/Expenses/ReviewInboxRow.swift` | `systemGreen`, `Color(.label)`, `Color.accentColor` | 0 |
| `Features/Expenses/AddExpenseView.swift` | `systemRed`, `systemGreen`, `secondarySystemBackground`, `.accentColor` | 0 |
| `Features/Expenses/EditExpenseView.swift` | `systemRed`, `systemGreen`, `secondarySystemBackground`, `.accentColor` | 0 |
| `Features/Expenses/DecimalKeypadView.swift` | `secondarySystemBackground` | 0 |
| `Features/Expenses/AccountPickerView.swift` | `systemRed`, `Color.accentColor` | 0 |
| `Features/Expenses/CategoryPickerView.swift` | `systemRed`, `Color.accentColor` | 0 |
| `Features/Expenses/TransferPairRow.swift` | `.tint(.green)` (line 12 doc mentions it) | 0 |

### Group 3 — Budgets (SKIN-03)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Budgets/BudgetsView.swift` | `systemBackground`, `systemRed`, `systemOrange`, `systemGreen`, `tertiarySystemFill` | 3 (lines 211, 258, 304) ★ |
| `Features/Budgets/BudgetCategoryCard.swift` | `systemRed`, `systemOrange`, `tertiarySystemFill`, `tertiaryLabel`, `secondaryLabel` | 1 (line 86) ★ |
| `Features/Budgets/BudgetProgressView.swift` | `secondarySystemBackground`, `systemRed`, `systemOrange`, `.accentColor` | 0 |
| `Features/Budgets/EditBudgetSheet.swift` | `secondarySystemBackground`, `systemRed`, `.accentColor` | 0 |
| `Features/Budgets/ManageCategoriesView.swift` | `systemRed`, `.accentColor` | 0 |
| `Features/Budgets/FilteredExpenseListView.swift` | (audit needed — not in grep output) | 0 |

### Group 4 — Notes / Calendar / Agenda (SKIN-04)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Notes/NotesHomeView.swift` | `systemBackground` | 0 |
| `Features/Notes/NotesListView.swift` | `.accentColor` | 0 |
| `Features/Notes/NoteRow.swift` | `Color.accentColor` | 0 |
| `Features/Notes/AddNoteView.swift` | `.accentColor` | 0 |
| `Features/Notes/EditNoteView.swift` | `Color.accentColor` | 0 |
| `Features/Notes/CalendarView.swift` | `Color.accentColor` | 0 |
| `Features/Notes/ReminderEditView.swift` | `.accentColor`, `tertiarySystemFill` | 0 |
| `Features/Notes/RoutineDetailView.swift` | `systemGreen` | 1 (line 122) ★ |

### Group 5 — Settings (SKIN-05)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Settings/SettingsView.swift` | `systemBlue`, `systemPurple`, `systemIndigo`, `systemRed`, `systemOrange`, `systemGreen`, `.accentColor` | 1 (line 341) ★ |
| `Features/Settings/UnlockView.swift` | `systemBackground`, `.accentColor` | 0 |
| `Features/Settings/MigrationReviewSheet.swift` | `systemRed`, `.accentColor` | 0 |

### Group 6 — Accounts (SKIN-06)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Settings/AccountsListView.swift` | `systemOrange`, `systemBlue`, `systemGreen`, `systemRed`, `.accentColor` | 0 |
| `Features/Settings/AccountDetailView.swift` | `systemRed`, `systemGreen` | 1 (line 156) ★ |
| `Features/Settings/EditAccountView.swift` | `systemRed`, `systemOrange`, `Color.accentColor`, `secondarySystemBackground` | 0 |

### Group 7 — Assets / Net-worth (SKIN-07)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Assets/NetWorthCard.swift` | `systemBlue`, `systemGreen`, `systemOrange` (donut segment colors) | 1 (line 68) ★ |
| `Features/Assets/AssetsListView.swift` | `systemBlue`, `systemGreen`, `systemOrange` | 0 |
| `Features/Assets/AssetDetailView.swift` | `systemGreen`, `systemRed` | 1 (line 153) ★ |
| `Features/Assets/EditAssetView.swift` | `systemRed`, `.accentColor` | 0 |
| `Features/Assets/NetWorthTrendChart.swift` | `Color.accentColor` | 0 |
| `Features/Assets/StalenessView.swift` | `systemOrange` | 0 |
| `Features/Assets/AMFISchemePickerView.swift` | `Color.accentColor` | 0 |
| `Features/Assets/NPSSchemePickerView.swift` | `Color.accentColor` | 0 |
| `Features/Assets/ReconcileView.swift` | `.accentColor` | 0 |
| `Features/Assets/SIPSetupView.swift` | `.accentColor` | 0 |
| `Features/Assets/ContributionLogView.swift` | (audit at build time) | 0 |

### Group 8 — Transfer Inbox (SKIN-08)
| File | System colors | cardStyle calls |
|------|--------------|-----------------|
| `Features/Expenses/TransferPairRow.swift` | `.tint(.green)` — line 12 of docstring confirms this; needs replacement with `DesignTokens.positive` | 0 |

### Group 9 — Gmail Review Inbox (SKIN-08 continued)
Covered by the `ReviewInboxRow.swift` changes in Group 2. No separate screen file.

### Shared components requiring restyle
| File | System colors | Note |
|------|--------------|------|
| `Features/Shared/CategoryStyle.swift` | All 33 `Color(.system*)` in palette and bySymbol dict | Full rewrite: swap system colors → `DesignTokens.cat*` per symbol name; hashed fallback → `DesignTokens.catOther` |
| `Features/Shared/CardStyle.swift` | `secondarySystemBackground` | DELETE this file after migrating all 14 call sites |
| `Features/Shared/StackBar.swift` | `tertiarySystemFill` | Replace with `DesignTokens.fillRecessed` |
| `Support/BudgetCalculator.swift` | Comments reference `Color.accentColor` etc. — code-only comments, not live color usage | Comments only; update wording, no code change |
| `DesignSystem/NeuTabBar.swift` | Not a system-color issue — DELETE this file | Orphaned (grep confirms: only referenced in its own file + Preview) |

---

## Design System Surface (Verified API)

[VERIFIED: codebase direct read]

### DesignTokens.swift — complete token inventory

**Canvas & Surface:**
- `DesignTokens.bgCanvas` = `#1C1C23` — ScrollView/List/NavigationStack background
- `DesignTokens.surfaceRaised` = `#1F1F27` — standard card fill (`.raised` state)
- `DesignTokens.surfaceRaisedStrong` = `#22222C` — hero card fill (`.floating` state)
- `DesignTokens.surfaceElevatedControl` = `#262630` — segmented control track, keypad key
- `DesignTokens.fillRecessed` = `#16161C` — search bar bg, input field bg
- `DesignTokens.fillRecessed2` = `#191920` — progress bar track
- `DesignTokens.fillRecessed3` = `#15151B` — `.recessed` surface fill

**Accent & Semantic:**
- `DesignTokens.accent` = `#FFD60A` (canary yellow)
- `DesignTokens.accentSoft` = `#FFD60A` at 16% opacity
- `DesignTokens.accentOnYellow` = `#1A1404` (dark text on yellow bg)
- `DesignTokens.positive` = `#34E29B` (income, positive net)
- `DesignTokens.negative` = `#FF6B6B` (spend, over-budget, destructive)
- `DesignTokens.orange` = `#FFB020` (warning, pinned note, overdue)

**Labels:**
- `DesignTokens.label` = `#ECEDF4` (100% — primary text)
- `DesignTokens.label2` = `#DCDFEE` at 56% opacity (secondary)
- `DesignTokens.label3` = `#DCDFEE` at 32% opacity (tertiary)
- `DesignTokens.label4` = `#DCDFEE` at 16% opacity (ghost/disabled)

**Separators:**
- `DesignTokens.separatorHairline` = white 5% opacity
- `DesignTokens.glassBorder` = white 2.5% opacity

**Category Palette (for icon tiles and donut segments):**
- `catGroceries` = `#2DD4BF`, `catDining` = `#FB923C`, `catFuel` = `#F472B6`
- `catUtilities` = `#7DD3FC`, `catRent` = `#818CF8`, `catAuto` = `#38BDF8`
- `catShopping` = `#E879F9`, `catHealth` = `#A78BFA`, `catSubscriptions` = `#22D3EE`
- `catEntertainment` = `#C084FC`, `catOther` = `#94A3B8`

**Geometry:**
- `DesignTokens.radiusCard` = 26pt (default for `.neuSurface`)
- `DesignTokens.radiusInner` = 20pt
- `DesignTokens.radiusPill` = 999pt
- `DesignTokens.spacing4/8/12/16/22/24/32/48` (pt)

**Animations:**
- `DesignTokens.springBouncy` — `.spring(response: 0.4, dampingFraction: 0.65)`
- `DesignTokens.springSoft` — `.spring(response: 0.4, dampingFraction: 0.90)`

### NeuSurface.swift — modifier API

```swift
// View extension (source: NeuSurface.swift lines 194–201)
func neuSurface(
    _ state: NeuSurfaceState,                // .raised / .floating / .recessed
    radius: CGFloat = DesignTokens.radiusCard, // 26pt default
    padding: CGFloat? = 16,                  // nil = caller handles padding
    isInteractive: Bool = false              // true = adds glassBorder WCAG affordance
) -> some View
```

State semantics:
- `.raised` — standard card (surfaceRaised fill + dual outer shadow + inner rim)
- `.floating` — hero card (surfaceRaisedStrong fill + deeper dual shadow + inner rim)
- `.recessed` — input well (fillRecessed3 fill + overlay gradient inset; NO outer shadow)

### RollingMoneyText.swift — API

```swift
// Source: RollingMoneyText.swift lines 29–61
struct RollingMoneyText: View {
    let amount: Decimal
    var currencyCode: String = "INR"
    var locale: Locale = Locale(identifier: "en_IN")
    var color: Color = DesignTokens.label
    var animationDuration: Double = 0.78
    // Internal @ScaledMetric base = 46pt anchored to .largeTitle — NOT configurable via API
}
```

**Critical constraint:** `RollingMoneyText` always renders at its internal 46pt base (scaled by user's Dynamic Type). For the donut center (21pt target), do NOT use `RollingMoneyText`. Instead use:

```swift
// Source: 14-UI-SPEC.md donut center spec + RollingMoneyText.swift preview (lines 85-88)
Text(amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
    .font(.system(size: 21, weight: .light, design: .rounded))
    .foregroundStyle(DesignTokens.label)
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(.smooth(duration: 0.78), value: amount)
```

### DonutChart.swift — existing API

```swift
// Source: Features/Shared/DonutChart.swift lines 17-48
struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

struct DonutChart<Center: View>: View {
    let segments: [DonutSegment]
    var innerRatio: CGFloat = 0.62
    var size: CGFloat = 132
    @ViewBuilder var center: () -> Center
}
// Also: init(segments:innerRatio:size:) overload for EmptyView center
```

DonutChart is marked `.accessibilityHidden(true)` — legend rows MUST carry `.accessibilityLabel` instead.

### CategoryStyle.swift — current state and required rewrite

Currently maps SF Symbol names → `Color(.system*)` values. **Must be fully rewritten** to map the same symbol names → `DesignTokens.cat*`:

```swift
// Source: Features/Shared/CategoryStyle.swift lines 22-38 (CURRENT — to be replaced)
"cart"      → Color(.systemGreen)    // Groceries → DesignTokens.catGroceries
"fork.knife"→ Color(.systemOrange)   // Dining    → DesignTokens.catDining
"fuelpump"  → Color(.systemRed)      // Fuel      → DesignTokens.catFuel
"bolt"      → Color(.systemYellow)   // Utilities → DesignTokens.catUtilities
"house"     → Color(.systemIndigo)   // Rent      → DesignTokens.catRent
"car"       → Color(.systemTeal)     // Auto      → DesignTokens.catAuto
"bag"       → Color(.systemPink)     // Shopping  → DesignTokens.catShopping
"cross.case"→ Color(.systemPurple)   // Health    → DesignTokens.catHealth
"film"      → Color(.systemMint)     // Entertainment → DesignTokens.catEntertainment
"antenna.radiowaves.left.and.right" → (Subscriptions → DesignTokens.catSubscriptions)
// fallback palette[idx] → DesignTokens.catOther
// nil category → DesignTokens.catOther
```

The IconTile component reads from `CategoryStyle`, so rewriting `CategoryStyle` propagates the neumorphic palette to every category icon tile across all screens.

---

## Stock-Color / CardStyle Audit Summary

[VERIFIED: codebase grep]

**Total system color occurrences (excl. CardStyle.swift):** ~121 lines across **33 unique files**

**cardStyle() call sites to migrate:** 14 across 8 files:
1. `OverviewView.swift:209` → `.neuSurface(.raised)`
2. `OverviewView.swift:228` → `.neuSurface(.raised, padding: nil)`
3. `OverviewView.swift:293` → `.neuSurface(.raised, radius: 20, padding: 14)` (ReviewBanner)
4. `OverviewView.swift:349` → `.neuSurface(.raised, padding: 18)` (WhereItsGoingCard — will be replaced by SpendDonutCard)
5. `SpendBudgetCard.swift:101` → `.neuSurface(.floating, padding: 18)` (hero)
6. `BudgetsView.swift:211` → `.neuSurface(.raised, radius: 20)`
7. `BudgetsView.swift:258` → `.neuSurface(.floating, padding: 22)` (budget summary ring hero)
8. `BudgetsView.swift:304` → `.neuSurface(.raised, padding: 20)`
9. `BudgetCategoryCard.swift:86` → `.neuSurface(.raised, radius: 20, padding: 15)`
10. `NetWorthCard.swift:68` → `.neuSurface(.floating, padding: 18)` (hero)
11. `AccountDetailView.swift:156` → `.neuSurface(.floating)` (detail header hero)
12. `AssetDetailView.swift:153` → `.neuSurface(.floating)` (detail header hero)
13. `RoutineDetailView.swift:122` → `.neuSurface(.raised)`
14. `SettingsView.swift:341` → `.neuSurface(.raised, radius: 20)`

**Additional `.primary` / `.secondary` / `.tertiary` foreground usages:** ~209 occurrences in feature files — these must be replaced with `DesignTokens.label`, `label2`, `label3` respectively per the UI-SPEC global rules.

**Files to DELETE (require 4 manual pbxproj edits each):**
- `MyHomeApp/DesignSystem/NeuTabBar.swift` — orphaned, zero non-self references [VERIFIED: grep]
- `MyHomeApp/Features/Shared/CardStyle.swift` — deprecation shim, all call sites migrated in this phase

---

## Architecture Patterns

### System Architecture Diagram

```
User Tap / App Open
        │
        ▼
  MyHomeApp.swift ──────────────────────── .preferredColorScheme(.dark) [one root]
        │
        ▼
   RootView.swift ──── TabView.tint(DesignTokens.accent) [Phase 14 change]
        │
   ┌────┴────────────────────────────────────────────────┐
   │  5 tabs (tag 0-4)                                   │
   ▼                                                     ▼
OverviewView          ExpenseListView / BudgetsView / NotesHomeView / SettingsView
   │                         │
   │  @Query monthExpenses   │  CategoryFilter.category(UUID) ← OVR-06 target
   │  (isTransfer != true)   │  @State categoryFilter
   │                         │
   ▼                         ▼
SpendDonutCard (NEW)    filtered daySections
   │
   ├─ DonutChart.swift (existing Swift Charts SectorMark)
   │    segments: top-4 DesignTokens.cat* + Others
   │    center: 21pt Text with .contentTransition(.numericText)
   │
   └─ Legend rows (Button) ──── tap ──→ selectedTab = 1
                                         (OVR-06: navigate Activity pre-filtered)
```

**OVR-06 navigation pattern** — OverviewView already passes `selectedTab: $selectedTab` binding through. The same binding is the mechanism for all existing "See all" buttons and the ReviewBanner. `SpendDonutCard` receives `selectedTab` + a new `onCategoryTap: (UUID?) -> Void` closure that callers use to set the Activity filter before switching tabs. ExpenseListView's `categoryFilter` must be promoted from `@State` (internal) to a binding or the navigation must use a shared `@State` in RootView.

**Recommended approach for OVR-06:** Add `@State private var activityCategoryFilter: UUID? = nil` to `RootView` and pass it as a `Binding<UUID?>` to both `OverviewView` (write) and `ExpenseListView` (read). This mirrors the existing `deepLinkNoteID` pattern in RootView and avoids changing the `CategoryFilter` enum's access level. [ASSUMED — alternative is Notification-based deep link like `kOpenNoteNotification`; either approach is valid]

### CardStyle Migration Map (verified from codebase)

All 14 sites are enumerated above. After migration:
1. Confirm zero `import` or usage of `CardStyle` anywhere (grep will verify)
2. Delete `CardStyle.swift` file
3. Remove 4 pbxproj entries for `CardStyle.swift`

### NeuTabBar Deletion

`NeuTabBar` is referenced **only within `NeuTabBar.swift` itself** (its own `#Preview`). No other file uses it. [VERIFIED: grep]

The only Phase 14 tab bar change is:
```swift
// RootView.swift — TabView block (line 66)
// Add after the closing brace of the last .tag(4) line:
.tint(DesignTokens.accent)
```

### Recommended Project Structure (no changes)

```
MyHomeApp/
├── DesignSystem/          # Phase 13 — consumed AS-IS; NeuTabBar.swift deleted
│   ├── DesignTokens.swift
│   ├── NeuSurface.swift
│   └── RollingMoneyText.swift
├── Features/
│   ├── Overview/
│   │   └── SpendDonutCard.swift  ← NEW (needs 4 pbxproj edits)
│   └── Shared/
│       ├── CategoryStyle.swift   ← rewritten (existing file; no pbxproj edit needed)
│       └── CardStyle.swift       ← DELETED (needs 4 pbxproj edits for removal)
```

---

## Donut Implementation Detail (OVR-05/06)

### Data pipeline (self-transfer exclusion)

The existing `WhereItsGoingCard` in `OverviewView.swift` (lines 301-351) already receives `ranked: [(category: Category, spent: Decimal)]` computed in `OverviewMonthContent.body` (line 136-141). That computation uses `BudgetCalculator.monthlySpend` which applies `filter { $0.isTransfer != true }` (line 79 of `BudgetCalculator.swift`). [VERIFIED: codebase]

The `isTransfer: Bool?` field on `SchemaV9.Expense` (line 120) encodes:
- `nil` = not evaluated (unevaluated by scorer)
- `true` = confirmed self-transfer (EXCLUDE from spend totals)
- (value `false` never set per Phase 10 logic)

**The existing ranked computation already excludes confirmed self-transfers.** `SpendDonutCard` can receive the same `ranked` and `total` parameters without any new filtering logic.

### Segment preparation

```swift
// In SpendDonutCard, mapping categories → DesignTokens colors
private func segmentColor(for category: Category) -> Color {
    // CategoryStyle.color(for:) will return DesignTokens.cat* after the rewrite
    return CategoryStyle.color(for: category)
}

// "Others" segment = ranked[4...].reduce(.zero) { $0 + $1.spent }
```

Minimum segment count: if < 2 categories have spend, show single neutral ring with `DesignTokens.catOther`.

### Tap-to-filter navigation (OVR-06)

`ExpenseListView.CategoryFilter` is a `private enum` with `case category(UUID)`. To drive it from Overview:
- `ExpenseListView` needs to accept an optional `Binding<UUID?>` parameter for the pre-filter
- Or: `categoryFilter` state is lifted to `RootView` and passed down

The existing `selectedTab: $selectedTab` binding in `OverviewView` init and `OverviewMonthContent` init demonstrates the exact pattern to follow. [VERIFIED: RootView.swift + OverviewView.swift]

---

## pbxproj Discipline

[VERIFIED: project memory + codebase — no synchronized groups exist]

**The project uses explicit file references only.** Every new `.swift` file requires exactly **4 manual edits** in `MyHome.xcodeproj/project.pbxproj`:

1. **PBXFileReference** — add a file reference entry (UUID + path + sourceTree)
2. **PBXBuildFile** — add a build file entry that references the PBXFileReference UUID
3. **PBXSourcesBuildPhase** — add the PBXBuildFile UUID to the Sources phase `files` array
4. **PBXGroup** — add the PBXFileReference UUID to the appropriate group's `children` array

**Files requiring ADD edits (Phase 14):**
- `MyHomeApp/Features/Overview/SpendDonutCard.swift` — 1 new file, 4 edits

**Files requiring REMOVE edits (Phase 14):**
- `MyHomeApp/DesignSystem/NeuTabBar.swift` — 4 removal edits (inverse of above)
- `MyHomeApp/Features/Shared/CardStyle.swift` — 4 removal edits

**Total pbxproj edits:** 12 (4 add + 4+4 remove)

Build verification command: `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' | tail -5`

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Donut chart | SVG-based ring / CGPath drawing | `DonutChart.swift` (existing `SectorMark`) | Already built in Phase 13 for Assets screen; uses Swift Charts |
| Category colors | Hardcoded hex per category | `CategoryStyle.color(for:)` after rewrite | Single source of truth; hashed fallback handles custom categories |
| Animated money | Custom `AnimatableModifier` or `withAnimation` on String | `RollingMoneyText` (46pt hero) or `Text + .contentTransition(.numericText())` (21pt stat) | Already built; honors Reduce Motion |
| Surface shadow | Inline `.shadow()` per card | `.neuSurface(.raised/.floating/.recessed)` | Phase 13 work; dual shadow spec baked in |
| Tab bar accent | `UITabBarAppearance` customization | `.tint(DesignTokens.accent)` on `TabView` | Single modifier; appearance APIs are unnecessary here |
| pbxproj edits | Xcode "Add Files" dialog (unreliable for agents) | Direct text edits with 4 manual pbxproj changes | Xcode groups are not synchronized; the dialog doesn't always register correctly |

---

## Common Pitfalls

### Pitfall 1: `.primary` / `.secondary` / `.tertiary` are light-adaptive
**What goes wrong:** Leaving `.foregroundStyle(.primary)` or `.foregroundStyle(.secondary)` in any view file — these use system adaptive colors that are white in dark mode but do not match `DesignTokens.label` exactly. They also ignore the neumorphic label tier hierarchy.
**Why it happens:** SwiftUI's semantic colors look correct at a glance in dark mode but fail the color-system requirement (all text must flow through `DesignTokens.label/label2/label3/label4`).
**How to avoid:** Treat `.primary`, `.secondary`, `.tertiary` as system colors that must be replaced — same discipline as `Color(.secondarySystemBackground)`.
**Warning signs:** ~209 occurrences remain after the grep — each requires replacement.

### Pitfall 2: Clipping shadows with `.clipShape` or `.clipped`
**What goes wrong:** Adding `.clipped()` to the donut card container clips the dual outer shadow, making the neumorphic depth effect invisible.
**Why it happens:** `NeuSurface.swift` applies `clipShape` internally on the background fill layer; adding another `.clipped()` on the outer container cancels the shadow.
**How to avoid:** Never add `.clipped()` or `.clipShape()` as an outer modifier on a `.neuSurface()`-wrapped view. The `NeuSurface` modifier handles all clipping internally.
**Warning signs:** Shadow looks flat or absent.

### Pitfall 3: Missing pbxproj edits for SpendDonutCard.swift
**What goes wrong:** `SpendDonutCard.swift` compiles fine in Preview but the build fails with "cannot find type 'SpendDonutCard' in scope" because the file is not registered in PBXSourcesBuildPhase.
**Why it happens:** No synchronized groups; Xcode does not auto-discover new files.
**How to avoid:** The 4 pbxproj edits must be in the SAME commit as the new file. The build gate (xcodebuild clean build) will catch this if the edits are missing.
**Warning signs:** Build succeeds locally in Xcode (which does auto-discover for the open project) but fails in clean CLI build.

### Pitfall 4: Self-transfer inclusion in donut totals
**What goes wrong:** Showing inflated spend in the donut by counting confirmed self-transfers as real expenses.
**Why it happens:** A naive `@Query` of all month expenses includes confirmed transfers (`isTransfer == true`).
**How to avoid:** Use the existing `BudgetCalculator.monthlySpend(for:categories:)` which already has `filter { $0.isTransfer != true }` on line 79. Pass the already-computed `rankedSpend` from `OverviewMonthContent` into `SpendDonutCard` — no additional filtering needed.
**Warning signs:** Donut shows transfer amounts in categories that don't match real spending.

### Pitfall 5: RollingMoneyText font size not configurable
**What goes wrong:** Trying to pass a `fontSize` or `font` parameter to `RollingMoneyText` for the 21pt donut center stat — this parameter doesn't exist.
**Why it happens:** RollingMoneyText uses `@ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46` — it's always 46pt (scaled). The parameter is intentionally private per DS-06 Dynamic Type compliance.
**How to avoid:** For non-46pt money text, use `Text + .contentTransition(.numericText())` pattern directly. See the Code Examples section below.
**Warning signs:** Compiler error "extra argument 'font' in call" or layout overflow in donut center.

### Pitfall 6: isTransfer predicate in @Query
**What goes wrong:** Trying to filter `isTransfer == false` in a `#Predicate` — optional Bool predicates are unreliable in SwiftData (known pattern from Phase 10).
**Why it happens:** SwiftData's `#Predicate` macros have known issues with `Bool?` comparisons.
**How to avoid:** Use in-memory filter after fetching, as `BudgetCalculator` already does. Never add `isTransfer == false` to a `#Predicate`.
**Warning signs:** Predicate compile errors or runtime crashes.

### Pitfall 7: CategoryStyle.swift rewrite loses custom categories
**What goes wrong:** After rewriting `CategoryStyle` to use `DesignTokens.cat*`, user-created categories with custom symbol names don't match any entry in `bySymbol` and fall through to the hashed fallback.
**Why it happens:** The hashed fallback currently returns `Color(.systemX)` — after rewrite it must return `DesignTokens.catOther`.
**How to avoid:** After the bySymbol rewrite, update the fallback `return palette[idx]` to use a `DesignTokens.cat*` palette array (11 colors), or use `DesignTokens.catOther` as the universal fallback for unknown symbols.

---

## Code Examples

### NeuSurface usage (all three states)
```swift
// Source: NeuSurface.swift lines 206-246 (Preview) + UI-SPEC
// Standard card
someView
    .neuSurface(.raised)

// Hero card (net-cash-flow, budget summary ring, account/asset detail headers)
someView
    .neuSurface(.floating, padding: 18)

// Tappable card (adds glassBorder WCAG affordance)
Button { action() } label: { someView }
    .neuSurface(.raised, isInteractive: true)

// Input well / progress track
someView
    .neuSurface(.recessed, radius: DesignTokens.radiusInner)
```

### 21pt rolling stat (donut center, income/spent tiles)
```swift
// Source: RollingMoneyText.swift preview lines 85-88 + UI-SPEC donut center spec
@State private var totalSpend: Decimal = 0

Text(totalSpend.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
    .font(.system(size: 21, weight: .light, design: .rounded))
    .foregroundStyle(DesignTokens.label)
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(.smooth(duration: 0.78), value: totalSpend)
```

### List + NavigationStack background (global rule)
```swift
// Source: UI-SPEC "Global Rules" — apply to every screen
List { ... }
    .scrollContentBackground(.hidden)
    .background(DesignTokens.bgCanvas)

ScrollView { ... }
    .background(DesignTokens.bgCanvas)

// List row backgrounds
.listRowBackground(DesignTokens.surfaceRaised)
```

### TabView tint (RootView change — the only native tab bar change)
```swift
// Source: RootView.swift line 66 + UI-SPEC "Native Tab Bar Restyle"
TabView(selection: $selectedTab) { ... }
    .tint(DesignTokens.accent)
```

### Donut segment + tap (SpendDonutCard skeleton)
```swift
// Source: DonutChart.swift + UI-SPEC Donut spec
struct SpendDonutCard: View {
    let ranked: [(category: Category, spent: Decimal)]
    let total: Decimal
    let onCategoryTap: (UUID?) -> Void  // nil = "Others"

    var body: some View {
        HStack(spacing: 18) {
            DonutChart(segments: segments, size: 132) {
                // Center overlay (21pt stat, not RollingMoneyText)
                VStack(spacing: 2) {
                    Text("SPENT")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(DesignTokens.label2)
                    Text(total.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
                        .font(.system(size: 21, weight: .light, design: .rounded))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            // Legend rows
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
                    .accessibilityLabel("\(item.label): ₹\(item.amount.formattedINRWhole())")
                }
            }
        }
        .neuSurface(.raised, padding: 18)
        // No .clipped() here — shadow must be visible
    }
}
```

---

## Runtime State Inventory

> This is NOT a rename/refactor/migration phase. No runtime state changes. [VERIFIED: CONTEXT.md scope fence — schema stays SchemaV9, no string renames]

**Nothing found in any category** — Phase 14 is presentational only; no stored data, live service config, OS-registered state, secrets, or build artifacts change.

---

## Navigation / Deep-Link Regression Surface

[VERIFIED: RootView.swift + OverviewView.swift]

| Flow | Anchored in | Phase 14 risk |
|------|------------|---------------|
| Expense CRUD (Add/Edit/Delete) | `AddExpenseView`, `EditExpenseView`, `ExpenseListView` | Low — restyle only; no data path changes |
| Note CRUD | `AddNoteView`, `EditNoteView`, `NotesListView` | Low — restyle only |
| `kOpenNoteNotification` deep-link | `RootView.swift:110` — `selectedTab = 3` | None — not touched |
| `kOpenReconcileNotification` deep-link | `RootView.swift:120` — `deepLinkReconcileSIPID` | None — not touched |
| Face ID gate | `LockController`, `UnlockView` | Low — `UnlockView` gets restyle but no logic change |
| Gmail sync | `GmailSyncController`, `scenePhase.onChange` in RootView | None — not touched |
| Self-transfer confirm | `TransferPairRow`, `EditExpenseView.applyTransferMark` | Low — `TransferPairRow` gets restyle; logic unchanged |
| Account balance (sign convention) | `AccountBalance.swift`, `BudgetCalculator.swift` | None — not touched |
| SIP/NPS nav | `AMFINavService`, `NPSNavService`, `ReconcileView` | Low — restyle only on `ReconcileView` |
| Tab deep-link from Overview | `selectedTab` binding via `OverviewView` | Medium — `SpendDonutCard` tap adds a new path; the binding must be threaded through |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build | ✓ (per project memory) | 26.5 | — |
| iPhone 17 Simulator | Testing | ✓ (per project memory) | iOS 26.5 | — |
| Swift Charts | DonutChart.swift | ✓ (already in project) | Xcode 26.5 | — |
| SwiftData SchemaV9 | @Query expense queries | ✓ | V9 | — |

No missing dependencies. This phase is first-party only.

---

## Validation Architecture

> `workflow.nyquist_validation: true` in `.planning/config.json` — section REQUIRED.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Swift) — existing test targets |
| Config file | `MyHomeApp.xcodeproj` test scheme |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -testPlan MyHomeTests 2>&1 | tail -20` |
| Full suite command | Same (no test plan separation in project) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OVR-05 | Donut data excludes `isTransfer == true` expenses | unit | `xcodebuild test ... -only-testing:MyHomeTests/DonutAggregationTests` | ❌ Wave 0 |
| OVR-05 | "Others" roll-up = all categories beyond top-4 | unit | same | ❌ Wave 0 |
| OVR-05 | Zero-spend month shows empty state (no crash) | unit | same | ❌ Wave 0 |
| OVR-06 | Tapping segment calls `onCategoryTap` with correct UUID | unit | `xcodebuild test ... -only-testing:MyHomeTests/SpendDonutCardTests` | ❌ Wave 0 |
| SKIN-09 | Clean build with zero "cannot find type" errors | build | `xcodebuild clean build -scheme MyHome ... | tail -5` | N/A |
| SKIN-09 | Self-transfer confirm still works after restyle | manual | Simulator smoke test | N/A |

### Sampling Rate
- **Per task commit:** Build check — `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5`
- **Per wave merge:** Full test suite + build
- **Phase gate:** Full suite green + human-verify simulator walk-through before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `MyHomeAppTests/DonutAggregationTests.swift` — covers OVR-05 (self-transfer exclusion, Others roll-up, zero-spend empty state)
- [ ] `MyHomeAppTests/SpendDonutCardTests.swift` — covers OVR-06 (tap callback with correct UUID)

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` in `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 14 does not change auth flows; Face ID gate untouched |
| V3 Session Management | No | No session changes |
| V4 Access Control | No | No access control changes |
| V5 Input Validation | No | No new user inputs (restyle only) |
| V6 Cryptography | No | No new crypto |

### Known Threat Patterns

No new threat surface introduced. Phase 14 is presentational (color/layout changes) with no new network calls, storage writes, or user input paths. The only security-adjacent consideration: `UnlockView` restyle must not accidentally dismiss the lock overlay — verified by keeping the conditional `if lockController.isLocked && lockController.lockEnabled` wrapper unchanged.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | OVR-06 implemented by lifting `categoryFilter` from `@State` inside `ExpenseListView` to a `Binding<UUID?>` in `RootView`, mirroring the `deepLinkNoteID` pattern | Architecture Patterns / OVR-06 navigation | If ExpenseListView's internal enum can't cleanly accept an external binding, a Notification-based approach (like `kOpenNoteNotification`) would be needed instead — minor rework, not a blocker |
| A2 | `FilteredExpenseListView.swift` in Budgets group has no system color occurrences (not in grep output) | Screen Group Inventory | If wrong, 1-2 additional system color fixes needed — low impact |
| A3 | `ContributionLogView.swift` in Assets group has no system color occurrences (not in grep output) | Screen Group Inventory | Same — low impact |

**All other claims are verified directly from codebase reads.**

---

## Open Questions

1. **OverviewView layout restructure scope**
   - What we know: Current `OverviewView` renders `SpendBudgetCard` (hero), optional `ReviewBanner`, optional `NetWorthCard`, existing `WhereItsGoingCard` (old donut), optional Budgets glance, Recent list.
   - What's unclear: The new UI-SPEC (14-UI-SPEC.md) calls for a "NET CASH FLOW hero card" (income/spent split tiles) instead of the existing `SpendBudgetCard` + stacked bar. The existing `SpendBudgetCard` shows spend vs budget with a stacked bar — this does NOT match the new spec's income/spent split with `DesignTokens.positive`/`negative` tiles. The planner must decide: (a) restyle `SpendBudgetCard` to the new income/spent layout (significant internal change), or (b) treat the existing content structure as canonical and only apply tokens (simpler). CONTEXT.md says "match the reference layout/content structure" — this implies the income/spent split IS required.
   - Recommendation: Plan explicitly for replacing `SpendBudgetCard.swift`'s internal layout with the NET CASH FLOW income/spent split pattern from UI-SPEC Screen 1. This is the largest single-screen change in the phase.

2. **SpendByCategoryChart + SpendOverTimeChart disposition**
   - What we know: Both exist in `Features/Overview/` and have `secondarySystemBackground` usages. The new Overview layout per UI-SPEC shows the donut card but not a category bar chart or a time-series chart on the Overview screen.
   - What's unclear: Are these charts retained (possibly still shown, just restyled) or deleted?
   - Recommendation: Plan to restyle both (remove system colors) but mark them as candidates for removal in Phase 15 when Analytics screen is built. Retain for now to avoid regression if any path references them.

---

## Sources

### Primary (HIGH confidence — codebase direct reads)
- `MyHomeApp/DesignSystem/DesignTokens.swift` — complete token inventory
- `MyHomeApp/DesignSystem/NeuSurface.swift` — modifier API and state enum
- `MyHomeApp/DesignSystem/RollingMoneyText.swift` — API, `@ScaledMetric` constraint
- `MyHomeApp/Features/Shared/DonutChart.swift` — `DonutSegment` + `DonutChart<Center>` API
- `MyHomeApp/Features/Shared/CategoryStyle.swift` — current system color mappings (to be replaced)
- `MyHomeApp/Features/Shared/CardStyle.swift` — confirmed deprecation shim with 0 non-call-site references
- `MyHomeApp/RootView.swift` — `TabView`, deep-link patterns, `selectedTab` binding
- `MyHomeApp/Features/Overview/OverviewView.swift` — existing `WhereItsGoingCard`, card layout, navigation
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — `CategoryFilter` enum, filter binding patterns
- `MyHomeApp/Support/BudgetCalculator.swift` — `isTransfer != true` exclusion on lines 79, 94
- `MyHomeApp/Persistence/Schema/SchemaV9.swift:120` — `isTransfer: Bool?` field definition
- `MyHomeApp/DesignSystem/NeuTabBar.swift` — confirmed orphaned (grep: zero references outside self)
- `.planning/phases/14-restyle-existing-screens-overview-donut/14-CONTEXT.md` — locked decisions
- `.planning/phases/14-restyle-existing-screens-overview-donut/14-UI-SPEC.md` — full per-screen restyle contract
- `.planning/REQUIREMENTS.md` — SKIN-01…09, OVR-05, OVR-06 definitions
- `.planning/config.json` — nyquist_validation: true, security_enforcement: true

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — Phase 13/14 decision history, pbxproj discipline note
- `.planning/ROADMAP.md` — Phase 14 success criteria

---

## Metadata

**Confidence breakdown:**
- Screen group inventory: HIGH — verified by direct file listing and grep
- System color count (121 lines, 33 files): HIGH — grep verified
- cardStyle call sites (14 across 8 files): HIGH — grep verified
- NeuTabBar orphaned status: HIGH — grep confirms zero non-self references
- Design system API: HIGH — source files read directly
- Self-transfer exclusion pattern: HIGH — BudgetCalculator.swift line 79 confirmed
- OVR-06 navigation approach: MEDIUM (A1 above) — pattern inferred from existing deep-link precedents

**Research date:** 2026-06-21
**Valid until:** Phase 14 complete (this is a closed phase — no external dependencies to expire)
