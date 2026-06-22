import SwiftUI

/// Searchable NPS scheme picker — 4 states: loaded, empty (pre-fetch), fetching, failed.
///
/// Mirrors AMFISchemePickerView verbatim; swaps:
///   - `amfiNavService: AMFINavService` → `npsNavService: NPSNavService`
///   - `[AMFIScheme]` → `[NPSScheme]`
///   - filteredSchemes searches both `name` AND `code` (NPS users search by PFM/asset-class
///     and by scheme code — PATTERNS.md NPSSchemePickerView section)
///
/// Presented as a navigation destination within EditAssetView's NPS section (added in 11.1-04).
/// Writes npsSchemeCode to the parent binding when user taps a row.
///
/// States (Surface 4, D-01/D-08):
///   A — loaded: filterable List with checkmark on selected row
///   B — pre-fetch: ContentUnavailableView + "Fetch Now" button
///   C — fetching: ProgressView("Loading schemes…")
///
/// Threat mitigations:
/// - T-113-04: Scheme names rendered via plain Text() — never AttributedString(markdown:).
/// - T-113-03: npsNavService fetches only HTTPS (hard-coded URL in NPSNavService).
struct NPSSchemePickerView: View {

    @Binding var selectedSchemeCode: String?
    var npsNavService: NPSNavService

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    // MARK: - Filtered schemes

    private var filteredSchemes: [NPSScheme] {
        if query.isEmpty {
            return npsNavService.schemeList
        }
        // NPS-specific: filter on name OR code (PFM/asset-class search + code search)
        return npsNavService.schemeList.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle("Choose NPS Scheme")
            .navigationBarTitleDisplayMode(.inline)
    }

    // State branches are split into separate @ViewBuilder properties so each
    // type-checks in its own context (same pattern as AMFISchemePickerView).
    @ViewBuilder
    private var content: some View {
        if npsNavService.isFetching {
            fetchingState        // State C — Fetching
        } else if npsNavService.schemeList.isEmpty {
            emptyState           // State B — No schemes loaded (also State D on error)
        } else {
            loadedState          // State A — Schemes loaded
        }
    }

    @ViewBuilder
    private var fetchingState: some View {
        VStack {
            Spacer()
            ProgressView("Loading schemes…")
            Spacer()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ContentUnavailableView(
                "No Schemes Loaded",
                systemImage: "arrow.down.circle",
                description: Text("Scheme data hasn't been fetched yet.")
            )
            Button("Fetch Now") {
                npsNavService.forceRefresh()
            }
            .tint(DesignTokens.accent)
            Spacer()
        }
    }

    @ViewBuilder
    private var loadedState: some View {
        // ForEach (not List(data:rowContent:)) so the element is a plain NPSScheme,
        // not Binding<NPSScheme> — same as AMFISchemePickerView to avoid Binding overload.
        List {
            ForEach(filteredSchemes, id: \.code) { scheme in
                Button {
                    selectedSchemeCode = scheme.code
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // T-113-04: plain Text — never AttributedString(markdown:)
                            // name may be empty (bulk endpoint has no names);
                            // show code prominently so an empty name is still selectable (Open Question 2)
                            if scheme.name.isEmpty {
                                Text(scheme.code)
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label)
                                    .lineLimit(2)
                            } else {
                                Text(scheme.name)  // T-113-04: plain Text
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label)
                                    .lineLimit(2)
                                Text(scheme.code)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.label2)
                            }
                        }
                        Spacer()
                        if selectedSchemeCode == scheme.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DesignTokens.accent)
                        }
                    }
                    .frame(minHeight: 44)  // 44pt touch target
                    .background(
                        selectedSchemeCode == scheme.code
                            ? DesignTokens.accent.opacity(0.12)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always)
        )
    }
}
