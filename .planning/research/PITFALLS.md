# Pitfalls Research

**Domain:** Adding Neumorphic design system + Apple FoundationModels AI + Swift Charts Analytics to an existing Swift 6.2 / SwiftUI / SwiftData iOS finance app (My Home v1.2)
**Researched:** 2026-06-20
**Confidence:** HIGH (neumorphism accessibility, FoundationModels availability/errors, Swift Charts API); MEDIUM (shadow performance at this specific scale, AI latency under real IST load)

---

## Critical Pitfalls

### Pitfall 1: Neumorphic Contrast Failure — Interactive Elements Become Invisible

**What goes wrong:**
Buttons and tappable surfaces defined entirely by dual-shadow depth — no colour change, border, or fill shift to mark interactivity — fall below the WCAG 2.1 criterion 1.4.11 requirement of 3:1 contrast for non-text UI components. The design system's neuro skin in `tokens.jsx` uses `--label2` at `rgba(220,223,238,0.56)` on a `#1C1C23` surface. At 56% opacity, secondary labels can fail the 4.5:1 text contrast requirement. Users with low contrast sensitivity cannot identify what is tappable.

**Why it happens:**
Neumorphism's defining trick — extruded shadow implying depth — relies on near-surface-colour shadows. The design handoff neuro token `--glass-shadow` is `-6px -6px 14px rgba(255,255,255,0.035), 7px 7px 18px rgba(0,0,0,0.55)`: a 3.5% white highlight and a 55%-opacity black drop shadow. That white value is so faint that the light side of the extrusion is essentially invisible at any ambient brightness other than a pitch-black room. Developers copy these exact values into SwiftUI `.shadow()` without measuring the contrast of the resulting surface boundary against the background.

**How to avoid:**
1. Measure every interactive surface boundary (not just text) against the app background using Xcode Accessibility Inspector contrast checker before shipping each view.
2. For pressed/selected state: add a `.fill2` background tint (`#16161C` inset) as the pressed state, not just reversed shadows. Shadow reversal alone is not perceptible to low-vision users.
3. Keep accent colour (canary `#FFD60A`) as the mandatory indicator of the *active* state — e.g. active tab capsule, active budget ring — because bright yellow achieves 8:1+ on the `#1C1C23` charcoal surface.
4. All icon-only buttons in the floating capsule tab bar must carry `.accessibilityLabel` strings — never rely on icon shape alone.
5. Run the app through the iOS Accessibility Inspector with "Colour Filters > Greyscale" to verify shadow depth is still perceptible without colour.

**Warning signs:**
- Any SwiftUI `.shadow(color:)` call that passes a white with opacity below 0.06 or a dark with opacity below 0.35 — these are the tokens from the neuro skin; re-check contrast.
- A view that changes appearance only via `.scaleEffect` or reversed shadows on tap — it has no accessible state change.
- Xcode Accessibility Inspector shows a contrast warning badge on any Label or Button.

**Phase to address:**
Design System phase (first phase of v1.2). Build `NMButton` and `NMCard` components with contrast assertions in unit tests. Gate every subsequent restyle phase on: no new Accessibility Inspector warnings.

---

### Pitfall 2: Dynamic Type Breakage From Fixed Font Sizes in Design Tokens

**What goes wrong:**
The design handoff specifies pixel-exact `fontSize` values (11px, 13px, 14.5px, 15.5px, 22px, 42px). Translating these directly to SwiftUI `.font(.system(size: 14))` bypasses Dynamic Type scaling. On an iPhone with Accessibility > Larger Text set to maximum, monetary amounts are physically smaller than the user's system preference — a critical accessibility regression.

**Why it happens:**
Design handoff files are always pixel-perfect for the prototype viewport. Developers unfamiliar with Dynamic Type mechanics translate `fontSize: 42` as `.font(.system(size: 42))`. The correct translation is `.font(.system(.largeTitle))` (or a custom scaled font) with `@ScaledMetric` for any layout value that must flex with text size (card padding, icon container size, vertical gap).

**How to avoid:**
Define a `NMFont` enum that maps each design token size to the nearest `Font.TextStyle` with a `relativeTo:` scaled fallback for unusual sizes like the 42px hero amount. Use `@ScaledMetric` for derived layout values. For the rolling-money readout specifically: use a scaled font so large-accessibility users still see amounts at the right relative size.

