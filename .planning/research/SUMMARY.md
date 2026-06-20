# Project Research Summary

**Project:** My Home v1.2 — Neumorphic Redesign
**Domain:** iOS personal-finance app — visual redesign milestone (Soft UI design system + Analytics screen + AI Insight card)
**Researched:** 2026-06-20
**Confidence:** HIGH (design system, Swift Charts, FoundationModels availability gating); MEDIUM (FoundationModels latency/guardrail behaviour under real IST load)

---

## Executive Summary

v1.2 is a visual and surface-area milestone on top of a fully shipped, feature-complete app. The goal is to transform My Home from a functional SwiftUI app into a polished Soft UI product using the neumorphic design handoff (`design/design_handoff_myhome_neumorphic/`), while adding three net-new UI surfaces: a "Where it's going" spend donut on Overview, a dedicated Analytics screen (area chart + category bars + delta chips), and an on-device AI Insight card powered by Apple's FoundationModels framework. Every capability is delivered by first-party Apple frameworks — zero new SPM dependencies are added. The deployment target stays at iOS 17.0; FoundationModels is adopted behind a two-layer gate (`#available(iOS 26, *)` plus `SystemLanguageModel.default.availability`) so the AI card is invisibly absent on ineligible devices without affecting anything else.

The recommended build order is strictly dependency-aware: Design System foundation first (tokens + NeuSurface/components + capsule tab bar + RollingMoneyText), then a restyle pass over all existing screens, then the Analytics screen, then the AI Insight card which re-uses the Analytics view model and aggregator. Skipping this order — for example, restyling screens before tokens are stable — causes the entire restyle to be written twice. The most consequential architectural decision is treating `DesignTokens` as a single source of truth: all colors, radii, and shadow values flow from one file so a design token change propagates everywhere without touching 30+ views.

The top risks in v1.2 are accessibility regressions and the FoundationModels finance-safety constraint. Neumorphism's near-surface-color shadows (white at 3.5% opacity) fall below WCAG 1.4.11 for interactive elements; accessibility must be treated as a first-class requirement built into the design-system components from the start, not audited at the end. For the AI card, the model must never compute or derive monetary figures — all rupee amounts, percentages, and deltas must be pre-computed in Swift and injected as literal context, with the model's output verified against those injected facts before display. Both of these risks are avoidable with the correct component design in Phase A.

---

## Key Findings

### Recommended Stack

v1.2 adds no new SPM packages. Every new capability maps to an existing or newly available first-party framework. The neumorphic design system is pure SwiftUI `ViewModifier` / `ShapeStyle` primitives — two `.shadow()` modifiers on a rounded rect are the entire visual effect. Swift Charts `SectorMark` (iOS 17+, already at the deployment floor) and `AreaMark` (iOS 16+) cover all chart types needed. `FoundationModels` is the only genuinely new framework adoption, and it is weak-linked via `#available(iOS 26, *)` so the linker omits it entirely on older devices.

**Core technologies for v1.2:**
- `SwiftUI ViewModifier` + `.shadow()`: neumorphic surface system — two shadow calls per card, wrapped in a reusable `NeuSurface` modifier; no UIKit, no third-party UI library
- `ContentTransition.numericText(value:)` (iOS 17+): rolling-money odometer animation — two lines of SwiftUI, no animation library
- `SwiftUI TabView` + `.toolbar(.hidden, for: .tabBar)` (iOS 16+): floating capsule tab bar — custom `HStack` overlay in ~60 lines
- `Swift Charts SectorMark` (iOS 17+): spend donut on Overview — already used in `DonutChart.swift`; restyle only, no reimplementation
- `Swift Charts AreaMark` + `LineMark` (iOS 16+): Analytics spending trend — existing `SpendOverTimeChart` pattern reused
- `FoundationModels` (iOS 26+, `#available`-gated): AI Insight card — `LanguageModelSession` with `@Generable` output struct; streaming via `streamResponse(to:)` for typewriter reveal
- `DesignTokens` enum (new): single Swift file translating all `tokens.jsx` neuro skin values to typed Color/CGFloat/Shadow constants

