// FloatingNavBar.swift
// Custom floating, neumorphic nav bar rendered OVER a plain TabView(selection:) whose own
// native tab bar is hidden. Phase 24 (NAV-01) — re-attempt of the Phase 13 NeuTabBar concept
// (DS-03), which was reverted in Phase 14 because it tried to RESTYLE the native TabView bar —
// a native bar can't glow/float. This time the bar is genuinely custom: it owns its own
// styling and geometry, detached from the screen edge, and simply drives `selectedTab`.
//
// Five items, same order/destinations as RootView's TabView tags (0…4):
//   0 Home · 1 Expenses · 2 Budgets · 3 Notes · 4 Settings
// Icons match the ones already used in RootView's (now-hidden) native tabItem labels so the
// iconography stays consistent with any lingering VoiceOver/Spotlight tab metadata.

import SwiftUI

struct FloatingNavBar: View {
    @Binding var selectedTab: Int
    /// Expenses review-inbox badge count (mirrors the native `.badge(reviewBadgeCount)` on tag 1).
    var reviewBadgeCount: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    private struct Tab {
        let id: Int
        let label: String
        let icon: String
        let activeIcon: String
    }

    private let tabs: [Tab] = [
        Tab(id: 0, label: "Home",     icon: "house",       activeIcon: "house.fill"),
        Tab(id: 1, label: "Expenses", icon: "list.bullet",  activeIcon: "list.bullet"),
        Tab(id: 2, label: "Budgets",  icon: "chart.bar",    activeIcon: "chart.bar.fill"),
        Tab(id: 3, label: "Notes",    icon: "note.text",    activeIcon: "note.text"),
        Tab(id: 4, label: "Settings", icon: "gearshape",    activeIcon: "gearshape.fill"),
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(tabs, id: \.id) { tab in
                    tabButton(tab: tab)
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
            // Dual outer shadow — floating element spec (light first, dark second)
            .shadow(color: DesignTokens.shadowFloat.lightColor,
                    radius: DesignTokens.shadowFloat.lightRadius,
                    x: DesignTokens.shadowFloat.lightX,
                    y: DesignTokens.shadowFloat.lightY)
            .shadow(color: DesignTokens.shadowFloat.darkColor,
                    radius: DesignTokens.shadowFloat.darkRadius,
                    x: DesignTokens.shadowFloat.darkX,
                    y: DesignTokens.shadowFloat.darkY)
            // Neon bloom in dark, whisper drop-shadow in light — detaches the bar from the canvas.
            .neonGlow(DesignTokens.accent, radius: 10, intensity: 0.35)
            // Safe-area-aware bottom offset — floats detached from the screen edge.
            .padding(.bottom, max(DesignTokens.tabBarBottomOffset,
                                  geometry.safeAreaInsets.bottom + 8))
            .padding(.horizontal, DesignTokens.spacing16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // GeometryReader expands to fill; constrain height so it doesn't push content.
        .frame(height: DesignTokens.tabBarHeight + DesignTokens.tabBarBottomOffset + 34)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func tabButton(tab: Tab) -> some View {
        let isActive = selectedTab == tab.id
        Button {
            if selectedTab != tab.id {
                Haptics.selection()
                selectedTab = tab.id
            }
        } label: {
            ZStack(alignment: .top) {
                // Active sliding pill (matchedGeometryEffect for spring slide — DS-03)
                if isActive {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(DesignTokens.accentSoft)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(DesignTokens.accent.opacity(0.35), lineWidth: 0.5)
                        }
                        .shadow(color: DesignTokens.accent.opacity(0.22), radius: 8)
                        .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                        .animation(reduceMotion ? nil : DesignTokens.springBouncy, value: selectedTab)
                        .frame(width: DesignTokens.tabItemWidth,
                               height: DesignTokens.tabBarHeight - DesignTokens.spacing12)
                }

                // Icon + label
                VStack(spacing: DesignTokens.spacing2) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isActive ? tab.activeIcon : tab.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(isActive ? DesignTokens.accentText : DesignTokens.label2)
                        if tab.id == 1 && reviewBadgeCount > 0 {
                            Text(reviewBadgeCount > 99 ? "99+" : "\(reviewBadgeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.accentOnYellow)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DesignTokens.accent))
                                .offset(x: 10, y: -6)
                        }
                    }
                    Text(tab.label)
                        .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? DesignTokens.accentText : DesignTokens.label2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityHint("Tab \(tab.id + 1) of \(tabs.count)")
    }
}

#Preview("Dark") {
    struct PreviewWrapper: View {
        @State private var selectedTab: Int = 0
        var body: some View {
            ZStack(alignment: .bottom) {
                DesignTokens.bgCanvas.ignoresSafeArea()
                VStack { Text("Tab \(selectedTab)").foregroundStyle(DesignTokens.label); Spacer() }
                FloatingNavBar(selectedTab: $selectedTab, reviewBadgeCount: 3)
            }
        }
    }
    return PreviewWrapper().preferredColorScheme(.dark)
}

#Preview("Light") {
    struct PreviewWrapper: View {
        @State private var selectedTab: Int = 0
        var body: some View {
            ZStack(alignment: .bottom) {
                DesignTokens.bgCanvas.ignoresSafeArea()
                VStack { Text("Tab \(selectedTab)").foregroundStyle(DesignTokens.label); Spacer() }
                FloatingNavBar(selectedTab: $selectedTab, reviewBadgeCount: 3)
            }
        }
    }
    return PreviewWrapper().preferredColorScheme(.light)
}
