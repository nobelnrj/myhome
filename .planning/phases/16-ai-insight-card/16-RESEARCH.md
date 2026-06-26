# Phase 16: AI Insight Card — Research

**Researched:** 2026-06-26
**Domain:** Apple FoundationModels (iOS 26), SwiftUI streaming, numeric integrity verification
**Confidence:** HIGH — all critical API shapes verified directly from the iOS 26.5 simulator SDK swiftinterface

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01/D-02:** On EVERY unavailability branch (`deviceNotEligible`, `appleIntelligenceNotEnabled`,
  `modelNotReady`, and pre-iOS-26), the AI card is **omitted entirely** — no shell card, no
  placeholder text, no blank gap, no spinner. ROADMAP Success Criterion 2 overrides AI-02 wording.
  Availability gating logic must still be implemented and unit-tested for all four branches; only
  the rendered output for unavailable branches is "nothing".
- **D-03:** Card uses `.neuSurface(.raised)` neumorphic base — NOT frosted glass.
- **D-04:** Violet edge-glow + `sparkles` icon + breathing orb as AI-only accent (violet
  `#C4A6FF`→`#7C5CFF`); primary accent stays canary `#FFD60A`. Add violet token(s) to
  `DesignTokens` scoped for AI use only; do not repaint other surfaces.
- **D-05:** Tone = observation + soft, data-grounded suggestion. `suggestion` is optional and
  included only when there is a clear, fact-supported nudge; never nagging or budget-policing.
- **D-06:** Focus angles: top-category change vs prior, overall trend/headline delta, notable
  concentration, calm reassurance on flat data ("spending held steady" — do NOT invent drama).
- **D-07/D-08:** Generate automatically when the card appears; re-generate on every
  Week/Month/Year range switch; CANCEL any in-flight generation on range change.
- **AI-04:** Every rupee/%/delta in output MUST match a Swift-precomputed `Decimal` fact.
  `InsightVerifier` rejects model-invented numbers and substitutes a templated fallback that
  reads like a normal terse insight (never an error).
- **AI-05:** Insights are ephemeral — no persistence.
- Deployment target stays `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; ALL FoundationModels code
  behind `#available(iOS 26, *)`.
- New `.swift` files MUST be registered in `MyHome.xcodeproj/project.pbxproj` (4 manual edits
  each — no synchronized groups).

### Claude's Discretion

- Exactly which `SpendSummary` facts to inject and how (token-budgeted prompt construction),
  the `InsightVerifier` matching strategy, and the templated-fallback sentence wording — all
  Claude's discretion, grounded in the AI-04 rule that every rupee/%/delta must match a
  pre-computed `Decimal` fact. Fallback should read as a normal terse insight, never as an error.
- Typewriter cadence (~22–38 cps per handoff), orb animation timing.

### Deferred Ideas (OUT OF SCOPE)

- Persisted insight history / "past insights" timeline.
- A user-facing "graceful shell" advertising the feature on ineligible devices.
- Light mode.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AI-01 | AI Insight card on Analytics screen, on-device FoundationModels, fully offline, finance data never leaves device | FoundationModels.framework confirmed in iOS 26.5 SDK; no network involved; `LanguageModelSession` runs entirely on-device |
| AI-02 | Two-layer availability gating: `#available(iOS 26, *)` + runtime `SystemLanguageModel.default.availability`; all unavailability cases handled; per D-01/D-02 unavailable = card omitted entirely | Exact API shapes verified from swiftinterface: `.available`, `.unavailable(.deviceNotEligible/.appleIntelligenceNotEnabled/.modelNotReady)` |
| AI-03 | Guided generation: `@Generable` struct (observation + optional suggestion), structured prompt under token budget, handles `guardrailViolation` and `exceededContextWindowSize` | `@Generable` macro + `@Guide` confirmed; error enum cases confirmed; 4,096 token budget documented |
| AI-04 | Numeric integrity: all rupee/percentage/delta figures pre-computed in Swift and injected as literal context; output verified against injected facts before display | `InsightVerifier` strategy designed; `SpendSummary` fact surface documented; matching algorithm defined |
| AI-05 | Ephemeral insights, streaming typewriter animation, honors Reduce Motion | `streamResponse(to:generating:)` → `ResponseStream<SpendInsight>.Snapshot` confirmed; existing `@Environment(\.accessibilityReduceMotion)` pattern established in codebase |
</phase_requirements>

---

## Summary

Phase 16 adds a single `AIInsightCard` view appended below `AnalyticsCategoryBars` in `AnalyticsView`. It is gated with two complementary guards — `#available(iOS 26, *)` compile-time and `SystemLanguageModel.default.availability` runtime — so the card is completely absent on pre-iOS 26 devices and silently absent on iOS 26 devices that lack Apple Intelligence. Both guards verified from the iOS 26.5 SDK swiftinterface (Xcode 26.5 confirmed on machine).

The core generation pipeline: `InsightPromptBuilder` serialises a compact set of `SpendSummary` facts into a prompt string; a `LanguageModelSession` with system instructions generates a `@Generable SpendInsight` struct (two string fields: `observation` and optional `suggestion`); `streamResponse(to:generating:)` streams token snapshots into a live typewriter reveal; when the stream ends, `InsightVerifier` scans the final text for any number tokens not present in the injected fact set and substitutes a template fallback if needed.

The most important architectural decision for testability: `LanguageModelSession` is a `final` class and cannot be subclassed. All business logic lives behind an `InsightGenerating` protocol that a `MockInsightService` can implement — this is the single seam that makes unit-testing all four availability branches and both error cases possible without a physical Apple Intelligence device.