**Anti-additions confirmed by research:** No Liquid Glass (`.glassEffect()`), no blur/translucency, no third-party AI, no cloud LLM, no third-party charting library, no deployment-target bump to iOS 26, no SwiftData schema change (SchemaV9 is sufficient).

### Expected Features

**Must have (table stakes):**
- `NeuSurface` ViewModifier with raised / pressed / inset variants — the shadow pair IS the style
- `DesignTokens` enum: all surface colors, text colors, accent, category palette, radii, shadow parameters
- `RollingMoneyText` view: odometer count-up for all hero rupee amounts (~780ms, easeOutCubic)
- Floating capsule tab bar: 62px tall, 34px radius, canary-yellow active pill, spring animation on selection
- Restyle all existing screens (Overview, Activity, Budgets, Notes, Settings, Accounts, Assets, Transfer Inbox)
- "Where it's going" spend donut on Overview: `SectorMark` ring with category segments, grow-in animation, center rolling total, top-4 legend
- Analytics screen: time-range tabs (Week/Month/Year), spend headline + delta chip vs prior period, smooth area chart, by-category horizontal bars with stagger animation
- AI Insight card: availability-gated, typewriter reveal via streaming, breathing orb loading state, graceful fallback when unavailable (section omitted entirely on ineligible devices)

**Should have (differentiators / P2):**
- Donut tap-to-filter: tapping a segment pre-filters the Activity screen to that category
- Scanning dot animation along the area chart line
- Range-aware AI insight specificity (Week insight names days; Month names weeks; Year names worst month)
- Budget gap referenced in AI suggestion ("Skipping one keeps you under budget")

**Defer to v2+:**
- Custom date-range picker on Analytics
- Year-over-year insight requiring multi-year data
- Persistent insight history in SwiftData

### Architecture Approach

The codebase at v1.1 / SchemaV9 has inline styling scattered across all views — no token file, no shared surface modifier. v1.2 adds a `DesignSystem/` folder as a new architectural layer below all features; every view becomes a consumer of tokens, never a producer of hex values. The Analytics screen introduces one new pure-static aggregator (`AnalyticsAggregator`) that mirrors the discipline of the existing `SpendOverTimeAggregator` and `BudgetCalculator` — pure static functions operating on already-fetched arrays, called in SwiftUI `body {}` before any Chart DSL. The AI Insight card introduces one `@Observable` service (`InsightService`) scoped to `AnalyticsView`, following the existing `@Observable` + `@State` service pattern.

**Major new components:**
1. `DesignSystem/DesignTokens.swift` — single source of truth for all visual constants; no view ever hardcodes a hex value
2. `DesignSystem/NeuSurface.swift` — `ViewModifier` with `.raised`, `.pressed`, `.inset` variants; replaces existing `CardStyle`
3. `DesignSystem/NeuTabBar.swift` — floating capsule tab bar replacing native SwiftUI tab bar via `.toolbar(.hidden, for: .tabBar)`
4. `DesignSystem/RollingMoneyText.swift` — animated odometer; Decimal to Double for animation interpolation only; formats from authoritative Decimal at end state
5. `Support/AnalyticsAggregator.swift` — pure static; buckets + delta% + byCategory + `SpendSummary` for AI; reuses `SpendOverTimeAggregator` bucketing, never reimplements it
6. `Features/Analytics/AnalyticsView.swift` — new screen pushed from Overview (not a 6th tab — matches `home.jsx` design intent); owns `InsightService` as `@State`
7. `Features/Analytics/InsightService.swift` — `@Observable`, `@available(iOS 26, *)`, manages session lifecycle, caching, streaming, all error branches
8. `Features/Analytics/AIInsightCard.swift` — conditionally rendered; hidden entirely on ineligible devices