```swift
// Correct:
.font(.system(.largeTitle, design: .default, weight: .light)) // ~34pt, scales
// Wrong:
.font(.system(size: 42, weight: .light))
```

**Warning signs:**
- Any `.font(.system(size:` call with a literal number in a view file (not inside a dedicated token/style helper).
- UI test run at Accessibility Large Text fails to render the rupee amount legibly.
- Xcode canvas shows clipped labels at XXL Dynamic Type preset.

**Phase to address:**
Design System phase. Define all typography tokens as `Font.TextStyle` references. Include a UI snapshot test at both `xsSmall` and `accessibility5` Dynamic Type sizes to catch regressions in any subsequent phase.

---

### Pitfall 3: Shadow Performance Degradation in Lists and ScrollViews

**What goes wrong:**
Every row in the Activity (expenses) list and the Budgets list gets a `NMCard` wrapper with two `.shadow()` modifiers (light upper-left, dark lower-right). SwiftUI evaluates each shadow as a separate compositing pass. With 30–60 expense rows visible across a scroll gesture, the render tree has 60–120 shadow layers being recalculated on every frame. This causes dropped frames and stuttering, especially on older A-series chips.

**Why it happens:**
In isolation, two `.shadow()` calls on one card look fine. The problem is multiplicative: SwiftUI's default render path does not batch shadow compositing for list rows. Each row is an independent compositing surface; two shadows per row means the GPU is doing N×2 blur passes per scroll frame. The design's neuro card token uses explicit `box-shadow: -6px -6px 14px ..., 7px 7px 18px ...` — translated naively this becomes two `.shadow()` calls on each card.

**How to avoid:**
1. Use a single custom `NMCardBackground` shape drawn with `Canvas` that renders both shadows in one GPU draw call rather than two SwiftUI modifier layers.
2. Alternatively, apply `.drawingGroup()` to the card content (not the whole list) to flatten it to a single bitmap before shadow compositing.
3. In `LazyVStack`-backed lists, apply card shadows to the row container — one shadow scope per row, not per element within the row.
4. Test on device (not Simulator): shadows are GPU-accelerated differently on device and Simulator masks real cost.
5. For Budget progress bars — each has its own shadow — apply `.compositingGroup()` to each row before adding the outer card shadow.

**Warning signs:**
- Instruments > Core Animation shows `CA::Render::prepare_commit` time exceeds 4ms per frame during list scroll.
- Any `.shadow()` call inside a `ForEach` body that is nested inside another `.shadow()`-decorated container.
- Simulator shows >60ms frame time in Activity list with 40+ rows.

**Phase to address:**
Design System phase (component build). Include a performance acceptance criterion: scroll through 50 expense rows with no frames exceeding 16ms render time, measured on device.

---

### Pitfall 4: The iOS 26 Deployment Target Floor Trap for FoundationModels

**What goes wrong:**
Developer sees `import FoundationModels` requires `@available(iOS 26, *)` and raises the project deployment target from iOS 17 to iOS 26 to silence the compiler. This instantly drops support for every device on iOS 17–25, including iPhone 12–14 users who have not updated — and potentially Reo's wife's device if she runs an older OS.

**Why it happens:**
The compiler error "FoundationModels is only available in iOS 26.0 or newer" and the red underline are alarming; the quickest fix in Xcode is to change the deployment target. Developers unfamiliar with `#available` gating take the path of least resistance.

**How to avoid:**
Keep deployment target at iOS 17. Wrap every `FoundationModels` call in `#available(iOS 26, *)`. Structure the AI Insight card with three gating layers:

```swift
// Layer 1: pre-iOS-26 — card not shown at all
guard #available(iOS 26, *) else { return nil }

// Layer 2: iOS 26 device eligibility
switch SystemLanguageModel.default.availability {
case .available:
    // proceed with generation
case .unavailable(let reason):
    switch reason {
    case .deviceNotEligible:
        // permanent — hide card entirely
    case .appleIntelligenceNotEnabled:
        // show "Enable Apple Intelligence in Settings" CTA
    case .modelNotReady:
        // show skeleton; schedule retry; call prewarm() now
    @unknown default:
        // hide card
    }
}
```

The card's absence on ineligible devices is required behaviour per PROJECT.md ("gracefully degrades where unsupported").

