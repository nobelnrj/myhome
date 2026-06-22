import SwiftUI
import SwiftData

/// Per-routine detail view — current streak as a hero card, 30-day completion history.
///
/// Mirrors AssetDetailView: header card (cardStyle()) + detail List (.insetGrouped).
/// Accessed via NavigationLink("Routine History") from EditNoteView's Routine section (D-09).
///
/// Security:
/// - T-12-10: all strings rendered via plain Text() — never AttributedString(markdown:).
/// - navigationTitle uses plain string access (mirrors AssetDetailView T-11-10 pattern).
struct RoutineDetailView: View {

    var note: Note

    // @Query predicate captured via init (Pitfall 4 in RESEARCH.md — no dynamic predicate in body)
    @Query private var completions: [RoutineCompletion]

    // MARK: - Init

    init(note: Note) {
        self.note = note
        // Pitfall 4: capture note.id into a local before the predicate
        let noteID = note.id
        self._completions = Query(
            filter: #Predicate<RoutineCompletion> { $0.noteID == noteID },
            sort: [SortDescriptor(\.dayKey, order: .reverse)]
        )
    }

    // MARK: - Computed

    private var streakResult: StreakResult {
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return StreakCalculator.compute(
            for: note.id,
            completions: completions,
            today: Date(),
            calendar: istCal
        )
    }

    private var currentStreak: Int {
        streakResult.currentStreak
    }

    /// UI-SPEC Surface 4 streak status line copy.
    private var streakStatusLine: String {
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayKey = istCal.startOfDay(for: Date())
        let todayCompleted = completions.contains { istCal.startOfDay(for: $0.dayKey) == todayKey }
        if todayCompleted {
            return "Today's streak is active"
        } else if currentStreak > 0 {
            return "Complete today to extend your streak"
        } else {
            return "Start your streak today"
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Header card — mirrors AssetDetailView.swift lines 67-74
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(DesignTokens.surfaceRaised)
                    .listRowSeparator(.hidden)
            }

            // Section 2: 30-day history
            Section("Last 30 Days") {
                if streakResult.history.isEmpty || completions.isEmpty {
                    // Empty state per UI-SPEC Surface 4
                    Text("No completions recorded yet. Complete this routine to start your streak.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.label2)
                        .padding(.vertical, 8)
                } else {
                    ForEach(streakResult.history, id: \.dayKey) { dayStatus in
                        historyRow(dayStatus)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .navigationTitle(note.title)   // T-12-10 / T-11-10: plain string — no AttributedString
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card

    /// Hero card showing current streak prominently — mirrors AssetDetailView.headerCard.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Category label (mirrors assetClassLabel in AssetDetailView)
            // T-12-10: plain Text — no AttributedString
            Text("Daily Routine")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)

            // Streak hero number (mirrors currentValue largeTitle in AssetDetailView)
            // T-12-10: plain Text
            Text("🔥 \(currentStreak)")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(DesignTokens.label)

            // Unit label
            Text(currentStreak == 1 ? "day streak" : "days streak")
                .font(.body)
                .foregroundStyle(DesignTokens.label2)

            // Streak status line (UI-SPEC Surface 4 copy)
            Text(streakStatusLine)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
        }
        .padding(16)
        .neuSurface(.raised)
    }

    // MARK: - History Row

    /// One row in the "Last 30 Days" section — mirrors UI-SPEC Surface 4 history row.
    @ViewBuilder
    private func historyRow(_ dayStatus: DayStatus) -> some View {
        let isCompleted = dayStatus.isCompleted
        let isToday = isHistoryRowToday(dayStatus)

        HStack {
            // Left: completion indicator (non-interactive, consistent sizing)
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? DesignTokens.positive : DesignTokens.label3)
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)

            // Middle: formatted date — T-12-10: plain Text
            if isToday {
                Text("Today")
                    .font(.body)
                    .foregroundStyle(DesignTokens.label)
            } else {
                Text(dayStatus.dayKey.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.body)
                    .foregroundStyle(DesignTokens.label)
            }

            Spacer()

            // Right: "Done" or "—" label
            Text(isCompleted ? "Done" : "—")
                .font(.caption)
                .foregroundStyle(isCompleted ? DesignTokens.positive : DesignTokens.label3)
        }
        .frame(minHeight: 44)
    }

    /// Helper: whether a DayStatus row represents today (extracted to avoid @ViewBuilder var mutation).
    private func isHistoryRowToday(_ dayStatus: DayStatus) -> Bool {
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayKey = istCal.startOfDay(for: Date())
        return istCal.startOfDay(for: dayStatus.dayKey) == todayKey
    }
}