**Primary recommendation:** Implement `InsightGenerating` protocol + `InsightService` + `InsightVerifier` as three separate pure types; keep `AIInsightCard` as a SwiftUI view that owns the `.task(id: summary.range)` cancellation lifecycle; drive typewriter reveal from streaming `Snapshot.content.observation`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Availability gating (pre-iOS 26) | View (`AIInsightCard`) | — | `#available` must appear at the call site; EmptyView returned pre-iOS 26 |
| Availability gating (runtime) | View (`AIInsightCard`) | — | `SystemLanguageModel.default` is `@Observable`; SwiftUI auto-re-renders on change |
| Prompt construction | Service (`InsightPromptBuilder`) | — | Pure function of `SpendSummary`; keeps View testable |
| LLM generation | Service (`InsightService: InsightGenerating`) | — | Wraps `LanguageModelSession`; abstracts behind protocol for mocks |
| Numeric integrity | Service (`InsightVerifier`) | — | Pure function on String + SpendSummary; no SwiftUI dependency |
| Typewriter animation / orb | View (`AIInsightCard`) | — | `@State` + `.task(id:)` streaming; ties to ReduceMotion env |
| Task cancellation on range change | View (`.task(id: summary.range)`) | — | `.task(id:)` cancels and restarts automatically on id change |
| Token persistence | — (none) | — | AI-05: ephemeral; discard after session |

---

## Standard Stack

### Core (ALL first-party — zero new dependencies per REQUIREMENTS.md ground rules)

| Framework | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| `FoundationModels` | iOS 26.0+ | On-device LLM, guided generation, streaming | `[VERIFIED: iOS 26.5 SDK swiftinterface]` |
| `SwiftUI` | iOS 17+ | UI, `.task(id:)` for cancellation, Reduce Motion env | Already in project |
| `Foundation` | — | `Decimal` arithmetic, `Regex` for number extraction in verifier | Already in project |

**No `import FoundationModels` line can appear outside an `#available(iOS 26, *)` guard or `@available(iOS 26, *)` type.** All FoundationModels types are gated at iOS 26.

---

## Package Legitimacy Audit

Not applicable — this phase adds zero new external package dependencies. All capabilities ship on first-party Apple frameworks (FoundationModels, SwiftUI, Foundation) already present in the Xcode 26.5 toolchain.

---

## Architecture Patterns

### System Architecture Diagram

```
AnalyticsView
    │
    ├── [selectedRange changes] ─────────────────────────────────────────┐
    │                                                                      ↓
    │   body: let summary = AnalyticsAggregator.summarize(...)            │
    │                                                                      │
    └── #available(iOS 26, *) {                                           │
            AIInsightCard(summary: summary)                               │
                │                                                         │
                ├── [runtime check]                                       │
                │   SystemLanguageModel.default.availability              │
                │       .available → render card + .task(id:) ←──────────┘
                │       .unavailable(*) → EmptyView (D-01)
                │
                └── .task(id: summary.range) [auto-cancels on range change — D-08]
                        │
                        ├── InsightPromptBuilder.buildPrompt(for: summary)
                        │       → compact fact string ≤ ~300 tokens
                        │
                        ├── InsightService.generate(for: summary)  [InsightGenerating]
                        │       └── LanguageModelSession.streamResponse(to:generating:SpendInsight.self)
                        │               → ResponseStream<SpendInsight>
                        │                   → Snapshot(content: SpendInsight.PartiallyGenerated)
                        │                       → partial.observation: String?  (grows)
                        │                       → partial.suggestion: String??  (grows)
                        │
                        ├── [stream live] displayedText = partial.observation ?? ""
                        │
                        └── [stream ends] InsightVerifier.verify(final, against: summary)
                                → .passed(text) → show as-is
                                → .failed → InsightFallbackBuilder.build(for: summary)
```

### Recommended Project Structure (new files only)

```
MyHomeApp/Features/Analytics/
└── AIInsightCard.swift          # SwiftUI view; #available(iOS 26,*); owns task lifecycle

MyHomeApp/Support/
├── InsightService.swift         # InsightGenerating protocol + InsightService (production)
│                                # + InsightPromptBuilder (prompt construction)
└── InsightVerifier.swift        # Numeric integrity check + InsightFallbackBuilder

MyHomeTests/
├── InsightServiceTests.swift    # Mock session; 4 availability branches + 2 error cases
└── InsightVerifierTests.swift   # Number extraction, matching, fallback generation tests
```

Total new .swift files: **5**. Each app-target file needs **4 pbxproj edits**; each test-target file needs **4 pbxproj edits** in the test sources section. See pbxproj footgun section.

### Pattern 1: `@Generable` Insight Struct

```swift
// Source: FoundationModels.swiftmodule/arm64-apple-ios-simulator.swiftinterface (iOS 26.5 SDK)
// @Generable + @Guide confirmed available iOS 26.0+

@available(iOS 26, *)
@Generable(description: "A brief spending insight for a two-person household finance app")
struct SpendInsight {
    @Guide(description: """
        One or two sentences observing the most notable spending pattern for the period.
        Terse, concrete, no preamble. Use ONLY the rupee figures and percentages
        explicitly listed in the context above — never invent or round numbers.
        """)
    var observation: String

    @Guide(description: """
        Optional soft, data-grounded suggestion. Include only when a clear, fact-supported
        nudge exists. Never mention budgets, limits, or policing. Omit entirely if nothing
        meaningful to add.
        """)
    var suggestion: String?
}
```