**Warning signs:**
- `IPHONEOS_DEPLOYMENT_TARGET = 26` in project.pbxproj.
- Any `FoundationModels` type used outside an `if #available(iOS 26, *)` block.
- The AI Insight card is shown to users whose `SystemLanguageModel.default.availability == .unavailable`.

**Phase to address:**
AI Insight phase. Write a unit test with a mock availability state that exercises all four branches (available, deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady). Confirm deployment target is iOS 17 after implementation.

---

### Pitfall 5: AI Insight Card Inventing Financial Numbers (Hallucination in Finance Context)

**What goes wrong:**
The FoundationModels on-device LLM generates plausible-sounding but factually incorrect monetary figures in the insight text — e.g. "You spent ₹6,200 on dining" when the real SwiftData total is ₹4,920. The model explicitly cannot perform arithmetic. In a finance app where users trust the insight to inform spending decisions, a hallucinated amount is actively harmful.

**Why it happens:**
The design prototype hardcodes insight strings like "Dining is up 34% this week — three weekend orders drove most of it." This looks like the model computed the percentage. The trap is prompting the model to *compute* or *derive* numbers from the data. Apple's own documentation acknowledges the model "will hallucinate" and has "severe logic limitations" compared to cloud LLMs.

**How to avoid:**
Never ask FoundationModels to calculate, derive, or invent any monetary figure. The correct architecture:
1. Compute all numbers in Swift using exact `Decimal` arithmetic before the model is invoked.
2. Build a structured prompt that injects pre-computed facts as literal context: `"This month's dining spend: ₹4,920 (vs ₹3,650 last month, +34.8%). Top merchant: Swiggy (₹1,840)."` The model's only job is to restate these facts in natural-language prose.
3. Use `@Generable` with a typed `InsightOutput` struct containing only `insightText: String` — no numeric fields that the model could generate from imagination.
4. After generation, programmatically verify that any rupee figure appearing in the output string matches a figure from the pre-computed context. If not, fall back to a templated string built from the pre-computed facts.

**Warning signs:**
- Prompt text contains phrases like "calculate", "what percentage", or "how much more" — asks the model to do arithmetic.
- The `@Generable` struct has `Double`, `Decimal`, or `Int` fields.
- Insight text is displayed directly from model response with no numeric cross-check.

**Phase to address:**
AI Insight phase. Define `InsightContext` (pre-computed by aggregator) and `InsightVerifier` (post-generation numeric cross-check) as required components. Unit-test with mock LLM responses containing fabricated rupee amounts and verify the verifier catches them.

---

### Pitfall 6: Reduce Motion Violation — Rolling-Money Animations and Plasma Blobs

**What goes wrong:**
The rolling-money odometer, plasma blob drift (`lqDrift1–3` keyframes), and the scanning-dot-on-chart animation are all continuous or value-change-driven. When the user has enabled Settings > Accessibility > Reduce Motion, all decorative and non-essential motion must stop. Failing to honour this makes the app inaccessible to users with vestibular disorders and violates WCAG 2.3.3.

**Why it happens:**
`liquid.css` shows partial Reduce Motion handling: the `@media (prefers-reduced-motion: reduce)` block slows blobs to 60-second cycles. `analytics.css` nulls out specific animation classes but does NOT handle the `lqaDotPulse` animation on the SVG `<circle>` inside the chart. In SwiftUI, checking `@Environment(\.accessibilityReduceMotion)` at every animation site is easy to miss — developers add it to the first few views and forget later ones.

**How to avoid:**
1. Create a shared `MotionEnvironment` observable that gates all animations: read `@Environment(\.accessibilityReduceMotion)` once at the root and propagate it.
2. Rolling-money: substitute `withAnimation(.none)` for the spring when `isReduceMotion == true`. The value updates instantly.
3. Plasma background: on Reduce Motion, show a static charcoal (`#1C1C23`) background only.
4. Scanning dot on Analytics chart: hide when `isReduceMotion == true`.
5. All `withAnimation` call sites and `animateOnMount` flags must check `isReduceMotion`.
6. Test by enabling Reduce Motion in the Simulator and walking every animated screen.

**Warning signs:**
- A `withAnimation` or `.animation()` modifier that does not branch on `accessibilityReduceMotion`.
- The plasma field has any animated layers visible when Reduce Motion is on.
- The odometer displays intermediate values when Reduce Motion is on.

**Phase to address:**
Design System phase (animation infrastructure). Encode Reduce Motion as a first-class gate in the shared `MotionEnvironment` so every subsequent view gets it automatically.