**Modified components:** `RootView` (add NeuTabBar overlay, suppress native tab bar), `CardStyle` (replace with `neuSurface(.raised)` or delete), `CategoryStyle` (extend to use `DesignTokens.catColors`), `DonutChart` (restyle colors, keep chart logic intact), all existing screen views (apply neumorphic tokens).

**No schema change:** SchemaV9 is sufficient throughout. No new `@Model` types, no `VersionedSchema` bump, no typealias risk.

### Critical Pitfalls

1. **Neumorphic contrast failure on interactive elements** — The neuro skin's 3.5% white shadow fails WCAG 1.4.11 for non-text UI components; buttons defined only by shadow depth are invisible to low-contrast users. Prevention: build contrast assertions into `NeuSurface` and `NeuTabBar` from the start; run Xcode Accessibility Inspector with Greyscale filter after every new component; mandate zero Accessibility Inspector warnings as a Phase A exit criterion. The canary yellow (`#FFD60A` = 8:1+ on charcoal) must be used for all active/selected states.

2. **Hallucinated monetary figures in AI Insight** — FoundationModels cannot perform arithmetic; prompting it to compute percentages or rupee amounts produces plausible but factually incorrect numbers that erode user trust in a finance app. Prevention: pre-compute ALL figures in Swift using exact `Decimal` arithmetic inside `AnalyticsAggregator`; inject as literal context strings; use a `@Generable` struct with only a `String` insight field; implement `InsightVerifier` that cross-checks any rupee figure in the output against injected context and falls back to a templated string on mismatch.

3. **Dynamic Type breakage from pixel font sizes** — The design handoff specifies pixel-exact sizes (11px, 13px, 42px). Translating directly to `.font(.system(size: 42))` bypasses Dynamic Type scaling. Prevention: define a `NMFont` enum mapping each design size to the nearest `Font.TextStyle`; use `@ScaledMetric` for derived layout values; include UI snapshot tests at `xsSmall` and `accessibility5` presets in Phase A.

4. **Reduce Motion violations** — Rolling-money odometer, breathing AI orb, and area chart animations must stop when Reduce Motion is enabled. Prevention: create a shared `MotionEnvironment` observable reading `@Environment(\.accessibilityReduceMotion)` at root; every `withAnimation` call site and `animateOnMount` flag must branch on this gate; test by enabling Reduce Motion in Simulator and walking every animated screen.

5. **iOS 26 deployment target trap** — Developer silences FoundationModels compiler errors by raising the deployment target from iOS 17 to iOS 26, instantly dropping all iOS 17–25 devices. Prevention: keep `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; mark `InsightService` with `@available(iOS 26, *)`; use `if #available(iOS 26, *) { ... }` in `AnalyticsView` to conditionally render the AI section; write a unit test verifying all four availability branches.

6. **Missing pbxproj file registrations** — The project uses explicit `PBXFileReference` entries (no synchronized groups). New `.swift` files in `DesignSystem/` and `Features/Analytics/` are silently excluded until 4 manual `project.pbxproj` edits are made per file. Incremental builds may succeed while clean builds fail. Prevention: register every new `.swift` file in the same commit it is created; clean build (`xcodebuild clean build`) is a required exit criterion for every phase.

7. **FoundationModels 4096-token context limit and guardrail false positives** — Verbose prompts with raw expense lists exceed the on-device context window (`exceededContextWindowSize`); finance vocabulary can trigger `guardrailViolation`. Prevention: pre-aggregate to max 8 category totals + 3 top merchants before prompt; implement `PromptBuilder` with 2,048-token budget guard; catch both errors explicitly and fall back to templated string.

---

## Implications for Roadmap

Based on the dependency graph across all four research files, the build order is fixed. The design system is a hard prerequisite — not optional Phase 1 nice-to-have.

### Phase A: Design System Foundation

**Rationale:** All other v1.2 work depends on stable token constants, the `NeuSurface` modifier, and the capsule tab bar. Building any screen before tokens are locked means every color and shadow value gets written twice. This phase also establishes the accessibility and Reduce Motion infrastructure that all subsequent phases inherit automatically.

