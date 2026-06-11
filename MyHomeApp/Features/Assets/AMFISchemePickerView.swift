import SwiftUI

/// Searchable AMFI scheme picker — 4 states: loaded, empty (pre-fetch), fetching, failed.
///
/// Presented as a navigation destination within EditAssetView's NavigationStack.
/// Writes amfiSchemeCode to the parent binding when user taps a row.
///
/// States (Surface 4, D-01/D-02):
///   A — loaded: filterable List with checkmark on selected row
///   B — pre-fetch: ContentUnavailableView + "Fetch Now" button
///   C — fetching: ProgressView("Loading schemes…")
///   D — failed: ContentUnavailableView with retry copy + "Try Again" button
///
/// Threat mitigations:
/// - T-11-10: Scheme names rendered via plain Text() — never AttributedString(markdown:).
struct AMFISchemePickerView: View {

    @Binding var selectedSchemeCode: String?
    var amfiNavService: AMFINavService

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    // MARK: - Filtered schemes

    private var filteredSchemes: [AMFIScheme] {
        if query.isEmpty {
            return amfiNavService.schemeList
        }
        return amfiNavService.schemeList.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle("Choose Scheme")
            .navigationBarTitleDisplayMode(.inline)
    }

    // State branches are split into separate @ViewBuilder properties so each
    // type-checks in its own context — a single Group with all three inline
    // collapses SwiftUI's ViewBuilder inference (surfaces a bogus TableColumn
    // candidate / "generic parameter could not be inferred").
    @ViewBuilder
    private var content: some View {
        if amfiNavService.isFetching {
            fetchingState        // State C — Fetching
        } else if amfiNavService.schemeList.isEmpty {
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
                amfiNavService.forceRefresh()
            }
            .tint(.accentColor)
            Spacer()
        }
    }

    @ViewBuilder
    private var loadedState: some View {
        // ForEach (not List(data:rowContent:)) so the element is a plain AMFIScheme,
        // not Binding<AMFIScheme> — the data:rowContent overload resolves to the
        // Binding form here and makes scheme.code a Binding<String>.
        List {
            ForEach(filteredSchemes, id: \.code) { scheme in
                Button {
                    selectedSchemeCode = scheme.code
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scheme.name)  // T-11-10: plain Text — no AttributedString
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(scheme.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedSchemeCode == scheme.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 44)
                    .background(
                        selectedSchemeCode == scheme.code
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always)
        )
    }
}
