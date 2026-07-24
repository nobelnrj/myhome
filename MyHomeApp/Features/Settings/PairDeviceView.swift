import SwiftUI

// MARK: - PairDeviceView

/// SYNC-06 (SC-2 / SC-6, UI half) — the code-confirmed pairing ceremony and paired-devices
/// manager, presented as a sheet from Settings › Sync.
///
/// Trust flow (locked decision — code-confirmed, never trust-on-first-use):
///   1. "Pair New Device" enters the transport's time-boxed pairing window (`beginPairing`).
///   2. When an as-yet-untrusted peer forms a session it surfaces as a `.pairingCandidate`
///      (NOT a trusted `.connected`, so NO snapshot is ever pushed to it — Plan 02). We capture
///      it via `coordinator.onPairingCandidate`.
///   3. Both phones display the SAME deterministic 6-digit `PairingCode.sixDigit` of the two
///      installIDs. The user compares and taps "Codes match" — that tap is the trust decision.
///   4. Only THEN do we persist trust (`PairedDevicesStore.add`) and push the updated allowlist
///      to the transport (`applyAllowlist`) so auto-sync can resume with this peer.
///
/// A rogue peer computes a DIFFERENT code (and shows an unexpected name), so the user declines.
///
/// Styling is the existing neumorphic system ONLY — `NeuSurface`, `NeuPrimaryButtonStyle`,
/// `DesignTokens`, `Haptics`. No new tokens, no new colors (DarkBitIdentityTests tripwire).
struct PairDeviceView: View {

    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(PairedDevicesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// A captured pairing candidate awaiting the user's "Codes match" confirmation.
    private struct Candidate: Equatable {
        let peerName: String
        let peerIID: String
    }

    /// True while the transport pairing window is open (search in progress).
    @State private var isPairing = false

    /// The current un-trusted candidate (if any), whose code the user must confirm.
    @State private var candidate: Candidate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.spacing22) {
                    if let candidate {
                        codeConfirmCard(for: candidate)
                    } else {
                        pairEntryCard
                    }
                    pairedDevicesCard
                    Text("Open this screen on your other phone too, tap “Pair New Device” there, "
                        + "then confirm the codes match on both. Only paired phones can ever sync.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.label3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(DesignTokens.spacing16)
            }
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Pair Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Route the transport's pre-trust candidate event into this sheet.
            coordinator.onPairingCandidate = { peerName, peerIID in
                candidate = Candidate(peerName: peerName, peerIID: peerIID)
            }
        }
        .onDisappear {
            // Leave the pairing window and drop the hook so a background candidate can't be
            // captured once the sheet is gone (restores default-deny discovery).
            coordinator.endPairing()
            coordinator.onPairingCandidate = nil
            isPairing = false
        }
    }

    // MARK: - Pair entry

    private var pairEntryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing12) {
            HStack(spacing: DesignTokens.spacing12) {
                Image(systemName: isPairing
                      ? "dot.radiowaves.left.and.right"
                      : "iphone.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(isPairing ? DesignTokens.accentText : DesignTokens.label2)
                    .symbolEffect(.pulse, isActive: isPairing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPairing ? "Looking for your other phone…" : "Pair a new device")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                    Text(isPairing
                         ? "Keep both phones on this screen and on the same Wi-Fi."
                         : "Add your other phone so the two can sync securely.")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.label2)
                }
                Spacer(minLength: 0)
            }
            Button {
                Haptics.tap()
                isPairing = true
                coordinator.beginPairing()
            } label: {
                Label(isPairing ? "Searching…" : "Pair New Device",
                      systemImage: "plus.circle")
            }
            .buttonStyle(NeuPrimaryButtonStyle())
            .disabled(isPairing)
            .opacity(isPairing ? 0.6 : 1)
        }
        .neuSurface(.raised)
    }

    // MARK: - Code confirmation

    private func codeConfirmCard(for candidate: Candidate) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Confirm the code")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                Text("Make sure this same code shows on “\(candidate.peerName)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.label2)
            }
            Text(Self.groupedCode(for: candidate.peerIID))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .kerning(4)
                .foregroundStyle(DesignTokens.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.spacing12)

            Button {
                Haptics.tap(.medium)
                confirm(candidate)
            } label: {
                Label("Codes match", systemImage: "checkmark.circle")
            }
            .buttonStyle(NeuPrimaryButtonStyle())

            Button {
                Haptics.tap()
                // Decline: drop this candidate but stay in the pairing window so the REAL
                // device can still be found. NEVER persists trust.
                self.candidate = nil
            } label: {
                Label("Not my device", systemImage: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.negative)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
        }
        .neuSurface(.raised)
    }

    // MARK: - Paired devices list

    private var pairedDevicesCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing12) {
            Text("Paired Devices")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.label2)
            if store.devices.isEmpty {
                Text("No devices paired yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.label3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.devices, id: \.installID) { device in
                    HStack(spacing: DesignTokens.spacing12) {
                        Image(systemName: "iphone")
                            .font(.title3)
                            .foregroundStyle(DesignTokens.accentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.friendlyName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DesignTokens.label)
                            Text("Paired \(SyncStatusPresentation.relativeLastSynced(device.pairedAt))")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.label3)
                        }
                        Spacer(minLength: 0)
                        Button {
                            Haptics.tap()
                            unpair(device.installID)
                        } label: {
                            Text("Unpair")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DesignTokens.negative)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .neuSurface(.raised)
    }

    // MARK: - Trust mutations (UI → transport allowlist)

    /// Record trust after the user confirmed a matching code, then push the updated allowlist to
    /// the transport so auto-sync can resume with this now-trusted peer, and leave pairing mode.
    private func confirm(_ candidate: Candidate) {
        store.add(PairedDevice(
            installID: candidate.peerIID,
            friendlyName: candidate.peerName,
            pairedAt: Date()
        ))
        coordinator.applyAllowlist(store.allowlist)
        coordinator.endPairing()
        // Once paired, the launch-time migration banner no longer applies.
        coordinator.statusStore.needsPairing = false
        self.candidate = nil
        isPairing = false
    }

    /// Remove trust for a device and re-push the allowlist so the transport stops connecting to it.
    private func unpair(_ installID: String) {
        store.remove(installID: installID)
        coordinator.applyAllowlist(store.allowlist)
    }

    // MARK: - Code formatting

    /// The deterministic 6-digit confirmation code for `peerIID` vs. this install, grouped
    /// "042 178" for legibility. Both phones compute the identical value with no exchange.
    static func groupedCode(for peerIID: String) -> String {
        let code = PairingCode.sixDigit(InstallIdentity.current(), peerIID)
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }
}