---

### Pitfall 7: UTC/IST Date Bucketing Error in Analytics Aggregation

**What goes wrong:**
The app stores all `expense.date` values in UTC. The existing `SpendOverTimeAggregator` correctly uses `TimeZone.current` (IST, UTC+5:30) for bucketing. The new Analytics aggregator must bucket expenses into the user's local day, not the UTC day. The IST offset of +5:30 means a transaction at 11:30 PM IST is stored as 6:00 PM UTC — which belongs to the *previous* UTC day. If the new aggregator uses `Calendar(identifier: "gregorian")` without setting `.timeZone`, expenses near midnight appear in the wrong day bucket.

**Why it happens:**
`Calendar(identifier:)` defaults to the device's current timezone on device but defaults to UTC on CI machines. Tests pass on a UTC CI server, fail silently on an IST device for transactions timestamped 18:30–23:59 UTC (midnight–5:29 AM IST next day).

**How to avoid:**
1. Always construct the `Calendar` in aggregators as:
   ```swift
   var cal = Calendar.current
   cal.timeZone = TimeZone.current
   ```
2. In tests, explicitly set the calendar's timezone to `TimeZone(identifier: "Asia/Kolkata")!` and create test dates straddling the IST midnight boundary: `2026-06-19T18:29:00Z` (11:59 PM IST June 19) vs `2026-06-19T18:31:00Z` (00:01 AM IST June 20) must bucket to different local days.
3. The existing `SpendOverTimeAggregator` already uses the correct pattern (see its `startOfDay` private method). The new Analytics aggregator must reuse this, not re-implement bucketing.
4. For "compare vs last week/month" delta chips: the comparison window must be computed in IST, not as "7 UTC days ago".

**Warning signs:**
- Any `Calendar(identifier: "gregorian")` construction in the new aggregator without an explicit `.timeZone` assignment.
- Test dates created from `ISO8601DateFormatter` without specifying `timeZone = TimeZone(identifier: "Asia/Kolkata")`.
- The Analytics "Week" total differs from the Overview "This Week" widget for the same data.

**Phase to address:**
Analytics/Charts phase. Required test: `SpendAnalyticsAggregatorTests.testMidnightISTBucketBoundary` with two expenses at 18:29Z and 18:31Z on the same UTC date, asserting they land in different day buckets.

---

### Pitfall 8: Swift Charts DonutChart Regression From Restyle — Clipping and Colour Mismatch

**What goes wrong:**
`DonutChart.swift` already uses `SectorMark` (iOS 17+, confirmed already shipping). The restyle wraps it in a `NMCard` with a `clipShape(RoundedRectangle(cornerRadius: 26))`. If `.clipShape` is applied to the Chart's immediate container, marks near the edge are clipped — segments at the 12, 3, 6, 9 o'clock positions are cropped. A second failure: `DonutSegment.color` uses the v1.1 palette `Color` values; after the neumorphic restyle these colours are not updated, so the donut uses different hues than the category bars on the Analytics screen.

**Why it happens:**
Swift Charts has its own rendering pipeline independent of SwiftUI's surface token system. Changing the design system does not automatically update chart mark colours — they are set at data-binding time. Developers assume "everything re-skins" when they update the token set.

**How to avoid:**
1. Apply `.clipShape` at the `NMCard` container level, not on the `Chart` view or its immediate parent. The Chart needs overflow room for corner antialiasing.
2. Update `DonutSegment.color` construction to use the new `CAT_COLORS` from the neumorphic design token set (translate hex to `Color(hex:)` via a shared extension). Update this in the aggregator that creates `DonutSegment` values, not in the view.
3. Preserve `.accessibilityHidden(true)` on the chart itself; ensure the parent card provides a single descriptive `.accessibilityLabel` built from the segment data (e.g. "Spending breakdown: Groceries 35%, Dining 28%...").

**Warning signs:**
- Chart segments are clipped at the card boundary.
- VoiceOver reads individual `SectorMark` values without a useful parent label.
- Segment colours in the donut visually mismatch the category bar colours on the Analytics screen.

**Phase to address:**
Overview Restyle phase. Add a `DonutChartSnapshotTest` that renders the chart at both appearances and checks no segment is clipped.

---

### Pitfall 9: FoundationModels 4096-Token Context Limit With Real Expense History

