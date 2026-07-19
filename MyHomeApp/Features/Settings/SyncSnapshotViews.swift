import SwiftUI
import SwiftData
import UIKit

/// SYNC-03 — the device-to-device transport UI: a share-sheet wrapper for exporting a
/// `.myhomesnap` (AirDrop is just a share-sheet target — no entitlement) and a decode-then-confirm
/// import sheet that merges through the Phase-18 engine only on an explicit user tap.
///
/// Design: styled with existing `DesignTokens` only — NO token is defined or mutated here, and no
/// dark-branch is touched, so `DarkBitIdentityTests` stays byte-identical.

// MARK: - Share sheet (AirDrop / Save to Files)

/// Wraps `UIActivityViewController` so a snapshot *file URL* can be shared. AirDrop, "Save to
/// Files", Messages, etc. all appear as standard targets — AirDrop IS the SYNC-03 transport.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Import confirm-merge sheet

/// Decode-then-confirm import. On appear it reads the (untrusted) file, decodes WITHOUT merging,
/// and shows the source device, export time, and per-entity counts so the user sees exactly what
/// would arrive. The store is untouched until "Merge into this phone" is tapped (T-18-11). A
/// version-mismatched or malformed file never reaches the importer and surfaces a distinct,
/// user-readable message (T-18-13).
struct SnapshotImportSheet: View {
    let fileURL: URL

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Sheet phases: previewing the decoded snapshot, or showing merge results.
    private enum Phase: Equatable {
        case loading
        case preview(SnapshotPreview)
        case failed(String)
        case merged(MergeStats)
    }

    @State private var phase: Phase = .loading
    @State private var isMerging = false
    /// The bytes read on appear, retained so Merge doesn't re-read the security-scoped URL.
    @State private var loadedData: Data?

    var body: some View {
        NavigationStack {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(DesignTokens.bgCanvas.ignoresSafeArea())
                .navigationTitle("Import Snapshot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(DesignTokens.label2)
                    }
                }
        }
        .task { load() }
    }

    // MARK: Phase content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Reading snapshot…")
                .tint(DesignTokens.accent)
                .foregroundStyle(DesignTokens.label2)

        case let .preview(preview):
            previewView(preview)

        case let .failed(message):
            failureView(message)

        case let .merged(stats):
            mergedView(stats)
        }
    }

    // MARK: Preview (before merge)

    private func previewView(_ preview: SnapshotPreview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(preview.deviceName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.label)
                Text("Exported \(preview.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("This snapshot contains")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.label3)
                ForEach(preview.rows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                            .foregroundStyle(DesignTokens.label2)
                        Spacer()
                        Text("\(row.count)")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DesignTokens.label)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(DesignTokens.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Nothing changes on this phone until you tap Merge. Records are combined by the "
                 + "sync engine — newer edits win and deletions are honored.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.label3)

            Button {
                merge()
            } label: {
                HStack {
                    if isMerging { ProgressView().tint(DesignTokens.accentOnYellow) }
                    Text(isMerging ? "Merging…" : "Merge into this phone")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 14)
                .background(DesignTokens.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(DesignTokens.accentOnYellow)
            }
            .disabled(isMerging)

            Spacer(minLength: 0)
        }
    }

    // MARK: Failure

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(DesignTokens.negative)
            Text("Can't import this file")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.label)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignTokens.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(DesignTokens.label)
            Spacer(minLength: 0)
        }
    }

    // MARK: Merged result

    private func mergedView(_ stats: MergeStats) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(DesignTokens.positive)
            Text("Merge complete")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.label)

            VStack(alignment: .leading, spacing: 8) {
                statRow("Added", stats.inserted)
                statRow("Updated", stats.updated)
                statRow("Deleted", stats.deleted)
                statRow("Skipped", stats.skipped)
                statRow("Matched", stats.adopted)
            }
            .padding(16)
            .background(DesignTokens.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignTokens.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(DesignTokens.accentOnYellow)

            Spacer(minLength: 0)
        }
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(DesignTokens.label2)
            Spacer()
            Text("\(value)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignTokens.label)
        }
        .font(.subheadline)
    }

    // MARK: Load + merge

    /// Read the file (security-scoped for Files-app documents; harmless for Inbox copies) and
    /// decode WITHOUT merging so the confirm view can preview counts.
    private func load() {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try SnapshotCodec.decode(data)
            loadedData = data
            phase = .preview(SnapshotPreview(snapshot: snapshot))
        } catch let error as SyncError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed("This file couldn't be read.")
        }
    }

    /// Merge the already-decoded bytes through the Phase-18 engine and show the returned stats.
    private func merge() {
        guard let data = loadedData, !isMerging else { return }
        isMerging = true
        do {
            let stats = try SnapshotImporter.mergeData(data, into: modelContext)
            phase = .merged(stats)
        } catch let error as SyncError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed("The merge couldn't be completed.")
        }
        isMerging = false
    }

    /// Distinct, user-readable copy per decode failure (T-18-13).
    private static func message(for error: SyncError) -> String {
        switch error {
        case let .schemaVersionMismatch(found, expected):
            return "This snapshot was made by an incompatible app version "
                + "(v\(found) vs v\(expected)) — update both phones and re-export."
        case .malformedSnapshot:
            return "This file isn't a valid MyHome snapshot."
        }
    }
}

// MARK: - Snapshot preview model

/// Non-mutating view model built from a decoded `SyncSnapshot` — pure counts for the confirm sheet.
struct SnapshotPreview: Equatable {
    struct Row: Equatable { let label: String; let count: Int }

    let deviceName: String
    let exportedAt: Date
    let rows: [Row]

    init(snapshot: SyncSnapshot) {
        deviceName = snapshot.deviceName.isEmpty ? "another phone" : snapshot.deviceName
        exportedAt = snapshot.exportedAt
        rows = [
            Row(label: "Expenses", count: snapshot.expenses.count),
            Row(label: "Categories", count: snapshot.categories.count),
            Row(label: "Notes", count: snapshot.notes.count),
            Row(label: "Note blocks", count: snapshot.noteBlocks.count),
            Row(label: "Accounts", count: snapshot.accounts.count),
            Row(label: "Assets", count: snapshot.assets.count),
            Row(label: "SIPs", count: snapshot.sips.count),
            Row(label: "Contributions", count: snapshot.contributions.count),
            Row(label: "Net-worth snapshots", count: snapshot.netWorthSnapshots.count),
            Row(label: "Routine completions", count: snapshot.routineCompletions.count),
            Row(label: "Deletions", count: snapshot.deletions.count),
        ].filter { $0.count > 0 }
    }
}
