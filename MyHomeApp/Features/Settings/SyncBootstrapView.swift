import SwiftUI

/// SYNC-05 — placeholder for the first-run bootstrap sheet. The full neumorphic implementation
/// lands in Task 2 of Plan 19-04; this compiling stub exists so the pbxproj registration is made
/// in the SAME task that authors `BootstrapAdvisor` (interruption-safety — register-with-create).
struct SyncBootstrapView: View {
    var onResolved: () -> Void = {}
    var body: some View { EmptyView() }
}