**What goes wrong:**
The AI Insight prompt injects the month's spending facts to ground the model. If facts are verbose — 200+ transactions each with merchant, category, amount, date — the serialised context string easily exceeds the 4,096-token combined input+output limit. The session throws `LanguageModelSession.GenerationError.exceededContextWindowSize`. With no handler, this crashes or silently shows nothing.

**Why it happens:**
The design prototype hardcodes small demo datasets (6 categories, 5 values). Real usage for a month of 2-person household expenses can have 80–150 transactions. Developers write the prompt builder for the demo case.

**How to avoid:**
1. The prompt should never contain raw transaction lists. Pre-aggregate to a maximum of 8 category totals + 3 top merchants + period total before building the prompt string.
2. Implement a `PromptBuilder` with a token budget guard: estimate tokens as `promptString.count / 4` (conservative), cap input at 2,048 tokens to leave 2,048 for the response.
3. Catch `exceededContextWindowSize` explicitly and fall back to the templated string.
4. Test with `promptString` at 3,500 estimated tokens to verify the guard fires before the API does.

**Warning signs:**
- The prompt builder operates on raw `[Expense]` arrays with more than 20 elements.
- No `catch LanguageModelSession.GenerationError.exceededContextWindowSize` handler in the AI generation path.
- Integration test with 150 expenses causes an unhandled error.

**Phase to address:**
AI Insight phase. The `PromptBuilder` and context budget guard are required before the first end-to-end AI test.

---

### Pitfall 10: FoundationModels Guardrail False Positives on Finance Terms

**What goes wrong:**
Apple's on-device safety guardrails scan prompt content. Finance vocabulary — "debt", "overdraft", "negative balance", "net loss" — can trigger a `guardrailViolation` error if the safety classifier misidentifies it as harmful content. Apple's own documentation explicitly acknowledges "false positives" in guardrail activation.

**Why it happens:**
The model is tuned on general consumer content; financial domain vocabulary shares surface-form overlap with harm-adjacent terms. The guardrail fires on the serialised prompt text before generation begins.

**How to avoid:**
1. Catch `LanguageModelSession.GenerationError.guardrailViolation` explicitly and fall back to the templated insight string.
2. Keep prompt framing neutral: "Summarise this spending data in one insight sentence." Avoid emotionally charged framing ("alarming spend", "danger zone budget").
3. Before shipping, test prompts against the maximum-spend month scenario (rent + large dining + medical) to confirm no guardrail triggers on real data.

**Warning signs:**
- Prompt text uses emotionally charged words around financial stress.
- No `catch guardrailViolation` handler — the view shows a blank insight or crashes.
- QA tests only happy-path prompts, never edge-case vocabulary.

**Phase to address:**
AI Insight phase. Include a guardrail-trigger test in the test suite with a mock session that throws this error.

---

### Pitfall 11: FoundationModels Latency — No Streaming, Blank Insight for 20–30 Seconds

**What goes wrong:**
Without streaming, the AI Insight card shows nothing for 20–30 seconds (documented latency benchmark) while the model generates. Users assume the card is broken and navigate away.

**Why it happens:**
`LanguageModelSession.respond(to:)` (non-streaming) blocks until the full response is ready. The design prototype's typewriter reveal animation fires after a hardcoded delay — it creates a false impression that the model responded quickly.

**How to avoid:**
1. Use `LanguageModelSession.streamResponse(to:)` to progressively display characters as they generate. This matches the design's typewriter animation intent.
2. Show a skeleton/placeholder state (the breathing AI orb) while generation begins.
3. Call `SystemLanguageModel.default.prewarm()` on `onAppear` of the Analytics screen, not when the user scrolls to the card.
4. Set a hard timeout (10 seconds): if streaming has not completed, show a templated fallback.

**Warning signs:**
- Using `respond(to:)` (non-streaming) for the insight card.
- No skeleton/loading state in the AI card before the first token arrives.
- `prewarm()` not called until the card becomes visible.

**Phase to address:**
AI Insight phase. Streaming is a requirement, not an optimisation.

---

### Pitfall 12: Xcodeproj Explicit File References — New Design System Files Silently Excluded