`SpendInsight.PartiallyGenerated` (auto-synthesised by `@Generable` macro):
- `observation: String?` — nil until first token arrives, then grows character-by-chunk
- `suggestion: String??` — nil until `observation` is complete and model starts the second field

### Pattern 2: `InsightGenerating` Protocol (the testability seam)

This is the single most important architectural decision. `LanguageModelSession` is `final` — it cannot be subclassed or mocked directly. All tests work through this protocol.

```swift
// Source: design inference from FoundationModels final-class constraint
// InsightService.swift

@available(iOS 26, *)
protocol InsightGenerating: Sendable {
    // Returns the complete, verified insight text (observation + optional suggestion joined).
    // Throws LanguageModelSession.GenerationError on failure.
    // Task cancellation propagates as CancellationError.
    func generate(for summary: SpendSummary) async throws -> SpendInsight
}

// Production implementation
@available(iOS 26, *)
final class InsightService: InsightGenerating {
    func generate(for summary: SpendSummary) async throws -> SpendInsight {
        let session = LanguageModelSession(instructions: InsightPromptBuilder.systemInstructions)
        let prompt = InsightPromptBuilder.buildPrompt(for: summary)
        let response = try await session.respond(
            to: prompt,
            generating: SpendInsight.self
        )
        return response.content
    }
}
```

Note: `generate(for:)` uses `respond()` (non-streaming) because the service layer does not own the
typewriter animation. The view layer drives live streaming separately via `streamResponse`. The
service protocol returns a complete `SpendInsight` for non-streaming paths (Reduce Motion, tests).

For **streaming** in the View:

```swift
// AIInsightCard.swift — streaming path (normal, no ReduceMotion)
// Source: FoundationModels swiftinterface; streamResponse confirmed iOS 26.0+

@available(iOS 26, *)
struct AIInsightCard: View {
    let summary: SpendSummary
    @State private var displayedObservation = ""
    @State private var displayedSuggestion: String? = nil
    @State private var isGenerating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // ... card chrome ...
        .task(id: summary.range) {
            // D-08: .task(id:) automatically cancels the previous task when range changes
            await generateInsight()
        }
    }

    @available(iOS 26, *)
    private func generateInsight() async {
        displayedObservation = ""
        displayedSuggestion = nil
        isGenerating = true
        defer { isGenerating = false }

        let session = LanguageModelSession(
            instructions: InsightPromptBuilder.systemInstructions
        )
        let prompt = InsightPromptBuilder.buildPrompt(for: summary)

        do {
            if reduceMotion {
                // Reduce Motion: instant reveal — use respond() not streamResponse()
                let response = try await session.respond(
                    to: prompt, generating: SpendInsight.self
                )
                let verified = InsightVerifier.verify(response.content, against: summary)
                displayedObservation = verified.observation
                displayedSuggestion = verified.suggestion
            } else {
                // Normal: live streaming typewriter from snapshot accumulation
                var lastPartial: SpendInsight.PartiallyGenerated?
                let stream = session.streamResponse(to: prompt, generating: SpendInsight.self)
                for try await snapshot in stream {
                    displayedObservation = snapshot.content.observation ?? ""
                    if let s = snapshot.content.suggestion {
                        displayedSuggestion = s
                    }
                    lastPartial = snapshot.content
                }
                // Stream ended: reconstruct final insight for verification
                let final = SpendInsight(
                    observation: lastPartial?.observation ?? displayedObservation,
                    suggestion: lastPartial?.suggestion ?? displayedSuggestion
                )
                let verified = InsightVerifier.verify(final, against: summary)
                // Atomically replace with verified text (in-place if passed)
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayedObservation = verified.observation
                    displayedSuggestion = verified.suggestion
                }
            }
        } catch is CancellationError {
            // D-08: task cancelled by range change — clear state silently
            displayedObservation = ""
            displayedSuggestion = nil
        } catch let err as LanguageModelSession.GenerationError {
            // AI-03: guardrailViolation, exceededContextWindowSize → fallback
            let fallback = InsightFallbackBuilder.build(for: summary)
            displayedObservation = fallback.observation
            displayedSuggestion = fallback.suggestion
        } catch {
            // Other errors (rateLimited, concurrentRequests) → fallback
            let fallback = InsightFallbackBuilder.build(for: summary)
            displayedObservation = fallback.observation
            displayedSuggestion = fallback.suggestion
        }
    }
}
```

### Pattern 3: `SystemLanguageModel.default.availability` — Exact Enum Shape

```swift
// Source: VERIFIED from iOS 26.5 SDK arm64-apple-ios-simulator.swiftinterface
// SystemLanguageModel confirmed @Observable (can drive SwiftUI auto-refresh)

// Availability property:
// final public var availability: SystemLanguageModel.Availability { get }

// Availability type:
// enum Availability: Equatable {
//     case available
//     case unavailable(UnavailableReason)
// }

// UnavailableReason enum:
// enum UnavailableReason: Equatable, Sendable {
//     case deviceNotEligible
//     case appleIntelligenceNotEnabled
//     case modelNotReady
// }

@available(iOS 26, *)
private var modelAvailability: SystemLanguageModel.Availability {
    SystemLanguageModel.default.availability
}

// In AIInsightCard.body — runtime gating:
switch modelAvailability {
case .available:
    insightCardContent  // render the card
case .unavailable:
    EmptyView()         // D-01: absolutely nothing
}
```

### Pattern 4: `GenerationError` — Exact Cases to Handle

