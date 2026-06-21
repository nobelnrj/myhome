// NeuTabBar.swift
// Floating capsule tab bar replacing stock TabView chrome.
// Phase 13: DS-03
//
// Layout contract (from 13-UI-SPEC.md):
//   Capsule height: 62pt  Corner radius: 34pt
//   Active pill: 58×50pt  corner radius: 26pt  fill: accentSoft
//   Bottom offset: max(tabBarBottomOffset, safeAreaInsets.bottom + 8)
//   VoiceOver: accessibilityLabel(tab.label) + accessibilityHint("Tab N of 5")

import SwiftUI

struct NeuTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    private let tabs: [(id: Int, label: String, icon: String, activeIcon: String)] = [
        (0, "Home",     "house",       "house.fill"),
        (1, "Activity", "creditcard",  "creditcard.fill"),
        (2, "Budgets",  "chart.pie",   "chart.pie.fill"),
        (3, "Notes",    "note.text",   "note.text"),
        (4, "Settings", "gear",        "gear"),
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    tabButton(tab: tab, index: index)
                }
            }
            .frame(height: DesignTokens.tabBarHeight)
            .background(DesignTokens.surfaceRaisedStrong)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusTabBar, style: .continuous))
            // Rim overlay (glassBorder boundary affordance — DS-06 WCAG 1.4.11)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radiusTabBar, style: .continuous)
                    .strokeBorder(DesignTokens.glassBorder, lineWidth: 0.5)
            }
            // Dual outer shadow — floating element spec (light first, dark second — Pitfall 2)
            .shadow(color: DesignTokens.shadowFloat.lightColor,
                    radius: DesignTokens.shadowFloat.lightRadius,
                    x: DesignTokens.shadowFloat.lightX,
                    y: DesignTokens.shadowFloat.lightY)
            .shadow(color: DesignTokens.shadowFloat.darkColor,
                    radius: DesignTokens.shadowFloat.darkRadius,
                    x: DesignTokens.shadowFloat.darkX,
                    y: DesignTokens.shadowFloat.darkY)
            // Safe-area-aware bottom offset (Pitfall 5 — reads safeAreaInsets.bottom)
            .padding(.bottom, max(DesignTokens.tabBarBottomOffset,
                                  geometry.safeAreaInsets.bottom + 8))
            .frame(maxWidth: .infinity)
        }
        // GeometryReader expands to fill; constrain height so it doesn't push content
        .frame(height: DesignTokens.tabBarHeight + DesignTokens.tabBarBottomOffset + 34)
    }

    @ViewBuilder
    private func tabButton(tab: (id: Int, label: String, icon: String, activeIcon: String), index: Int) -> some View {
        let isActive = selectedTab == tab.id
        Button {
            selectedTab = tab.id
        } label: {
            ZStack {
                // Active sliding pill (matchedGeometryEffect for spring slide — DS-03)
                if isActive {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(DesignTokens.accentSoft)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(
                                    Color(hex: "#FFD60A").opacity(0.35),
                                    lineWidth: 0.5
                                )
                        }
                        .shadow(color: DesignTokens.accent.opacity(0.22), radius: 8)
                        .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                        // Animation gated by reduceMotion (DS-06, UI-SPEC Motion Contract)
                        .animation(reduceMotion ? nil : DesignTokens.springBouncy, value: selectedTab)
                        .frame(width: DesignTokens.tabItemWidth,
                               height: DesignTokens.tabBarHeight - DesignTokens.spacing12)
                }

                // Icon + label
                VStack(spacing: DesignTokens.spacing2) {
                    Image(systemName: isActive ? tab.activeIcon : tab.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isActive ? DesignTokens.accent : DesignTokens.label2)
                    Text(tab.label)
                        .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? DesignTokens.accent : DesignTokens.label2)
                }
            }
            .frame(width: DesignTokens.tabItemWidth, height: DesignTokens.tabBarHeight)
        }
        .buttonStyle(.plain)
        // VoiceOver contract (DS-06 / 13-UI-SPEC VoiceOver labels)
        .accessibilityLabel(tab.label)
        .accessibilityHint("Tab \(index + 1) of 5")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: Int = 0
        var body: some View {
            ZStack(alignment: .bottom) {
                DesignTokens.bgCanvas
                    .ignoresSafeArea()
                VStack {
                    Text("Tab \(selectedTab)")
                        .foregroundStyle(DesignTokens.label)
                    Spacer()
                }
                NeuTabBar(selectedTab: $selectedTab)
            }
        }
    }
    return PreviewWrapper()
}