**What goes wrong:**
The v1.2 restyle adds new Swift files: `DesignTokens.swift`, `NMCard.swift`, `NMButton.swift`, `NMTabBar.swift`, `RollingMoney.swift`, `InsightCard.swift`, etc. The project uses explicit `PBXFileReference` entries (no synchronized groups — documented in project memory). New files created on disk are not auto-included in the compile target. They compile silently absent: types referenced from other files produce "cannot find type X in scope" errors only at post-merge clean build time.

**Why it happens:**
Known project footgun. Every new `.swift` file requires 4 manual edits to `project.pbxproj`: `PBXBuildFile`, `PBXFileReference`, `PBXGroup` children, and `PBXSourcesBuildPhase`. Executor agents that create files without editing `pbxproj` leave the project in a state that passes their local incremental build but fails the orchestrator's clean build.

**How to avoid:**
For every new `.swift` file created in v1.2:
1. Immediately add all 4 `pbxproj` entries as part of the same commit that creates the file.
2. Run a clean build (`xcodebuild clean build`) after each new file is registered to confirm inclusion.
3. Each roadmap phase must include an explicit checklist item: "All new .swift files registered in pbxproj — verified with clean build."
4. Batch new files by subsystem to reduce edit rounds (e.g. add all design-system files at once in Phase 1).

**Warning signs:**
- A new `.swift` file exists on disk but is not listed in `project.pbxproj`.
- Build succeeds but tests reference a type from the new file and fail with "unresolved identifier".
- A phase's exit criteria do not include a clean build verification step.

**Phase to address:**
Every phase of v1.2. The Design System phase will be the worst, with 10+ new files at once.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Apply `.shadow(color: .white.opacity(0.035), ...)` directly on List rows instead of via a shared `NMCard` | Faster to prototype | Shadow changes require touching every view file; 118 files become 118 separate shadow definitions | Never — define `NMCard` first |
| Hard-code category colours in chart instead of using design token `CAT_COLORS` | One less indirection | Re-skin requires touching chart data builders, not just tokens | Never in a multi-skin system |
| Use `respond(to:)` (blocking) instead of streaming for initial prototype | Simpler code | Users see 20–30s blank; hard to swap to streaming mid-phase without UX rework | Only for unit tests / pure logic tests |
| Skip Reduce Motion check for "just the rolling number" | Saves two lines | One missed animation fails accessibility audit; sets precedent for skipping others | Never |
| Set deployment target to iOS 26 to silence compiler | Zero `#available` boilerplate | App excluded from iOS 17–25 devices | Never |
| Use `Calendar(identifier: "gregorian")` without `.timeZone` in tests | Less boilerplate | Tests pass on UTC CI, fail silently on IST device for post-midnight transactions | Never in aggregator tests |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| FoundationModels availability | Check only `#available(iOS 26, *)` and assume the model works | Check `#available` AND `SystemLanguageModel.default.availability` — three distinct unavailability reasons need distinct UX responses |
| FoundationModels session | Create a new `LanguageModelSession` per insight request | Reuse the session across requests for the same Analytics screen; session state is preserved across turns |
| FoundationModels session | Send requests from multiple views in parallel | Each session processes one request at a time; parallel calls throw `rateLimited` — serialise or use separate sessions |
| Swift Charts + NMCard | Apply `.clipShape` to the `Chart` view itself | Apply `.clipShape` to the card container; the Chart's internal rendering must not be clipped or marks at the edge disappear |
| `SpendOverTimeAggregator` for Analytics | Copy-paste the aggregator and remove `TimeZone.current` setting | Reuse or extract as a shared utility; do not re-implement bucketing logic |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Dual `.shadow()` on every List row | Scroll stutter, >16ms frames in Activity list | Single-pass `NMCardBackground` drawn with `Canvas`; one compositing group per row | 30+ rows visible simultaneously |
| `withAnimation(.spring(...))` on rolling-money for every `@Query` refresh | Number animates on every background Gmail sync | Gate `withAnimation` on user-initiated navigation, not data refresh; use `.transaction` to suppress bg-refresh animations | Gmail sync fires while Activity list is visible |
| Plasma blob animation active during LLM generation | GPU contention; LLM generation slows further | Pause plasma animation while `isGenerating == true`; resume on completion | LLM invoked while Analytics screen is visible |
| Swift Charts redraw on every parent state change | Chart redraws when unrelated state changes (e.g. tab selection) | Isolate chart data in `@State` or a separate `@Observable` view model; use `.id(rangeKey)` to force-redraw only on range change | Any parent `@Observable` property changes |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Passing raw expense data to a remote LLM instead of FoundationModels | Household financial data leaves device | FoundationModels is mandatory per PROJECT.md; no remote AI API calls. Audit all `URLSession` call sites to confirm none are added during the AI phase |
| Logging the AI prompt string (which contains financial summaries) to console or crash reporter | Financial details in logs | Use `os_log(.debug, ...)` with private formatting: `os_log(.debug, "AI prompt: %{private}@", prompt)` |
| Rendering AI insight text with markdown enabled when merchant names are injected into the prompt | Prompt injection via merchant name embedding markdown or escape sequences | Sanitise merchant names before injecting into prompt (strip backticks, angle brackets, newlines) |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Floating capsule tab bar occludes bottom content in ScrollViews | Last row of Activity list hidden behind tab bar | Add `.safeAreaInset(edge: .bottom)` equal to tab bar height + 16pt to all ScrollView and List containers |
| Rolling-money animation shows intermediate (incorrect) values | User reads a wrong amount mid-roll; could screenshot it | Only animate on navigation transition, not on data update; never animate the primary displayed balance if it could be read as the "current" value |
| AI Insight card absent on ineligible device with no explanation | User taps Analytics, sees nothing, assumes bug | Show a static "Spending insights available on Apple Intelligence–enabled devices" placeholder card — never a blank space or invisible gap |
| Analytics "Year" tab shows all 12 months including future months with zero bars | Misleading — August–December appear flat, implying no future spend rather than absent data | Clip "Year" slots to `min(currentMonthIndex, 12)` — show only months up to and including the current month |

