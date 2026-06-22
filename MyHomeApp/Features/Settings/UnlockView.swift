import SwiftUI

/// Full-screen unlock overlay shown when lockController.isLocked && lockController.lockEnabled (D5-02).
///
/// Always shows a tappable Unlock button as the manual retry path — never a blank/auto-only gate (T-05-01).
/// Maps every LockAuthError case to recoverable guidance text (T-05-02, SEC-02, D5-06).
/// No-passcode state shows escape guidance to set a device passcode (D5-05, T-05-02).
struct UnlockView: View {

    let lockController: LockController

    var body: some View {
        ZStack {
            DesignTokens.bgCanvas
                .ignoresSafeArea()

            VStack(spacing: 32) {

                // App icon — decorative, hidden from accessibility
                appIconView
                    .accessibilityHidden(true)

                // App name
                Text("MyHome")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.label2)
                    .accessibilityAddTraits(.isHeader)

                // Error message — shown only when authError != nil
                if let error = lockController.authError {
                    Text(errorMessage(for: error))
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Unlock button — always visible as manual retry path (D5-02)
                Button("Unlock") {
                    Task { await lockController.authenticate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignTokens.accent)

                // No-passcode guidance — shown only when authError == .noPasscode (D5-05)
                if lockController.authError == .noPasscode {
                    Text("Open the Settings app, then Face ID & Passcode, to set a device passcode. Then return here.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.label2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding()
        }
    }

    // MARK: - App Icon

    @ViewBuilder
    private var appIconView: some View {
        if let uiImage = UIImage(named: "AppIcon") {
            Image(uiImage: uiImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            Image(systemName: "house.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(DesignTokens.accent)
        }
    }

    // MARK: - Error Message Mapping (SEC-02, D5-06)

    /// Maps a LockAuthError to exact UI-SPEC Copywriting Contract strings.
    /// Every case maps to a recoverable action — never a dead end (D5-06).
    private func errorMessage(for error: LockAuthError) -> String {
        switch error {
        case .failed:
            return "Authentication failed. Try again."
        case .biometryLocked:
            return "Too many failed attempts. Use your device passcode."
        case .noPasscode:
            return "No device passcode is set."
        case .unknown:
            return "Authentication unavailable. Try again."
        }
    }
}