**Delivers:** Working neumorphic foundation app-wide: `DesignTokens` enum, `NeuSurface` modifier (raised/pressed/inset), `NeuTabBar` capsule overlay, `RollingMoneyText`, `DeltaChip`, `SegmentedRangeBar`, `MotionEnvironment` (Reduce Motion gate), updated `CategoryStyle` with luminous palette, `CardStyle` replaced.

**Features addressed:** NeuSurface/NeuTokens (P1), RollingNumberView (P1), capsule tab bar (P1), typography token definitions.

**Pitfalls to avoid:** Contrast failure (Accessibility Inspector zero-warning check in component tests), Dynamic Type breakage (NMFont enum here), Reduce Motion violations (MotionEnvironment here), shadow performance in lists (single-pass `Canvas` or `compositingGroup` per row, not two `.shadow()` per row in `ForEach`), missing pbxproj registrations (clean build after all 10+ new files added at once).

**Research flag:** Standard patterns — no additional phase research needed.

### Phase B: Restyle Existing Screens

**Rationale:** Restyling all screens in one focused pass immediately after the token foundation is stable prevents token drift. Order within phase: Overview first (most sub-components), then Activity + Expenses, then Budgets, then Notes, then Settings/Accounts/Assets/Transfer Inbox.

**Delivers:** Every screen using neumorphic tokens; no stock SwiftUI system colors visible anywhere; `DonutChart.swift` restyled with luminous category palette and glow (chart logic unchanged); floating tab bar safe-area insets applied to all scroll containers.

**Features addressed:** Full app restyle (P1); `DonutChart.swift` color update (prerequisite for spend donut P1).

**Pitfalls to avoid:** DonutChart clipping — apply `.clipShape` to card container, not the `Chart` view; DonutChart color mismatch — update `DonutSegment.color` in the aggregator, not the view; safe area inset for floating tab bar — all `ScrollView` and `List` containers need `.safeAreaInset(edge: .bottom)` equal to tab bar height + 16pt; clean build after each screen batch.

**Research flag:** Standard patterns — no additional phase research needed.

### Phase C: Analytics Screen

**Rationale:** Analytics is independent of screen restyle (only depends on Phase A tokens) but benefits from seeing the restyled Overview first to confirm design direction before committing Analytics layout. The aggregator must be written and unit-tested before the view is built.

**Delivers:** Full Analytics screen pushed from the Overview Analytics entry row (not a 6th tab — matches `home.jsx` `openAnalytics` callback design intent); `AnalyticsAggregator` with IST-correct date bucketing and prior-period delta; area chart with Catmull-Rom interpolation and peak marker; by-category horizontal bars with stagger animation; time-range tabs (Week/Month/Year); spend headline + delta chip; "Where it's going" spend donut on Overview with grow-in animation; `SpendSummary` struct ready for AI consumption.

**Features addressed:** Analytics screen (all P1 items), spend donut on Overview (P1).

**Pitfalls to avoid:** UTC/IST midnight bucketing — use `Calendar.current` with explicit `timeZone = TimeZone.current`; write `testMidnightISTBucketBoundary` with expenses at 18:29Z and 18:31Z asserting different IST day buckets; never pass `@Query` arrays directly into Chart DSL — aggregate in `body {}` first; Year tab must clip to current month (no future-month zero bars); clean build.

**Research flag:** Standard patterns — `SpendOverTimeAggregator` discipline is proven in the codebase; IST bucketing test is explicitly called out with exact test cases.

### Phase D: AI Insight Card

**Rationale:** Hard dependency on Phase C: `InsightService.refresh()` takes a `SpendSummary` from `AnalyticsAggregator`; the card lives inside `AnalyticsView`. Must come last.