---

## "Looks Done But Isn't" Checklist

- [ ] **Neumorphic button states:** Every button has a visually distinct pressed state beyond reversed shadows — verify with Accessibility Inspector Colour Filter (greyscale) that the pressed state is distinguishable.
- [ ] **Rolling-money Reduce Motion:** With Accessibility > Reduce Motion ON, rolling numbers snap to final value with zero intermediate frames — verify in Simulator.
- [ ] **AI Insight fallback:** On a device without Apple Intelligence (or on iOS 17–25), the Analytics screen renders correctly with a static placeholder card — no crash, no blank gap, no stuck spinner.
- [ ] **Context token budget:** With 150 real-volume expenses injected into `PromptBuilder`, the prompt string is under 2,048 estimated tokens — verify with `prompt.count / 4 < 2048`.
- [ ] **Guardrail error handled:** `LanguageModelSession.GenerationError.guardrailViolation` is caught and shows the templated fallback — verify by unit-testing with a mock session that throws this error.
- [ ] **IST midnight bucket:** Expenses at 18:29Z and 18:31Z on the same UTC date bucket to different IST days in `SpendAnalyticsAggregatorTests`.
- [ ] **All new .swift files in pbxproj:** After each phase, `xcodebuild clean build` succeeds with no "cannot find type" errors.
- [ ] **DonutChart not clipped:** `NMCard` wrapping `DonutChart` — all SectorMark segments fully visible at the card edges — verify with snapshot test.
- [ ] **Float/scroll safeAreaInset:** Analytics screen and Activity list have bottom padding equal to tab bar height + 16pt — last row fully visible above the floating tab bar.
- [ ] **SectorMark iOS 17 floor confirmed:** `DonutChart.swift` already uses `SectorMark` without an `@available` guard and is deployed on iOS 17+; no new availability guard needed.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Contrast failures discovered at QA | MEDIUM | Audit all `NMCard` and `NMButton` usages; add a faint `.overlay(RoundedRectangle..., stroke: Color.white.opacity(0.07))` border to card boundaries; increase `--label2` opacity to 0.72 minimum |
| Dynamic Type broken across many screens | HIGH | Introduce `NMFont` token enum retroactively; replace all literal `.font(.system(size:))` calls — likely 30–50 sites |
| iOS 26 deployment target accidentally raised | LOW | Revert `IPHONEOS_DEPLOYMENT_TARGET` in pbxproj to 17.0; add `#available(iOS 26, *)` wrappers at all FM call sites — one-hour fix |
| AI hallucinated numbers shipped to users | HIGH | Hotfix: add numeric cross-check validator before display; disable AI card for one release while validator is built and tested; trust erosion is the real cost |
| Shadow performance causes scroll stutter | MEDIUM | Refactor `NMCard` to `Canvas`-based single-pass shadow; no API changes needed, pure internal implementation change |
| Missing pbxproj entries cause clean build failure | LOW | Add 4 lines per missing file to pbxproj; clean build; 15 minutes per file, disruptive if discovered post-merge |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Neumorphic contrast failure | Design System phase | Xcode Accessibility Inspector zero-warning pass on `NMCard`, `NMButton`, `NMTabBar` |
| Dynamic Type fixed sizes | Design System phase | UI snapshot tests at `xsSmall` and `accessibility5` Dynamic Type presets |
| Shadow performance in lists | Design System phase | Instruments frame-time < 16ms scrolling 50 rows on device |
| iOS 26 deployment target trap | AI Insight phase | `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` returns `17.0`; all FoundationModels calls inside `#available(iOS 26, *)` |
| AI inventing financial numbers | AI Insight phase | Unit test: mock LLM response with fabricated rupee amount fails `InsightVerifier` |
| Reduce Motion violation | Design System phase | All animated views pass test with `UIAccessibility.isReduceMotionEnabled = true` via XCTest |
| UTC/IST date bucketing error | Analytics/Charts phase | `testMidnightISTBucketBoundary` passes with 18:29Z and 18:31Z test expenses in different IST day buckets |
| DonutChart regression from restyle | Overview Restyle phase | Snapshot test: `DonutChart` in `NMCard` — no segment clipping at any card edge |
| FoundationModels context limit | AI Insight phase | `PromptBuilderTests.testBudgetWith150Expenses` confirms prompt under 2,048 estimated tokens |
| Guardrail false positive | AI Insight phase | Unit test: `guardrailViolation` mock shows fallback string, no crash |
| LLM latency / no streaming | AI Insight phase | Integration test: first character of insight appears within 3 seconds of `onAppear` |
| Xcodeproj missing file references | Every phase | Clean build (`xcodebuild clean build`) is a required exit criterion for every phase |

