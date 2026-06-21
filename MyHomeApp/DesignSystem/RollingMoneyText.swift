// RollingMoneyText.swift
// Animated headline money readout — Plan 02 implements the full animation.
// Phase 13: DS-04

import SwiftUI

/// Animated INR money readout using `.contentTransition(.numericText())`.
/// Full animation implementation ships in Plan 02.
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