```swift
// Source: VERIFIED from iOS 26.5 SDK swiftinterface
// LanguageModelSession.GenerationError cases (all iOS 26.0+):
//   .guardrailViolation(Context)         ← AI-03 required
//   .exceededContextWindowSize(Context)  ← AI-03 required
//   .assetsUnavailable(Context)
//   .unsupportedGuide(Context)
//   .unsupportedLanguageOrLocale(Context)
//   .decodingFailure(Context)
//   .rateLimited(Context)
//   .concurrentRequests(Context)         ← isResponding guard prevents this
//   .refusal(Refusal, Context)
```

Handle `.guardrailViolation` and `.exceededContextWindowSize` explicitly per AI-03. The others
can be caught by a general `GenerationError` fallback.

### Pattern 5: `InsightPromptBuilder` — Token-Budgeted Prompt

```swift
// Source: Claude's Discretion (AI-03). Budget: 4,096 tokens total (instructions + prompt + output).
// Target: keep prompt under ~400 tokens to leave ample room for output.

@available(iOS 26, *)
enum InsightPromptBuilder {

    static let systemInstructions = """
        You are a friendly spending assistant for a two-person Indian household.
        You write a single short paragraph: one or two sentences of observation followed by
        an optional soft suggestion. Use ONLY the rupee amounts and percentages explicitly
        given in the context — never calculate, round, or invent figures.
        Be warm and non-judgmental. Avoid mentioning budgets, limits, or financial advice.
        """

    static func buildPrompt(for summary: SpendSummary) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = ","
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 0

        func rupee(_ d: Decimal) -> String {
            "₹\(fmt.string(from: d as NSDecimalNumber) ?? d.description)"
        }

        let rangeLabel: String
        switch summary.range {
        case .week:  rangeLabel = "this week"
        case .month: rangeLabel = "this month"
        case .year:  rangeLabel = "this year"
        }

        let direction = summary.delta > 0 ? "up" : "down"
        let pct = abs(Int(summary.deltaFraction * 100))

        var lines = [
            "Range: \(rangeLabel)",
            "Total spend: \(rupee(summary.totalSpend))",
            "vs prior period: \(rupee(summary.priorTotalSpend)) (\(direction) \(pct)%)",
            "Top categories:"
        ]

        // Inject top-5 categories to stay within token budget
        let topCats = summary.categoryBreakdown.prefix(5)
        for cat in topCats {
            let priorAmt = summary.priorCategorySpend.values.first ?? .zero
            // Note: correct lookup requires matching by PersistentIdentifier
            lines.append("  \(cat.name): \(rupee(cat.spentDecimal))")
        }

        lines.append("")
        lines.append("Write a spending insight for this household.")
        return lines.joined(separator: "\n")
    }
}
```

Note: the real `buildPrompt` should look up prior-period spend per category by `cat.id`
(PersistentIdentifier) from `summary.priorCategorySpend`. The above is a skeleton; the planner
should specify this lookup correctly.

### Pattern 6: `InsightVerifier` — Number Integrity

```swift
// Source: Claude's Discretion (AI-04). Strategy: extract numeric tokens, normalise to Decimal,
// check membership in canonical fact set with ±0 tolerance (exact match after normalisation).

@available(iOS 26, *)
enum InsightVerifier {

    struct Result {
        let observation: String
        let suggestion: String?
        let passed: Bool
    }

    static func verify(_ insight: SpendInsight, against summary: SpendSummary) -> Result {
        let canonicalNumbers = buildCanonicalSet(from: summary)
        let combinedText = insight.observation + (insight.suggestion ?? "")

        if allNumbersVerified(in: combinedText, against: canonicalNumbers) {
            return Result(observation: insight.observation, suggestion: insight.suggestion, passed: true)
        } else {
            let fallback = InsightFallbackBuilder.build(for: summary)
            return Result(observation: fallback.observation, suggestion: fallback.suggestion, passed: false)
        }
    }

    // Build a Set<Decimal> of all injected fact values
    private static func buildCanonicalSet(from summary: SpendSummary) -> Set<Decimal> {
        var set = Set<Decimal>()
        set.insert(summary.totalSpend)
        set.insert(summary.priorTotalSpend)
        set.insert(abs(summary.delta))
        set.insert(Decimal(abs(Int(summary.deltaFraction * 100)))) // percentage as whole number
        for cat in summary.categoryBreakdown {
            set.insert(cat.spentDecimal)
        }
        for (_, v) in summary.priorCategorySpend {
            set.insert(v)
        }
        return set
    }

    // Extract numeric tokens and verify each is in the canonical set
    private static func allNumbersVerified(in text: String, against facts: Set<Decimal>) -> Bool {
        // Regex: extract digit sequences possibly followed by % sign
        // Strips ₹ prefix, commas. Handles "12,450" → Decimal(12450), "34%" → Decimal(34)
        let pattern = /(?:₹\s*)?(\d[\d,]*)(?:\.\d+)?(%)?/
        for match in text.matches(of: pattern) {
            let raw = match.output.1.description.replacingOccurrences(of: ",", with: "")
            if let d = Decimal(string: raw), !facts.contains(d) {
                return false
            }
        }
        return true
    }
}

// Fallback reads as normal terse insight, never as an error (D-05/AI-04)
enum InsightFallbackBuilder {
    static func build(for summary: SpendSummary) -> SpendInsight {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal; fmt.groupingSeparator = ","
        func rupee(_ d: Decimal) -> String {
            "₹\(fmt.string(from: d as NSDecimalNumber) ?? d.description)"
        }
        let top = summary.categoryBreakdown.first
        let dir = summary.delta > 0 ? "up" : "down"
        let pct = abs(Int(summary.deltaFraction * 100))
        let observation: String
        if let top {
            observation = "You spent \(rupee(summary.totalSpend)) — \(top.name) was the top category at \(rupee(top.spentDecimal)), with total spend \(dir) \(pct)% vs last period."
        } else {
            observation = "You spent \(rupee(summary.totalSpend)) this period, \(dir) \(pct)% vs the previous period."
        }
        return SpendInsight(observation: observation, suggestion: nil)
    }
}
```