---

## Sources

- Apple Developer Documentation: [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) — availability states and device eligibility
- Apple Developer Documentation: [LanguageModelSession.GenerationError.guardrailViolation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/guardrailviolation(_:))
- Apple Developer Documentation: [LanguageModelSession.GenerationError.exceededContextWindowSize](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/exceededcontextwindowsize(_:))
- WWDC25: [Explore prompt design & safety for on-device foundation models](https://developer.apple.com/videos/play/wwdc2025/248/)
- WWDC25: [Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- Axess Lab: [Neumorphism — the accessible and inclusive way](https://axesslab.com/neumorphism/)
- Medium (Xurxe Toivo Garcia): [For a more accessible Neumorphism (Soft UI)](https://medium.com/@xurxe/accessible-neumorphism-soft-ui-992286900bfa)
- DEV Community: [How to Fall Back Gracefully When Apple Intelligence Isn't Available](https://dev.to/arshtechpro/how-to-fall-back-gracefully-when-apple-intelligence-isnt-available-48j)
- Natasha The Robot: [Introduction to Apple's FoundationModels: Limitations, Capabilities, Tools](https://www.natashatherobot.com/p/apple-foundation-models)
- AzamSharp: [The Ultimate Guide To The Foundation Models Framework](https://azamsharp.com/2025/06/18/the-ultimate-guide-to-the-foundation-models-framework.html) — token limits, latency, `prewarm()`
- AppCoda: [Building Pie Charts and Donut Charts with SwiftUI in iOS 17](https://www.appcoda.com/swiftui-chart-ios17/) — SectorMark iOS 17 availability confirmed
- Hacking with Swift Forums: [Performance issues when adding shadows to a bunch of views](https://www.hackingwithswift.com/forums/swiftui/performance-issues-when-adding-shadows-to-a-bunch-of-views/7456)
- Fatbobman: [Fixing ScrollView Clipping: Allow Shadows to Overflow in SwiftUI](https://fatbobman.com/en/snippet/preventing-scrollview-content-clipping-in-swiftui/)
- Apple Developer Forums: [Performance degradation and redraw loops when syncing SwiftUI Charts](https://developer.apple.com/forums/thread/816542)
- Project memory: `xcodeproj-explicit-file-refs.md` — explicit PBXFileReference footgun (project-specific, verified)

---
*Pitfalls research for: My Home v1.2 — Neumorphic Redesign + FoundationModels AI + Swift Charts Analytics*
*Researched: 2026-06-20*
