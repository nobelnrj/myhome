import SwiftUI

// MARK: - SyncStatusPresentation (pure)

/// SYNC-05 — the pure, deterministic mapping from `SyncStatusStore` state to the strings,
/// SF Symbols, and DesignTokens the sync surface renders. No SwiftUI state, no rendering,
/// every input passed in — so the whole presentation layer is unit-tested without a view.
///
/// This type defines ZERO colors: every `tint` returns an EXISTING `DesignTokens` member
/// (the dark-branch byte-identity guard, DarkBitIdentityTests, must stay green).
enum SyncStatusPresentation {

    /// Human-readable status line. `.idle` reads differently before vs. after a first sync so
    /// a never-synced phone doesn't claim to be "Up to date". `.error` is already a
    /// human-readable message from Plan 02, so it passes through verbatim.
    static func label(for status: PeerSyncStatus, lastSyncedAt: Date?) -> String {
        switch status {
        case .idle:
            return lastSyncedAt != nil ? "Up to date" : "Not synced yet"
        case .connecting:
            return "Looking for your other phone…"
        case .syncing:
            return "Syncing…"
        case .error(let message):
            return message
        }
    }

    /// SF Symbol name for the status glyph.
    static func systemImage(for status: PeerSyncStatus) -> String {
        switch status {
        case .idle:       return "checkmark.circle"
        case .connecting: return "dot.radiowaves.left.and.right"
        case .syncing:    return "arrow.triangle.2.circlepath"
        case .error:      return "exclamationmark.triangle"
        }
    }

    /// Status tint — always an EXISTING `DesignTokens` member (this file defines no colors).
    static func tint(for status: PeerSyncStatus) -> Color {
        switch status {
        case .idle:       return DesignTokens.positive
        case .connecting: return DesignTokens.label2
        case .syncing:    return DesignTokens.accentText
        case .error:      return DesignTokens.negative
        }
    }

    /// Relative "last synced" text. `nil` → "Never synced"; under a minute → "Just now"
    /// (an explicit branch that side-steps `RelativeDateTimeFormatter`'s "in 0 seconds"
    /// weirdness for sub-minute intervals); otherwise a named relative string ("2 minutes ago").
    static func relativeLastSynced(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never synced" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// One-line summary of the most recent merge. `nil` stats → `nil` (no row shown); a merge
    /// that changed nothing → "Nothing new — already in sync"; otherwise the non-zero
    /// components joined ("3 added · 2 updated · 1 removed"), always ≥1 component.
    static func mergeSummary(_ stats: MergeStats?) -> String? {
        guard let stats else { return nil }
        var parts: [String] = []
        if stats.inserted > 0 { parts.append("\(stats.inserted) added") }
        if stats.updated  > 0 { parts.append("\(stats.updated) updated") }
        if stats.deleted  > 0 { parts.append("\(stats.deleted) removed") }
        if parts.isEmpty { return "Nothing new — already in sync" }
        return parts.joined(separator: " · ")
    }
}

// MARK: - SyncStatusView

/// SYNC-05 — the neumorphic sync surface, reachable from Settings → Sync. A thin view over the
/// Plan-02 `SyncStatusStore` (read through the coordinator): every string/symbol/tint comes from
/// the pure `SyncStatusPresentation` mapper above. Uses ONLY existing `DesignTokens` + `NeuSurface`
/// — zero token/dark-branch edits (DarkBitIdentityTests is the tripwire).
struct SyncStatusView: View {

    @Environment(SyncCoordinator.self) private var coordinator

    /// SYNC-05: manual entry to the bootstrap flow for users who skipped the first-run prompt.
    /// Works on non-empty stores too — the underlying exchange merges (never clobbers).
    @State private var showBootstrap = false

    private var store: SyncStatusStore { coordinator.statusStore }

    private var isSyncing: Bool { store.status == .syncing }

    /// The connected peer's display name is the T-19-02 visibility mitigation — an unexpected
    /// household peer is user-visible. When not connected, say so plainly.
    private var peerLine: String {
        if let name = store.connectedPeerName { return "Connected to \(name)" }
        return "No phone nearby"
    }

    /// Foreground-only expectation + the Local-Network privacy hint when the error implicates it.
    private var footerText: String {
        let base = "Syncing works when both phones have MyHome open on the same Wi-Fi."
        if case .error(let message) = store.status,
           message.localizedCaseInsensitiveContains("Local Network") {
            return base + " Enable it in Settings → Privacy → Local Network."
        }
        return base
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spacing22) {
                statusCard
                if let summary = SyncStatusPresentation.mergeSummary(store.lastMergeStats) {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                syncNowButton
                setUpFromOtherPhoneButton
                Text(footerText)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.label3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesignTokens.spacing16)
        }
        .background(DesignTokens.bgCanvas)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBootstrap) {
            SyncBootstrapView()
        }
    }

    // MARK: - Manual bootstrap entry (SYNC-05)

    /// Quiet secondary affordance — the manual path into the bootstrap flow for users who tapped
    /// "Set up later" on first run. Merges on non-empty stores; never clobbers.
    private var setUpFromOtherPhoneButton: some View {
        Button {
            Haptics.tap()
            showBootstrap = true
        } label: {
            Label("Set up from your other phone…", systemImage: "iphone.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing12) {
            HStack(spacing: DesignTokens.spacing12) {
                Image(systemName: SyncStatusPresentation.systemImage(for: store.status))
                    .font(.title2)
                    .foregroundStyle(SyncStatusPresentation.tint(for: store.status))
                    .symbolEffect(.pulse, isActive: isSyncing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SyncStatusPresentation.label(for: store.status, lastSyncedAt: store.lastSyncedAt))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                    Text(peerLine)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.label2)
                }
                Spacer(minLength: 0)
            }
            // Re-render the relative time every 30s so "Just now" ages without interaction.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(SyncStatusPresentation.relativeLastSynced(store.lastSyncedAt, now: context.date))
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.label2)
            }
        }
        .neuSurface(.raised)
    }

    // MARK: - Sync Now

    private var syncNowButton: some View {
        Button {
            Haptics.tap()
            coordinator.syncNow()
        } label: {
            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(NeuPrimaryButtonStyle())
        .disabled(isSyncing)
        .opacity(isSyncing ? 0.6 : 1)
    }
}
