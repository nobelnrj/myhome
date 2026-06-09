import Foundation

// MARK: - RoutineResetService

/// Routine-reset coordinator: resets routine NoteBlock completion state on each new IST day.
///
/// Phase 8 scaffold: no model writes this phase (NoteBlock.lastCheckedDate does not exist
/// until SchemaV6 / Phase 9). The call path is fully wired; Phase 9 fills the body.
///
/// Owned by RootView via `@State private var routineResetService = RoutineResetService()`
/// and called synchronously from `.onChange(of: scenePhase)` on `.active`.
@MainActor
@Observable
final class RoutineResetService {

    func resetIfNeeded() {
        // STAB-04: logged scaffold only. Phase 9 adds NoteBlock.lastCheckedDate comparison
        // once SchemaV6 lands.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // IST — household timezone
        let todayIST = cal.startOfDay(for: Date())
        // Phase 9 implementation:
        //   fetch all NoteBlocks where note.isRoutine == true
        //   for each block where lastCheckedDate < todayIST: reset isChecked = false, update lastCheckedDate
        print("[RoutineResetService] resetIfNeeded: startOfToday IST = \(todayIST). No-op (Phase 8 scaffold).")
    }
}
