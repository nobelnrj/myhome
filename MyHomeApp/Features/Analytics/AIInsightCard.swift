// AIInsightCard.swift
// Phase 16: AI Insight Card — view stub (Plan 01).
//
// Stub returned in Wave 1. Plan 04 fills in the full card UI:
//   - Neumorphic base (.neuSurface(.raised), D-03)
//   - Violet edge glow (DesignTokens.aiViolет*, D-04)
//   - Breathing orb (isGenerating state, D-07)
//   - Streaming typewriter reveal (AI-05)
//   - Runtime availability gating (SystemLanguageModel.default.availability, D-01/D-02)
//   - .task(id: summary.range) auto-cancel on range change (D-08)
//
// Integration point (AnalyticsView, Plan 04):
//   if #available(iOS 26, *) {
//       AIInsightCard(summary: summary)
//           .padding(.top, 8)
//   }
//
// Pre-iOS 26: the if #available guard means this struct is never instantiated on older OS.

import SwiftUI

// MARK: - AIInsightCard

/// AI-powered spending insight card, gated to iOS 26+ (FoundationModels requirement).
///
/// On iOS 26 with Apple Intelligence available: generates a terse, data-grounded
/// spending observation via `InsightService` and streams it with a typewriter reveal.
/// On iOS 26 with Apple Intelligence unavailable: returns `EmptyView` (D-01/D-02 — no shell card).
///
/// Stub: always renders `EmptyView`. Plan 04 implements the full card.
@available(iOS 26, *)
struct AIInsightCard: View {

    /// The pre-aggregated spend data for the currently selected range.
    /// Passed fresh by `AnalyticsView` on every range change; triggers `.task(id:)` restart (D-08).
    let summary: SpendSummary

    var body: some View {
        EmptyView()
        // stub — Plan 04 implements:
        //   availability gating → card content OR EmptyView
        //   violet edge glow, breathing orb, typewriter reveal
    }
}
