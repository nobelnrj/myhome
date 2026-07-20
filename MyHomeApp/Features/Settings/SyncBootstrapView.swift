import SwiftUI

/// SYNC-05 — the first-run "Set up from your other phone" bootstrap sheet.
///
/// A guided window onto the EXISTING snapshot exchange: on appear it starts discovery and issues
/// a `syncNow()` so the other phone pushes its full snapshot; the Phase-18 merge engine seeds this
/// (fresh) store. Because it is the same merge exchange, a NON-empty store is never wiped — local
/// rows are kept and merged (LWW), which is exactly what the user-facing copy promises.
///
/// Drives ONLY `coordinator.start()` / `coordinator.syncNow()` and reads `statusStore` — zero
/// direct transport/engine calls. Neumorphic, existing `DesignTokens` only (no token/dark edits —
/// DarkBitIdentityTests is the tripwire).
struct SyncBootstrapView: View {

    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    /// Called when the prompt is resolved (completed, "Set up later", or swipe-dismissed) so a
    /// first-run presenter can drop its `isPresented` binding.
    var onResolved: () -> Void = {}

    /// `lastMergeStats` at sheet-appear — completion is detected as a transition AWAY from this.
    @State private var baselineStats: MergeStats?
    @State private var completed = false
    @State private var completionSummary: String?
    @State private var completionPeer: String?
    /// Ensures the one-shot resolved flag is written exactly once across button + swipe paths.
    @State private var didResolve = false

    private var store: SyncStatusStore { coordinator.statusStore }

    /// Live status line — never a dead spinner: every state maps to explicit copy.
    private var progressLabel: String {
        if case .error(let message) = store.status { return message }
        if store.status == .syncing { return "Copying data…" }
        if let peer = store.connectedPeerName { return "Connected to \(peer)" }
        return "Looking for your other phone…"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.spacing22) {
                    header
                    if completed {
                        completionCard
                    } else {
                        progressCard
                        if case .error = store.status {
                            tryAgainButton
                        }
                    }
                }
                .padding(DesignTokens.spacing16)
            }
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Set Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !completed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Set up later") { resolve() }
                            .foregroundStyle(DesignTokens.label2)
                    }
                }
            }
        }
        .onAppear {
            baselineStats = store.lastMergeStats
            coordinator.start()      // idempotent
            coordinator.syncNow()    // force fresh discovery + snapshotRequest
        }
        // Completion: a NEW merge stats value (vs the appear-time baseline) means the other phone's
        // snapshot has landed and merged into this store.
        .onChange(of: store.lastMergeStats) { _, newValue in
            guard !completed, let newValue, newValue != baselineStats else { return }
            completionSummary = SyncStatusPresentation.mergeSummary(newValue)
            completionPeer = store.connectedPeerName
            completed = true
            Haptics.success()
        }
        // Swipe-dismiss counts as "Set up later": persist the one-shot flag so we never nag again.
        .onDisappear {
            if !didResolve {
                BootstrapAdvisor.markResolved()
                onResolved()
                didResolve = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: DesignTokens.spacing12) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(DesignTokens.accentText)
            Text("Set up from your other phone")
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.label)
            Text("Open MyHome on your other phone and keep both on the same Wi-Fi. Everything — expenses, notes, accounts, assets — will be copied over. Anything already on this phone is kept and merged, never deleted.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.label2)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.spacing22)
        .neuSurface(.raised)
    }

    private var progressCard: some View {
        VStack(spacing: DesignTokens.spacing12) {
            if case .error = store.status {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.negative)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(progressLabel)
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.label)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.spacing22)
        .neuSurface(.raised)
    }

    private var completionCard: some View {
        VStack(spacing: DesignTokens.spacing12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DesignTokens.positive)
            Text("Done" + (completionSummary.map { " — \($0)" } ?? ""))
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.label)
            if let peer = completionPeer {
                Text("Imported from \(peer)")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.label2)
            }
            Button {
                resolve()
            } label: {
                Label("Start using MyHome", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(NeuPrimaryButtonStyle())
            .padding(.top, DesignTokens.spacing12)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.spacing22)
        .neuSurface(.raised)
    }

    private var tryAgainButton: some View {
        Button {
            Haptics.tap()
            coordinator.syncNow()
        } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(NeuPrimaryButtonStyle())
    }

    // MARK: - Resolution

    /// Persist the one-shot flag, notify the presenter, and dismiss — used by both "Set up later"
    /// and "Start using MyHome". Idempotent with the swipe-dismiss `.onDisappear` path.
    private func resolve() {
        Haptics.tap()
        if !didResolve {
            BootstrapAdvisor.markResolved()
            onResolved()
            didResolve = true
        }
        dismiss()
    }
}
