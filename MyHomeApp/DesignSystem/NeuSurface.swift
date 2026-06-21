// NeuSurface.swift
// Neumorphic surface ViewModifier — raised / floating / recessed states.
// Replaces CardStyle entirely for v1.2 screens.
// Phase 13: DS-02

import SwiftUI

/// State of a neumorphic surface.
enum NeuSurfaceState {
    /// Standard extruded card — dual outer shadow (light top-left, dark bottom-right) + inner rim.
    case raised
    /// Hero-tier card / floating element — deeper dual outer shadow + inner rim.
    case floating
    /// Sunken well — overlay-gradient inset approximation; no outer shadow, no rim.
    case recessed
}

/// ViewModifier that wraps any content in a neumorphic surface.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .neuSurface(.raised)
///
/// // Interactive (tappable) card adds a glassBorder boundary affordance (DS-06):
/// Button("Tap") { ... }
///     .neuSurface(.raised, isInteractive: true)
/// ```
struct NeuSurface: ViewModifier {
    var state: NeuSurfaceState
    var radius: CGFloat = DesignTokens.radiusCard
    var padding: CGFloat? = 16
    /// When `true`, adds a 0.5pt `DesignTokens.glassBorder` stroke overlay to satisfy
    /// WCAG 1.4.11 (3:1) non-text contrast: shadow depth is never the sole boundary affordance (DS-06).
    var isInteractive: Bool = false

    // MARK: - Fill

    private var fill: Color {
        switch state {
        case .raised:    return DesignTokens.surfaceRaised
        case .floating:  return DesignTokens.surfaceRaisedStrong
        case .recessed:  return DesignTokens.fillRecessed3
        }
    }

    // MARK: - Shadow spec (raised / floating only)

    private var shadowSpec: DesignTokens.ShadowSpec? {
        switch state {
        case .raised:    return DesignTokens.shadowRaised
        case .floating:  return DesignTokens.shadowFloat
        case .recessed:  return nil   // recessed uses overlay-gradient inset, no outer shadow
        }
    }

    // MARK: - Body

    func body(content: Content) -> some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // --- Outer dual shadow (raised / floating only — light FIRST, dark SECOND per RESEARCH Pitfall 2)
        .modifier(OuterShadowModifier(spec: shadowSpec))
        // --- Inner rim overlay for raised / floating
        .modifier(RimOverlayModifier(state: state, radius: radius))
        // --- Recessed inset approximation (overlay gradient)
        .modifier(RecessedOverlayModifier(state: state, radius: radius))
        // --- WCAG 1.4.11 interactive boundary affordance (DS-06)
        .modifier(InteractiveBorderModifier(isInteractive: isInteractive, radius: radius))
    }
}

// MARK: - Outer shadow sub-modifier

/// Applies the dual outer shadow (light first, dark second) from a ShadowSpec.
/// Extracted to a separate modifier so the `body` chain stays readable.
private struct OuterShadowModifier: ViewModifier {
    let spec: DesignTokens.ShadowSpec?

    func body(content: Content) -> some View {
        if let spec {
            content
                // Light shadow first (top-left highlight)
                .shadow(color: spec.lightColor, radius: spec.lightRadius, x: spec.lightX, y: spec.lightY)
                // Dark shadow second (bottom-right depth)
                .shadow(color: spec.darkColor,  radius: spec.darkRadius,  x: spec.darkX,  y: spec.darkY)
        } else {
            content
        }
    }
}

// MARK: - Inner rim overlay (raised / floating)

/// Adds a strokeBorder rim gradient for raised/floating states.
/// Gradient runs white 4.5% → black 30% top-leading → bottom-trailing,
/// replicating the inner light/dark rim from the UI-SPEC shadowRim spec.
private struct RimOverlayModifier: ViewModifier {
    let state: NeuSurfaceState
    let radius: CGFloat

    private var showRim: Bool {
        state == .raised || state == .floating
    }

    func body(content: Content) -> some View {
        content.overlay {
            if showRim {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.045),
                                Color.black.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Recessed inset approximation

/// For `.recessed`, overlays a gradient that makes the surface appear sunken.
/// SwiftUI has no native inset shadow. We approximate it with a gradient overlay:
/// dark in top-left + light in bottom-right, giving the illusion of light coming
/// from the top (RESEARCH Open Question 1 — overlay-gradient is the default approach;
/// the fillRecessed3 color being darker than bgCanvas carries the primary sunken look).
private struct RecessedOverlayModifier: ViewModifier {
    let state: NeuSurfaceState
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if state == .recessed {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.30),
                                Color.white.opacity(0.025)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Interactive boundary affordance (DS-06)

/// When `isInteractive` is true, adds a 0.5pt `DesignTokens.glassBorder` stroke.
/// Ensures WCAG 1.4.11 (3:1) non-text contrast: the shadow alone is insufficient
/// as a boundary affordance because shadows at 3.5% white opacity are below threshold.
private struct InteractiveBorderModifier: ViewModifier {
    let isInteractive: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if isInteractive {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DesignTokens.glassBorder, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - View extension

extension View {
    /// Wraps the view in a neumorphic surface (padding + fill + clip + dual shadow + rim).
    ///
    /// - Parameters:
    ///   - state: `.raised` (standard card), `.floating` (hero/tab-bar), or `.recessed` (input/track).
    ///   - radius: Corner radius; defaults to `DesignTokens.radiusCard` (26pt).
    ///   - padding: Inner padding; pass `nil` if the caller handles padding.
    ///   - isInteractive: When `true`, adds a `glassBorder` stroke affordance (DS-06).
    func neuSurface(
        _ state: NeuSurfaceState,
        radius: CGFloat = DesignTokens.radiusCard,
        padding: CGFloat? = 16,
        isInteractive: Bool = false
    ) -> some View {
        modifier(NeuSurface(state: state, radius: radius, padding: padding, isInteractive: isInteractive))
    }
}

// MARK: - Preview

#Preview("NeuSurface — all three states") {
    ScrollView {
        VStack(spacing: DesignTokens.spacing22) {

            // Raised — standard card
            VStack(alignment: .leading, spacing: 8) {
                Text("Raised").font(.caption).foregroundStyle(DesignTokens.label2)
                Text("Standard card surface")
                    .foregroundStyle(DesignTokens.label)
                    .neuSurface(.raised)
            }

            // Floating — hero card
            VStack(alignment: .leading, spacing: 8) {
                Text("Floating").font(.caption).foregroundStyle(DesignTokens.label2)
                Text("Hero / tab-bar surface")
                    .foregroundStyle(DesignTokens.label)
                    .neuSurface(.floating)
            }

            // Recessed — input well
            VStack(alignment: .leading, spacing: 8) {
                Text("Recessed").font(.caption).foregroundStyle(DesignTokens.label2)
                Text("Input / track surface")
                    .foregroundStyle(DesignTokens.label)
                    .neuSurface(.recessed)
            }

            // Interactive (raised + glassBorder DS-06 affordance)
            VStack(alignment: .leading, spacing: 8) {
                Text("Interactive (raised)").font(.caption).foregroundStyle(DesignTokens.label2)
                Text("Tappable card — glassBorder visible at 0.5pt")
                    .foregroundStyle(DesignTokens.label)
                    .neuSurface(.raised, isInteractive: true)
            }
        }
        .padding(DesignTokens.spacing16)
    }
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}
