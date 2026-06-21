// NeuTabBar.swift
// Floating capsule tab bar replacing stock TabView chrome — Plan 02 implements the full body.
// Phase 13: DS-03

import SwiftUI

/// Floating neumorphic tab bar.
/// Full implementation (active pill animation, safe-area insets, deep-link support) ships in Plan 02.
struct NeuTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabs: [(id: Int, label: String, icon: String, activeIcon: String)] = [
        (0, "Home",     "house",       "house.fill"),
        (1, "Activity", "creditcard",  "creditcard.fill"),
        (2, "Budgets",  "chart.pie",   "chart.pie.fill"),
        (3, "Notes",    "note.text",   "note.text"),
        (4, "Settings", "gear",        "gear"),
    ]

    var body: some View {
        // Stub — full neumorphic capsule implementation in Plan 02
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                Button {
                    selectedTab = tab.id
                } label: {
                    VStack(spacing: DesignTokens.spacing2) {
                        Image(systemName: selectedTab == tab.id ? tab.activeIcon : tab.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(selectedTab == tab.id ? DesignTokens.accent : DesignTokens.label2)
                        Text(tab.label)
                            .foregroundStyle(selectedTab == tab.id ? DesignTokens.accent : DesignTokens.label2)
                    }
                    .frame(width: DesignTokens.tabItemWidth, height: DesignTokens.tabBarHeight)
                }
            }
        }
        .background(DesignTokens.surfaceRaisedStrong)
        .clipShape(Capsule())
        .padding(.bottom, DesignTokens.tabBarBottomOffset)
    }
}