**Delivers:** `InsightService` (`@Observable`, `@available(iOS 26, *)`); `SpendInsight` `@Generable` struct (String-only output fields); streaming generation via `streamResponse(to:)` with typewriter reveal; breathing orb loading state; `InsightVerifier` cross-checking output against injected facts; `PromptBuilder` with 2,048-token budget guard; graceful fallback for all four unavailability cases (section hidden for `deviceNotEligible`, settings CTA for `notEnabled`, skeleton for `modelNotReady`, retry button for generation failure); `prewarm()` called on Analytics screen appear.

**Features addressed:** AI Insight card (P1), typewriter reveal, streaming.

**Pitfalls to avoid:** Finance-AI hallucination — `InsightVerifier` is mandatory before shipping; deployment target trap — `grep IPHONEOS_DEPLOYMENT_TARGET project.pbxproj` must return `17.0`; context window — `PromptBuilderTests.testBudgetWith150Expenses` must pass under 2,048 estimated tokens; guardrail false positives — catch `guardrailViolation` and show templated fallback; latency — use `streamResponse` not blocking `respond`, call `prewarm()` on screen appear; parallel sessions — serialise requests; clean build; verify all four availability branches in unit tests.

**Research flag:** This phase requires knowing whether the dev iPhone is A17 Pro+ for on-device testing. If not, all testing uses a mock `InsightService`. The mock path is straightforward; no additional research needed either way.

### Phase Ordering Rationale

- Phase A must precede everything: no token constants = restyling is written twice; no `MotionEnvironment` = Reduce Motion wired incorrectly in every subsequent view.
- Phases B and C are technically parallelisable after Phase A completes, but B to completion first keeps the restyle concern in one focused context and reduces the risk of a token change in Phase C rippling back into already-restyled views.
- Phase D has a hard dependency on Phase C: `SpendSummary` and `AnalyticsView` must exist before `InsightService` can be wired.
- No schema changes anywhere in v1.2: SchemaV9 is sufficient throughout, eliminating the entire typealias/migration-footgun category.

### Research Flags

**Phases with standard patterns (no research phase needed):**
- Phase A: `ViewModifier` + `.shadow()` is a primitive SwiftUI pattern; neumorphic dual-shadow implementation is thoroughly documented.
- Phase B: Screen restyling is mechanical application of Phase A tokens; no new APIs.
- Phase C: `SpendOverTimeAggregator` pattern is already proven in the codebase; `AreaMark` / `BarMark` are used in v1.0.
- Phase D: FoundationModels implementation pattern is documented with Swift code examples in STACK.md; PITFALLS.md covers every error branch with specific catch clauses.

### Open Questions for Roadmap Planning

1. **Analytics as push from Overview vs. 6th tab.** Research recommends push (matches `home.jsx` `openAnalytics` callback, avoids NeuTabBar layout changes and selectedTab renumbering). Default recommendation: push from Overview. Confirm before finalising Phase C scope.

2. **Dev device Apple Intelligence eligibility.** If Reo's iPhone is not iPhone 15 Pro or later, all Phase D AI testing uses mock `InsightService`. Confirm device before Phase D begins to set correct expectations.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies are first-party Apple frameworks with official documentation; no third-party choices; zero new SPM dependencies |
| Features | HIGH | Design handoff is the authoritative pixel-faithful spec; features map directly to it; must-have / P2 / defer boundaries are clear |
| Architecture | HIGH | Based on direct codebase reading of 187 Swift files at SchemaV9; existing patterns (`SpendOverTimeAggregator`, `@Observable` services, dynamic `@Query` init) are verified and directly reusable |
| Pitfalls | HIGH (neumorphism, Swift Charts, pbxproj); MEDIUM (FoundationModels latency and guardrail behaviour) | Accessibility and shadow performance pitfalls verified against WCAG and community sources; FoundationModels latency benchmarks from community sources, not Apple-published SLAs |

**Overall confidence:** HIGH

### Gaps to Address