### Pattern 7: Card Visual — Violet Edge-Glow on Neumorphic Base

```swift
// Source: design/design_handoff_myhome_neumorphic/src/analytics.jsx lines 343-349 (translated)
// D-03: base is .neuSurface(.raised); D-04: violet accent only on this card.

// Add to DesignTokens.swift (AI-scoped section):
// static let aiVioletTop    = Color(hex: "#C4A6FF")  // top of edge gradient
// static let aiVioletBottom = Color(hex: "#7C5CFF")  // bottom of edge gradient
// static let aiVioletGlow   = Color(hex: "#8B5CF6")  // shadow / orb / wash

// Edge glow — left-edge 4pt-wide band:
Rectangle()
    .fill(LinearGradient(
        colors: [DesignTokens.aiVioletTop, DesignTokens.aiVioletBottom],
        startPoint: .top, endPoint: .bottom
    ))
    .frame(width: 4)
    .neonGlow(DesignTokens.aiVioletGlow, radius: 8, intensity: 1.0)
    // reuse the existing neonGlow(_:radius:intensity:) modifier from DesignTokens.swift

// Breathing orb (shown while isGenerating; hidden with ReduceMotion):
// Use DonutChart's existing scaleEffect breathing pattern (already in codebase).
// Replicate: withAnimation(.easeInOut(duration: 2.4).repeatForever()) { scale = generating ? 1.1 : 1.0 }
// Show orb ring (14pt circle, 1.5pt violet border) + inner orb (11pt, violet radial fill).
```

### Anti-Patterns to Avoid

- **Rendering a skeleton/placeholder on unavailable devices.** D-01 is clear: EmptyView only.
- **Checking `isResponding` before every call.** Use one session per generation, discard after.
  Do NOT reuse a session across range changes — create a fresh one each time.
- **Leaving `LanguageModelSession` alive after task cancellation.** Swift structured concurrency
  cancels the `async throws` call; the session is deallocated with the task stack frame.
- **Accessing `response.output` instead of `response.content`.** The API uses `.content`.
- **Injecting Double money values into the prompt.** Always format from `Decimal` using
  `NSDecimalNumber` for the rupee string; never via `Double` (floating-point drift).
- **Running InsightVerifier before the stream ends.** Partial snapshots contain incomplete text;
  the verifier must see the final complete strings only.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| On-device LLM inference | Custom ML pipeline / CoreML text generation | `LanguageModelSession` + `@Generable` | The 3B model, tokenizer, and guided JSON generation are all managed by FoundationModels |
| Streaming token delivery | Manual polling / timer-based model query | `session.streamResponse(to:generating:)` | Returns `AsyncSequence` of `Snapshot`; handles buffering, partial JSON, cancellation |
| Structured output parsing | String-splitting / regex on raw LLM output | `@Generable` struct + guided generation | Compile-time schema enforcement; model constrained to valid JSON matching the struct |
| Task cancellation on navigation | Manual `isActive` bool + Task.cancel() call | `.task(id: summary.range)` modifier | SwiftUI automatically cancels and restarts on id change; zero manual bookkeeping |
| Orb breathing animation | Frame-by-frame CADisplayLink | `withAnimation(.easeInOut(duration:).repeatForever(autoreverses:))` + `.scaleEffect` | Same pattern used in `DonutChart.swift` (line 316) — established in codebase |
| Number extraction from text | Hand-written parser | `Regex` literal syntax (`/pattern/`) with Swift 5.7+ typed captures | Correct handling of Unicode digits, grouping separators, optional ₹ prefix |

---

## Runtime State Inventory

Step 2.5 SKIPPED — this is a greenfield feature addition phase, not a rename/refactor/migration.
No stored data, live service config, OS-registered state, or build artifacts require inventory.

---

## Common Pitfalls

### Pitfall 1: `FoundationModels` import at pre-iOS-26 scope

**What goes wrong:** Placing `import FoundationModels` at the top of any file that compiles for iOS 17 causes a build error: framework not available on deployment target.
**Why it happens:** All FoundationModels types exist only in iOS 26+. The file itself compiles for 17.0.
**How to avoid:** Every file that uses FoundationModels MUST be `@available(iOS 26, *)` as the type declaration, OR all usages wrapped in `#available(iOS 26, *) { }`. Using a dedicated `AIInsightCard.swift` with the `@available(iOS 26, *)` attribute on the struct is cleanest.
**Warning signs:** Build error "cannot find type 'LanguageModelSession' in scope" or "module 'FoundationModels' not found" on a 17.0 deployment-target build.

### Pitfall 2: Calling `SystemLanguageModel.default.availability` outside `#available(iOS 26, *)`

**What goes wrong:** `SystemLanguageModel` doesn't exist on iOS < 26. The availability check itself must be inside the guard.
**How to avoid:** The `AIInsightCard` view is declared `@available(iOS 26, *)`. Its body can reference `SystemLanguageModel.default` freely. The calling site in `AnalyticsView` wraps with `if #available(iOS 26, *)`.

### Pitfall 3: Reusing a `LanguageModelSession` across range changes

