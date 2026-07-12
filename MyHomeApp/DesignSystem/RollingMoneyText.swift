// RollingMoneyText.swift
// Animated headline money readout — honors Reduce Motion, formats INR with lakh grouping.
// Phase 13: DS-04
//
// DELIBERATE DEVIATION FROM UI-SPEC (DS-06 Dynamic Type):
// The UI-SPEC exposes `font: Font = .system(size: 46, …)` as a parameter. That signature
// passes a fixed 46pt literal through the API, defeating Dynamic Type (DS-06). Instead we
// use an instance `@ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46`
// so the size scales with the user's preferred text size. This deviation is intentional and
// documented here per plan instructions.

import SwiftUI

/// Animated INR money readout using `.contentTransition(.numericText())`.
///
/// When `accessibilityReduceMotion` is enabled, the digit roll is replaced by an
/// instant snap (`.identity` transition + `nil` animation — zero intermediate frames).
/// VoiceOver reads the final formatted value via `.accessibilityLabel`, never a mid-animation
/// interpolated value.
///
/// Usage:
/// ```swift
/// // Default (label color)
/// RollingMoneyText(amount: balance)
///
/// // Negative/spent amount in caller-specified color (Phase 14 pattern)
/// RollingMoneyText(amount: spent, color: DesignTokens.negative)
/// ```
struct RollingMoneyText: View {
    let amount: Decimal
    var currencyCode: String = "INR"
    var locale: Locale = Locale(identifier: "en_IN")
    /// Color applied via `.foregroundStyle`. Callers pass `DesignTokens.negative` for
    /// negative/spent amounts (Phase 14 pattern). Defaults to `DesignTokens.label` (#ECEDF4).
    var color: Color = DesignTokens.label
    var animationDuration: Double = 0.78
    /// Font weight for the readout. Defaults to `.ultraLight` (DS hero spec). The Overview
    /// hero overrides this to a heavier weight to read as solid (closer to the pre-v1.2 look).
    var weight: Font.Weight = .ultraLight
    /// Font design. Defaults to `.rounded`; the Overview hero passes `.default` for a more
    /// solid, less delicate numeral matching the previous version.
    var design: Font.Design = .rounded

    // DS-06 Dynamic Type: @ScaledMetric instance property (NOT static) anchored to .largeTitle.
    // This satisfies the heroMoney typography spec (46pt base) while scaling with the user's
    // preferred text size. A static or hardcoded 46pt literal would violate DS-06.
    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formatted: String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: baseSize, weight: weight, design: design))
            .foregroundStyle(color)
            .monospacedDigit()
            // contentTransition + animation MUST be paired (RESEARCH Pitfall 6):
            // omitting .animation makes the transition silent — digits never roll.
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth(duration: animationDuration), value: amount)
            // VoiceOver reads the final formatted value — never the mid-animation interpolation.
            .accessibilityLabel("₹\(formatted)")
    }
}

// MARK: - Preview

#Preview("RollingMoneyText — digit roll demo") {
    RollingMoneyTextPreview()
        .background(DesignTokens.bgCanvas)
        .preferredColorScheme(.dark)
}

private struct RollingMoneyTextPreview: View {
    @State private var amount: Decimal = 123456.78
    @State private var useNegativeColor = false

    var body: some View {
        VStack(spacing: DesignTokens.spacing24) {

            // Hero money display
            RollingMoneyText(
                amount: amount,
                color: useNegativeColor ? DesignTokens.negative : DesignTokens.label
            )

            // Stat variant — use a separate instance with a smaller @ScaledMetric base
            // (demonstrates callers can compose without a font: parameter)
            Text(amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
                .font(.system(size: 21, weight: .light, design: .rounded))
                .foregroundStyle(DesignTokens.label2)
                .monospacedDigit()

            VStack(spacing: DesignTokens.spacing8) {
                // Roll up
                Button("Roll up (₹2,34,567.89)") {
                    amount = 234567.89
                }
                // Roll down
                Button("Roll down (₹56,789.00)") {
                    amount = 56789.00
                }
                // Toggle color (simulates Phase 14 negative amount)
                Button(useNegativeColor ? "Color: negative (red)" : "Color: label (default)") {
                    useNegativeColor.toggle()
                }
            }
            .foregroundStyle(DesignTokens.accentText)
            .font(.body)

            Text("To test Reduce Motion: Simulator → Settings → Accessibility → Motion → Reduce Motion ON.\nDigit roll should snap to target with zero intermediate frames.")
                .font(.caption)
                .foregroundStyle(DesignTokens.label3)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.spacing16)
    }
}
