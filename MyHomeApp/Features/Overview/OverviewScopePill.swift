import SwiftUI

/// The Overview header scope pill (OVF-03) — the always-present entry point AND active-state
/// display for the ACCOUNT dimension of the filter (UI-REFERENCE Decision 3).
///
/// The pill deliberately shows ONLY the account scope; the custom date range lives in the left
/// eyebrow (which recolours to the selected range and is tappable to reset it). Keeping the date
/// range OUT of the pill means the pill can never grow to a long "account · date" string and
/// reflow the header against the title — the layout stays stable when a range is applied.
///
/// - No account subset: a neutral dot + "All accounts" + a chevron; the capsule opens the sheet.
/// - Account subset active: an accent dot + the account name(s), so filtered figures can never
///   masquerade as all-account totals (threat T-21-05). A trailing `xmark.circle.fill` replaces
///   the chevron; ONE tap clears the ACCOUNT dimension only (`onClear`, keeping any date range),
///   while tapping the label still opens the sheet.
///
/// Pure presentation — no @Query, no fetching. The caller resolves `accountNames` and gates the
/// clear action. Styled with existing neumorphic tokens only (no DesignSystem edits).
struct OverviewScopePill: View {
    let filter: OverviewFilter
    /// Resolved names of the selected accounts (plus "Unassigned" when included).
    let accountNames: [String]
    /// Opens the filter sheet.
    let onTap: () -> Void
    /// Clears the ACCOUNT dimension only (`filter.clearingAccounts()`) — a single tap, no
    /// confirmation (OVF-03). A date range set from the eyebrow is preserved.
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
                        .fill(filter.accountFilterActive ? DesignTokens.accent : DesignTokens.label3)
                        .frame(width: 8, height: 8)
                    Text(summaryLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if !filter.accountFilterActive {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if filter.accountFilterActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignTokens.label3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear account filter")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, filter.accountFilterActive ? 6 : 14)
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
        guard filter.accountFilterActive else { return "All accounts" }
        guard let first = accountNames.first else { return "Filtered" }
        return accountNames.count > 1 ? "\(first) +\(accountNames.count - 1)" : first
    }
}