**What goes wrong:** Sessions have context (`transcript`). Reusing a session across ranges means the prior range's transcript influences the new generation.
**How to avoid:** Create a fresh `LanguageModelSession` inside each `.task(id:)` invocation. Since `.task(id:)` cancels the previous task on id change (D-08), the previous session reference is released naturally.
**Warning signs:** Insight for "Month" range references week-range figures.

### Pitfall 4: Assuming `Snapshot.content.observation` is non-nil from the first snapshot

**What goes wrong:** The first several streaming snapshots may arrive with `observation == nil` while the model emits the opening JSON token. Using `partial.observation!` crashes.
**How to avoid:** Always use `partial.observation ?? ""` when updating `displayedObservation`.

### Pitfall 5: `InsightVerifier` false-positives on small integers

**What goes wrong:** Common numbers like "1", "2", "3", "5" appear in category counts and narrative prose ("one keep you under") and can match any `Decimal(1)` in the fact set by accident.
**How to avoid:** Only extract numbers > 2 digits OR preceded by ₹ or followed by %. Pure small integers used as prose words ("one", "two") don't appear as digit tokens. The verifier regex should require either ₹ prefix, % suffix, or number ≥ 100.
**Revised strategy:** Skip numbers < 100 in the verifier unless they are %-suffixed. Only flag rupee amounts ≥ ₹100 and percentage figures.

### Pitfall 6: `priorCategorySpend` lookup by `PersistentIdentifier`

**What goes wrong:** `summary.priorCategorySpend` is `[PersistentIdentifier: Decimal]`. In `InsightPromptBuilder` and `InsightVerifier`, you must look up prior spend by `cat.id` (each `CategorySpendItem` has an `id: PersistentIdentifier`). Getting this wrong means wrong prior-period figures in the prompt.
**How to avoid:** `let priorAmt = summary.priorCategorySpend[cat.id] ?? .zero` — straightforward O(1) lookup.

### Pitfall 7: pbxproj 4-edit footgun (carried from all prior phases)

**What goes wrong:** New `.swift` files are silently not compiled if not registered in `project.pbxproj`. The project uses NO synchronized groups. Symptom: "cannot find type 'AIInsightCard' in scope" or blank build with no error.
**Pattern (from G_ANL group in project.pbxproj):**
  1. PBXBuildFile: `AXXX /* AIInsightCard.swift in Sources */ = {isa = PBXBuildFile; fileRef = FXXX /* AIInsightCard.swift */; };`
  2. PBXFileReference: `FXXX /* AIInsightCard.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AIInsightCard.swift; sourceTree = "<group>"; };`
  3. PBXGroup children: add `FXXX /* AIInsightCard.swift */,` to the `G_ANL /* Analytics */` group
  4. PBXSourcesBuildPhase: add `AXXX /* AIInsightCard.swift in Sources */,`
**Test files** go into the test target's PBXGroup (e.g. the Analytics tests group) and test target's Sources build phase.

### Pitfall 8: Verifier runs on partial text from streaming path

**What goes wrong:** If `InsightVerifier` is called on `displayedObservation` mid-stream (e.g. in an `onChange`), it will reject partial sentences that happen to contain fragments resembling numbers.
**How to avoid:** Verifier runs once, after the `for try await snapshot in stream` loop exits (meaning the stream is complete). Track the last snapshot explicitly; call `InsightVerifier.verify(finalInsight, against:)` only after the loop.

### Pitfall 9: `@available(iOS 26, *)` on the test file itself vs. `#available` at call sites

**What goes wrong:** The test target has `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. Tests cannot use `@available` on the test struct directly (Swift Testing structs can't have OS availability attributes at the struct level without making the entire file unavailable).
**How to avoid:** Wrap each test method that touches FoundationModels in `if #available(iOS 26, *) { ... }` or mark the individual `@Test` function `@available(iOS 26, *)`. The entire `InsightServiceTests.swift` can be gated with a `#if canImport(FoundationModels)` at the top if needed. Alternatively, since tests run on the iPhone 17 simulator (iOS 26.5), `#available(iOS 26, *)` checks always pass and the code compiles cleanly via the `@available(iOS 26, *)` attribute on mock types.

---

## Code Examples

### Availability Gating in AnalyticsView

```swift
// Source: pattern from CONTEXT.md + SDK confirmation
// In AnalyticsView.body LazyVStack, after AnalyticsCategoryBars:

if #available(iOS 26, *) {
    AIInsightCard(summary: summary)
        .padding(.top, 8)
}
// pre-iOS 26: nothing rendered
```

### Mock Session for Tests (Testability Seam)

```swift
// Source: design — testability seam for InsightGenerating protocol
// InsightServiceTests.swift

@available(iOS 26, *)
final class MockInsightService: InsightGenerating {
    // Configurable stub
    var result: Result<SpendInsight, Error> = .success(
        SpendInsight(observation: "Test observation.", suggestion: nil)
    )
    private(set) var callCount = 0

    func generate(for summary: SpendSummary) async throws -> SpendInsight {
        callCount += 1
        try await Task.yield() // allow cancellation to propagate
        return try result.get()
    }
}

// Test: guardrailViolation → fallback shown
@Test("guardrailViolation substitutes fallback text")
@available(iOS 26, *)
func testGuardrailViolationFallback() async throws {
    let mock = MockInsightService()
    mock.result = .failure(
        LanguageModelSession.GenerationError.guardrailViolation(.init())
    )
    // ... test ViewModel transitions to .fallback state ...
}
```

### `.task(id:)` for D-08 Cancellation

