// NeuSurface.swift
// Neumorphic surface ViewModifier — Plan 02 implements the full body.
// Phase 13: DS-02

import SwiftUI

/// State of a neumorphic surface.
enum NeuSurfaceState {
    case raised    // Standard extruded card — dual outer shadow
    case floating  // Hero-tier card / floating element — deeper dual outer shadow
    case recessed  // Sunken well — dual inset shadow, no rim
}

/// ViewModifier that wraps any content in a neumorphic surface.
/// Full implementation ships in Plan 02.
struct NeuSurface: ViewModifier {
    var state: NeuSurfaceState
    var radius: CGFloat = DesignTokens.radiusCard
    var padding: CGFloat? = 16

    func body(content: Content) -> some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func neuSurface(
        _ state: NeuSurfaceState,
        radius: CGFloat = DesignTokens.radiusCard,
        padding: CGFloat? = 16
    ) -> some View {
        modifier(NeuSurface(state: state, radius: radius, padding: padding))
    }
}