- **FoundationModels latency under IST real conditions:** The 2–5 second generation latency and streaming characteristics are from community sources, not Apple-published SLAs. Mitigation: `prewarm()` on screen appear; streaming so first character appears quickly; hard 10-second timeout with templated fallback. No additional research needed — these mitigations are correct regardless of exact latency.

- **Guardrail vocabulary sensitivity with Indian finance terms:** Specific terms that trigger `guardrailViolation` are not documented. Mitigation: neutral framing in prompts, avoid emotionally charged framing, catch `guardrailViolation` with fallback, test with a max-spend month scenario (rent + dining + medical in same month) before shipping Phase D.

- **Dev device Apple Intelligence eligibility:** Unknown at research time. User to confirm before Phase D begins.

---

## Sources

### Primary (HIGH confidence)
- `design/design_handoff_myhome_neumorphic/src/tokens.jsx` — canonical neuro skin token values (surface colors, shadow formulas, accent palette, category colors)
- `design/design_handoff_myhome_neumorphic/src/ui.jsx` — TabBar, Screen, Row components; floating capsule tab bar specification
- `design/design_handoff_myhome_neumorphic/src/analytics.jsx` — Analytics screen, AIInsight card, AreaChart, CategoryBars, LiquidTabs
- `design/design_handoff_myhome_neumorphic/src/home.jsx` — HomeScreen; Analytics entry as push not tab (`openAnalytics` callback)
- `design/design_handoff_myhome_neumorphic/src/motion.jsx` — RollingNumber/RollingMoney animation spec (780ms easeOutCubic)
- Apple Developer Documentation: `SystemLanguageModel`, `LanguageModelSession`, `LanguageModelSession.GenerationError` — availability states, error types, device eligibility
- Apple WWDC25 session 286 "Meet the Foundation Models framework" — capabilities, limitations, 4096-token context window, hardware requirements
- Apple WWDC25 session 248 "Explore prompt design and safety for on-device foundation models" — guardrail behaviour, prompt engineering guidance
- Direct codebase reading: `RootView.swift`, `DonutChart.swift`, `SpendOverTimeAggregator.swift`, `BudgetCalculator.swift`, `OverviewAggregation.swift`, `CardStyle.swift`, `CategoryStyle.swift`, `SchemaV9.swift`, `MyHomeApp.swift`
- Project memory: `xcodeproj-explicit-file-refs.md`, `schema-version-mutation-footgun.md`, `AccountBalance sign convention`

### Secondary (MEDIUM confidence)
- AppCoda "Building Pie Charts and Donut Charts with SwiftUI in iOS 17" — SectorMark iOS 17 availability confirmed
- AppCoda "Getting Started with Foundation Models in iOS 26" — availability gating patterns, graceful degradation
- AzamSharp "The Ultimate Guide to the Foundation Models Framework" — token limits, latency benchmarks, `prewarm()`
- CreateWithSwift "Exploring the Foundation Models Framework" — `@Generable` macro, `@Guide` constrained fields
- Hacking with Swift "How to Build Neumorphic Designs with SwiftUI" — dual-shadow ViewModifier pattern
- Axess Lab "Neumorphism — the accessible and inclusive way" — WCAG 1.4.11 contrast requirements for Soft UI interactive elements
- Medium (Xurxe Toivo Garcia) "For a more accessible Neumorphism" — shadow opacity thresholds for accessibility
- Hacking with Swift Forums "Performance issues when adding shadows to a bunch of views" — `Canvas` / `compositingGroup` mitigation for list row shadows
- Fatbobman "Fixing ScrollView Clipping — Allow Shadows to Overflow in SwiftUI" — chart container clipping prevention
- DEV Community "How to Fall Back Gracefully When Apple Intelligence Isn't Available" — unavailability reason UX patterns

### Tertiary (LOW confidence)
- eleken.co "Fintech UX best practices" — progressive disclosure, contextual insights — informs Analytics screen information hierarchy but not implementation

---
*Research completed: 2026-06-20*
*Milestone: v1.2 Neumorphic Redesign*
*Ready for roadmap: yes*
