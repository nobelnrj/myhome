import SwiftUI

/// Notes tab root view — List | Calendar segmented host (D3-17).
///
/// Owns its NavigationStack. The segmented control switches between:
///   - `NotesListView` (shipped in plan 03-05)
///   - A calendar placeholder `ContentUnavailableView` (03-06 hook — CalendarView lands there)
///
/// Satisfies: NOT-01..06 (note keeper), D3-17 (segmented tab root).
struct NotesHomeView: View {

    // MARK: - Segment state

    private enum NoteSegment: Int, CaseIterable {
        case list
        case calendar

        var label: String {
            switch self {
            case .list: return "List"
            case .calendar: return "Calendar"
            }
        }
    }

    @State private var selectedSegment: NoteSegment = .list

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control header
                segmentedHeader

                // Content area — switch on segment
                switch selectedSegment {
                case .list:
                    NotesListView()
                case .calendar:
                    // 03-06 HOOK: CalendarView goes here; stub until plan 03-06
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "calendar",
                        description: Text("Scheduled reminders will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Segmented Header

    private var segmentedHeader: some View {
        Picker("View", selection: $selectedSegment) {
            ForEach(NoteSegment.allCases, id: \.self) { segment in
                Text(segment.label).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
