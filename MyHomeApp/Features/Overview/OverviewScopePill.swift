import SwiftUI

/// The Overview header scope pill (OVF-03) — a single always-present control that is BOTH the
/// filter entry point AND the active-state display (UI-REFERENCE Decision 3, which replaces the
/// planned separate chip bar).
///
/// - Inactive: a neutral dot + "All accounts" + a chevron; the whole capsule opens the filter sheet.
/// - Active: an accent dot + a summary label naming the selection (accounts and/or custom range),
///   so filtered figures can never masquerade as all-account totals (threat T-21-05). A trailing
///   `xmark.circle.fill` replaces the chevron; ONE tap on it clears the filter without opening the
///   sheet (`onClear` → `OverviewFilter()`), while tapping the label still opens the sheet.
///
/// Pure presentation — no @Query, no fetching. The caller resolves `accountNames` and gates the
/// clear action. Styled with existing neumorphic tokens only (no DesignSystem edits).
struct OverviewScopePill: View {
    let filter: OverviewFilter
    /// Resolved names of the selected accounts (plus "Unassigned" when included). Empty when only
    /// a custom date range is active — the label then shows just the range.
    let accountNames: [String]
    /// Opens the filter sheet.
    let onTap: () -> Void
    /// Resets to `OverviewFilter()` — a single tap, no confirmation (OVF-03).
    let onClear: () -> Void

    var body: some View {
        // WR-03: the label and the clear button are SIBLING buttons in the HStack, each sized to
        // its own bounds, rather than a 44×44 clear overlay pinned over the capsule. This confines
        // the clear tap target to the xmark so a tap on the trailing edge of the label can never
        // silently wipe the filter (clear has no confirmation — OVF-03).
        HStack(spacing: 7) {
            Button(action: onTap) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(filter.isActive ? DesignTokens.accent : DesignTokens.label3)
                        .frame(width: 8, height: 8)
                    Text(summaryLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if !filter.isActive {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if filter.isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignTokens.label3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filters")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, filter.isActive ? 6 : 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(LinearGradient(
                colors: [DesignTokens.surfaceRaisedStrongTop, DesignTokens.surfaceRaisedStrongBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [DesignTokens.neuRimTop, DesignTokens.neuRimBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        )
        .shadow(color: DesignTokens.neuOuterHighlight, radius: 6, x: -4, y: -4)
        .shadow(color: DesignTokens.neuOuterShade, radius: 7, x: 5, y: 5)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Summary label

    private var summaryLabel: String {
        guard filter.isActive else { return "All accounts" }
        var parts: [String] = []
        if let first = accountNames.first {
            parts.append(accountNames.count > 1 ? "\(first) +\(accountNames.count - 1)" : first)
        }
        if let range = filter.dateRange {
            // WR-01 / WR-02: one shared formatter for header + pill; discloses the from-side year
            // on cross-year ranges so the scope label is never ambiguous.
            // WR-04: same explicit IST calendar the header uses, so the pill label matches the
            // @Query day-edges regardless of device timezone.
            parts.append(OverviewFilterEngine.rangeLabel(
                from: range.lowerBound, to: range.upperBound,
                calendar: OverviewFilterEngine.financialCalendar))
        }
        return parts.isEmpty ? "Filtered" : parts.joined(separator: " · ")
    }
}
