// AIInsightCard.swift
// Phase 16 Plan 04: AI Insight Card — full implementation.
//
// Replaces the Plan 01 stub with the complete view:
//   - Runtime availability switch via isInsightAvailable() (D-01/D-02/AI-02)
//   - Neumorphic base (.neuSurface(.raised), D-03)
//   - Violet edge-glow (DesignTokens.aiViolet*, neonGlow, D-04)
//   - "AI INSIGHT" sparkles label header (D-04)
//   - Breathing orb while generating, hidden under Reduce Motion (D-04/SC-3)
//   - Streaming typewriter reveal via streamResponse (AI-05)
//   - Reduce Motion: instant full text, no orb (SC-3)
//   - .task(id: summary.range) auto-generate + auto-cancel on range change (D-07/D-08)
//   - InsightVerifier.verify once at stream end; fallback on rejection or error (AI-04/AI-03)
//   - No persistence: all state lives in @State (AI-05)
//
// Call site in AnalyticsView (Plan 04):
//   if #available(iOS 26, *) {
//       AIInsightCard(summary: summary).padding(.top, 8)
//   }

import SwiftUI
import FoundationModels

// MARK: - AIInsightCard

/// On-device AI spending insight card, available iOS 26+ only.
///
/// Two-layer availability gating (AI-01/AI-02):
///   1. `#available(iOS 26, *)` compile-time guard at the call site in `AnalyticsView`
///   2. `SystemLanguageModel.default.availability` runtime guard in `body`
///
/// On ANY unavailable branch — `deviceNotEligible`, `appleIntelligenceNotEnabled`,
/// `modelNotReady`, or pre-iOS-26 — the view returns `EmptyView` (D-01/SC-2).
/// No shell, no gap, no spinner. Nothing.
@available(iOS 26, *)
struct AIInsightCard: View {

    /// The pre-aggregated spend data for the currently selected range.
    /// Passed fresh by `AnalyticsView` on every range change; triggers `.task(id:)` restart (D-08).
    let summary: SpendSummary

    // MARK: - State