```swift
// Source: SwiftUI documentation pattern; confirmed as the standard cancel-on-id-change idiom
// When `summary.range` changes, SwiftUI cancels the previous task and starts a new one.

.task(id: summary.range) {
    await generateInsight()
}
```

### Breathing Orb (reusing DonutChart pattern)

```swift
// Source: DonutChart.swift line 316 — established in codebase
@State private var orbScale: CGFloat = 1.0

Circle()
    .fill(RadialGradient(
        colors: [.white.opacity(0.9), DesignTokens.aiVioletGlow],
        center: .init(x: 0.35, y: 0.30),
        startRadius: 0, endRadius: 6
    ))
    .frame(width: 11, height: 11)
    .scaleEffect(orbScale)
    .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            orbScale = 1.12
        }
    }
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Cloud LLM via URLSession | On-device `LanguageModelSession` | iOS 26 / Xcode 26 (2025) | Finance data never leaves device; works offline; no latency from network |
| Raw string response + regex parsing | `@Generable` struct + guided generation | iOS 26 | Compile-time schema; structured fields; no parsing needed |
| Manual `Task { }` with cancel flags | `.task(id:)` SwiftUI modifier | iOS 15 (now idiomatic) | Automatic cancel-on-id-change; no manual bookkeeping |
| Subclassing for mock | Protocol injection | — | `LanguageModelSession` is `final`; protocol is the only viable test seam |

**Deprecated/outdated:**
- `response.output`: Never existed. The API is always `.content`. (Common mis-guess from CoreML patterns.)
- Multi-session conversations for a single insight: unnecessary. A fresh session per range keeps transcripts clean and avoids context contamination.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `SpendInsight` initializer is synthesised by `@Generable` with the same field names as the struct | Code Examples (fallback construction) | Fallback `SpendInsight(observation:suggestion:)` init call would fail; use `GeneratedContent` init path instead |
| A2 | `InsightFallbackBuilder.build(for:)` returning `SpendInsight` directly requires a memberwise init; the `@Generable` macro may gate normal init | Code Examples — fallback | May need to create a separate `FallbackInsight` struct (non-Generable) for the fallback path; or check if `@Generable` preserves memberwise init |
| A3 | `partial.suggestion` in `PartiallyGenerated` is `String??` — outer Optional for "field not yet emitted", inner Optional for nil value | Pattern 2 / streaming code | If the type is just `String?` the nil check logic changes slightly |

---

## Open Questions

1. **`@Generable` + memberwise init compatibility**
   - What we know: `@Generable` attaches `@attached(member, ...)` macros that add conformance members. Standard memberwise `init` may or may not be preserved.
   - What's unclear: Can `InsightFallbackBuilder` construct a `SpendInsight(observation:suggestion:)` directly, or must it use `GeneratedContent`?
   - Recommendation: Planner should add a Wave 0 build-check task that confirms memberwise init compiles after applying `@Generable`. If not, `InsightFallbackBuilder` returns a plain struct `FallbackInsight { let observation: String; let suggestion: String? }` and the View uses a union type or protocol.

2. **Verifier regex for Indian number format**
   - What we know: Indian formatting uses `₹12,45,000` (lakh grouping). The prompt formatter uses standard `12,450`. The model may use either.
   - What's unclear: Will the model respect the exact formatting in the prompt or adopt Indian lakh separators?
   - Recommendation: The verifier normalises by stripping ALL commas and ₹ before Decimal comparison, which handles both formats.

3. **`LanguageModelSession.GenerationError` init for mock**
   - What we know: `GenerationError` has a `Context` associated value. The public `Context` init signature is not confirmed in the swiftinterface snippet above.
   - What's unclear: Can tests construct `GenerationError.guardrailViolation(.init())` directly, or is `Context` opaque?
   - Recommendation: If `Context` is not publicly constructible, wrap the error in a local error type for test stubs, and match on the error type in `catch` blocks using `is LanguageModelSession.GenerationError`.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | `@Generable` macro expansion, FoundationModels SDK | ✓ | 26.5 / Build 17F42 | — |
| iOS 26.5 Simulator SDK | FoundationModels.framework | ✓ | `iPhoneSimulator26.5.sdk` confirmed | — |
| iPhone 17 Simulator | Build + unit test target | ✓ | Booted (2F09365E) | iPhone 17 Pro also available |
| `FoundationModels.framework` | All AI code | ✓ | In iPhoneSimulator.sdk/Frameworks/ | — |
| Physical A17 Pro+ device | End-to-end AI generation test (Success Criterion 1) | Assumed (dev device per REQUIREMENTS.md) | — | Simulator cannot run Apple Intelligence; SC-1 requires device |

**Missing dependencies with no fallback:**
- Physical iOS 26 / Apple Intelligence device for Success Criterion 1. Unit tests (SC-5) run on simulator. SC-1 is a manual human-verify step, not automated.

**Missing dependencies with fallback:**
- None beyond the physical device gap.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) — confirmed used by `AnalyticsAggregatorTests.swift` |
| Config file | None — Xcode test target configuration via `project.pbxproj` |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/InsightServiceTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AI-02 (D-01) | `isInsightAvailable(.unavailable(.deviceNotEligible))` returns false | unit | `... -only-testing:MyHomeTests/InsightServiceTests` | ❌ Wave 0 |
| AI-02 (D-01) | `isInsightAvailable(.unavailable(.appleIntelligenceNotEnabled))` returns false | unit | same | ❌ Wave 0 |
| AI-02 (D-01) | `isInsightAvailable(.unavailable(.modelNotReady))` returns false | unit | same | ❌ Wave 0 |
| AI-02 (D-01) | `isInsightAvailable(.available)` returns true | unit | same | ❌ Wave 0 |
| AI-03 | `guardrailViolation` → ViewModel transitions to fallback | unit | same | ❌ Wave 0 |
| AI-03 | `exceededContextWindowSize` → ViewModel transitions to fallback | unit | same | ❌ Wave 0 |
| AI-04 | InsightVerifier rejects model-invented number, returns fallback | unit | `... -only-testing:MyHomeTests/InsightVerifierTests` | ❌ Wave 0 |
| AI-04 | InsightVerifier passes valid fact-only numbers | unit | same | ❌ Wave 0 |
| AI-05 (SC-5) | `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` returns `17.0` | shell | `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` | ✅ (already 17.0) |
| SC-5 | `xcodebuild clean build` succeeds | build | `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ✅ (gate) |
| AI-01, AI-03, AI-05 | Live insight on A17 Pro+ device, typewriter visible, no network | manual | Human-verify on device | — |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/InsightServiceTests -only-testing:MyHomeTests/InsightVerifierTests`
- **Per wave merge:** Full suite `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Phase gate:** Full suite green + simulator screenshot verify + physical device human-verify

### Wave 0 Gaps

- [ ] `MyHomeTests/InsightServiceTests.swift` — covers availability branches + error cases (AI-02, AI-03)
- [ ] `MyHomeTests/InsightVerifierTests.swift` — covers number extraction + match + fallback (AI-04)
- [ ] `MyHomeApp/Support/InsightService.swift` — `InsightGenerating` protocol declaration (needed by tests)
- [ ] `MyHomeApp/Support/InsightVerifier.swift` — stub needed by `InsightVerifierTests`

---

## Security Domain

`security_enforcement: true`, ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | LLM "session" is not a user auth session; single-use, discarded |
| V4 Access Control | No | — |
| V5 Input Validation | Yes (limited) | `InsightVerifier` validates model output before display; prompt is constructed from pre-typed `Decimal` facts — no user text injection |
| V6 Cryptography | No | — |
| V10 Malicious Code | Partial | Prompt injection risk: `SpendSummary` fields (category names from user data) are injected into the prompt. Category names come from the user's own data stored locally — low risk but names should be truncated to ≤ 30 chars to prevent prompt stuffing |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Prompt injection via category names | Tampering | Truncate category names to 30 characters in `InsightPromptBuilder`; they are user-defined and could contain unusual strings |
| Model-generated PII / hallucinated personal data | Information Disclosure | `InsightVerifier` rejects any number not in injected facts; no other PII injected; model cannot invent account numbers |
| Finance data leaving device | Information Disclosure | On-device `LanguageModelSession` exclusively; no `URLSession`; no network entitlement required for FoundationModels |
| Stale insight serving wrong range data | Tampering | `.task(id: summary.range)` + D-08 cancellation; view always passes current `summary` to `buildPrompt` |

---

## Sources

### Primary (HIGH confidence — verified from SDK)

- `FoundationModels.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (Xcode 26.5 / iOS 26.5 SDK) — all type shapes, enum cases, method signatures, and availability annotations verified directly from the compiled Swift module interface.
- `everything-claude-code:foundation-models-on-device` skill (SKILL.md) — patterns for `@Generable`, session init, snapshot streaming, tool calling, availability check.

### Secondary (MEDIUM confidence — codebase-verified patterns)

- `MyHomeApp/Support/AnalyticsAggregator.swift` — `SpendSummary` struct fields and their types confirmed directly.
- `MyHomeApp/Features/Analytics/AnalyticsView.swift` — integration point (LazyVStack bottom, `.task` pattern, `selectedRange` state) confirmed.
- `MyHomeApp/DesignSystem/DesignTokens.swift` — `neonGlow` modifier confirmed available; existing token names confirmed.
- `MyHomeApp/Features/Shared/DonutChart.swift` — breathing orb animation pattern (`scaleEffect` + `repeatForever`) confirmed.
- `MyHome.xcodeproj/project.pbxproj` — 4-edit pattern for `G_ANL` group confirmed; `IPHONEOS_DEPLOYMENT_TARGET = 17.0` confirmed across all targets.
- `design/design_handoff_myhome_neumorphic/src/analytics.jsx` lines 320-375 — violet hex values (#C4A6FF, #7C5CFF, #8B5CF6), typewriter timing (26ms/char ≈ 38 cps), orb dimensions (11pt/14pt), and edge glow CSS shadow values.
- `design/design_handoff_myhome_neumorphic/src/tokens.jsx` — neuro style shadow values and surface hex values confirmed.

### Tertiary (LOW confidence — not separately verified)

- Assumption A1/A2 (memberwise init on `@Generable` struct) — unverified; planner should add a Wave 0 compile-check task.
- `GenerationError.Context` public constructibility — not confirmed from swiftinterface; see Open Questions #3.

---

## Metadata

**Confidence breakdown:**
- FoundationModels API surface: HIGH — read directly from iOS 26.5 SDK swiftinterface
- Architecture/testability seam: HIGH — `final` class constraint confirmed from swiftinterface; protocol pattern is industry-standard
- InsightVerifier strategy: MEDIUM — design is sound but exact regex matching against Indian number formatting has one unverified edge case (lakh grouping)
- pbxproj edits: HIGH — confirmed by inspection of existing `G_ANL` group pattern

**Research date:** 2026-06-26
**Valid until:** 2026-09-26 (90 days; FoundationModels is post-shipping in Xcode 26 GA)