    @State private var displayedObservation = ""
    @State private var displayedSuggestion: String? = nil
    @State private var isGenerating = false
    @State private var orbPulsing = false

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        // Runtime availability guard (D-01/D-02).
        // SystemLanguageModel is @Observable → SwiftUI auto-refreshes if availability changes.
        if isInsightAvailable(SystemLanguageModel.default.availability) {
            cardChrome
                // D-07: auto-generate when card appears.
                // D-08: .task(id:) auto-cancels the prior run when summary.range changes.
                .task(id: summary.range) {
                    await generateInsight()
                }
        }
        // On all unavailable branches: EmptyView (D-01/SC-2) — no shell, no gap.
    }

    // MARK: - Card Chrome

    @ViewBuilder
    private var cardChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if !displayedObservation.isEmpty || isGenerating {
                textContent
            }
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 20, trailing: 20))
        .neuSurface(.raised, padding: nil)
        .overlay(alignment: .leading) {
            violetEdgeBand
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // sparkles SF Symbol label (D-04)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.aiVioletTop)
            Text("AI INSIGHT")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(DesignTokens.aiVioletTop)
            Spacer()
            // Breathing orb: visible only while generating AND Reduce Motion is off (SC-3/D-04)
            if isGenerating && !reduceMotion {
                breathingOrb
            }
        }
    }

    // MARK: - Text Content

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayedObservation)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(DesignTokens.label)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                // Reserve height while generating so the card doesn't collapse to a header-only card
                .frame(minHeight: displayedObservation.isEmpty ? 44 : 0, alignment: .leading)
            if let suggestion = displayedSuggestion, !suggestion.isEmpty {
                Text(suggestion)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DesignTokens.label2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Violet Edge Band (D-04)

    /// A 4pt linear-gradient band at the leading edge with a violet neon glow.
    /// Mirrors the design's `lqa-edgeglow` element (analytics.jsx ~line 343).
    private var violetEdgeBand: some View {
        LinearGradient(
            colors: [DesignTokens.aiVioletTop, DesignTokens.aiVioletBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 4)
        // Round only the leading corners to match the card's corner radius (D-04)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: DesignTokens.radiusCard,
                    bottomLeading: DesignTokens.radiusCard,
                    bottomTrailing: 0,
                    topTrailing: 0
                )
            )
        )
        .neonGlow(DesignTokens.aiVioletGlow, radius: 8, intensity: 1)
    }

    // MARK: - Breathing Orb (D-04)

    /// Pulsing orb shown in the header during active generation (SC-3: hidden under Reduce Motion).
    ///
    /// Replicates the design's `lqa-orbring` expanding ring + `lqa-orb` breathing sphere
    /// animation pattern from analytics.jsx ~line 359. Uses the same `scaleEffect` +
    /// `.easeInOut(duration:).repeatForever(autoreverses:)` pattern from DonutChart.swift.
    private var breathingOrb: some View {
        ZStack {
            // Expanding ring pulse (lqa-orbring)
            Circle()
                .stroke(DesignTokens.aiVioletGlow.opacity(0.5), lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .scaleEffect(orbPulsing ? 1.35 : 1.0)
                .opacity(orbPulsing ? 0.0 : 0.8)
            // Core orb with radial gradient (lqa-orb)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.9), DesignTokens.aiVioletGlow],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .frame(width: 11, height: 11)
                .scaleEffect(orbPulsing ? 1.08 : 1.0)
        }
        .onAppear {
            // DonutChart pattern: scaleEffect + easeInOut repeatForever
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                orbPulsing = true
            }
        }
        .onDisappear {
            // Reset so next appearance starts from resting state
            orbPulsing = false
        }
    }

    // MARK: - Generation Lifecycle

    /// Runs a single generation: build prompt → stream response → verify → update display.
    ///
    /// Called from `.task(id: summary.range)` which provides D-07 (auto-run on appear) and
    /// D-08 (auto-cancel on range change via Swift structured concurrency `CancellationError`).
    ///
    /// Fresh `LanguageModelSession` per call (Pitfall 3 / T-16-04): no transcript carryover.
    private func generateInsight() async {
        displayedObservation = ""
        displayedSuggestion = nil
        isGenerating = true
        orbPulsing = false
        defer { isGenerating = false }

        // Fresh session per generation (Pitfall 3 / T-16-04)
        let session = LanguageModelSession(
            instructions: InsightPromptBuilder.systemInstructions
        )
        let prompt = InsightPromptBuilder.buildPrompt(for: summary)

        do {
            if reduceMotion {
                // SC-3: Reduce Motion — instant full text, no orb, no typewriter animation.
                let response = try await session.respond(
                    to: prompt,
                    generating: SpendInsight.self
                )
                // Pitfall 8: verify ONCE after complete response (never mid-stream)
                let verified = InsightVerifier.verify(response.content, against: summary)
                displayedObservation = verified.observation
                displayedSuggestion = verified.suggestion

            } else {
                // Normal path: live streaming typewriter reveal via snapshot accumulation.
                var lastPartial: SpendInsight.PartiallyGenerated?
                let stream = session.streamResponse(to: prompt, generating: SpendInsight.self)

                for try await snapshot in stream {
                    // Pitfall 4: .observation on PartiallyGenerated is String? (nil until first token)
                    displayedObservation = snapshot.content.observation ?? ""
                    // .suggestion on PartiallyGenerated is String?? (outer nil until field starts)
                    if let s = snapshot.content.suggestion {
                        // s: String? (outer optional unwrapped; inner nil = model chose no suggestion)
                        displayedSuggestion = s
                    }
                    lastPartial = snapshot.content
                }

                // Stream ended: reconstruct final SpendInsight for one-time verification (Pitfall 8).
                // Use flatMap to safely flatten PartiallyGenerated.observation (String?) → String? → String.
                // displayedSuggestion already accumulates the latest suggestion from every snapshot.
                let finalObservation: String =
                    lastPartial.flatMap { $0.observation } ?? displayedObservation
                let finalInsight = SpendInsight(
                    observation: finalObservation,
                    suggestion: displayedSuggestion
                )
                let verified = InsightVerifier.verify(finalInsight, against: summary)

                // Atomically replace with verified text (in-place if passed; fallback if not — AI-04)
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayedObservation = verified.observation
                    displayedSuggestion = verified.suggestion
                }
            }

        } catch is CancellationError {
            // D-08: task cancelled by range change — clear state silently, never show stale insight.
            displayedObservation = ""
            displayedSuggestion = nil

        } catch {
            // AI-03: GenerationError (.guardrailViolation, .exceededContextWindowSize, etc.)
            // or any other error → templated fallback. Never shows an error message (D-05).
            let fallback = InsightFallbackBuilder.build(for: summary)
            displayedObservation = fallback.observation
            displayedSuggestion = fallback.suggestion
        }
    }
}
