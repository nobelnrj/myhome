import Foundation
import SwiftData

// MARK: - RoutineResetService

/// Routine-reset coordinator: resets routine NoteBlock completion state on each new IST day.
///
/// On `scenePhase .active`, fetches every Note flagged `isDailyRoutine == true` whose
/// `routineLastResetDate` is before IST start-of-today, unchecks all its checkbox blocks,
/// and stamps the new reset date (STAB-04, NOTE-02, D-11, D-12).
///
/// Non-routine notes are never touched (D-11).
/// Same-day reactivations are no-ops — idempotent by design (D-12).
///
/// Owned by RootView via `@State private var routineResetService = RoutineResetService()`
/// and called synchronously from `.onChange(of: scenePhase)` on `.active`.
/// `modelContext` is injected from RootView.onAppear (same pattern as gmailSyncController.setContext).
@MainActor
@Observable
final class RoutineResetService {

    // Injected by RootView.onAppear (same pattern as gmailSyncController.setContext — RootView line 86)
    var modelContext: ModelContext?

    func resetIfNeeded() {
        guard let context = modelContext else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // IST — household timezone
        let startOfTodayIST = cal.startOfDay(for: Date())

        do {
            // D-11: fetch only isDailyRoutine notes (non-routine notes never auto-reset)
            let notes = try context.fetch(
                FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })
            )
            var didChange = false
            for note in notes {
                // D-12: compare note-level routineLastResetDate (nil = distantPast = never reset)
                let lastReset = note.routineLastResetDate ?? .distantPast
                guard lastReset < startOfTodayIST else { continue }   // same-day no-op

                // Uncheck all checkbox blocks on this note
                for block in note.blocks ?? [] {
                    if block.kindRaw == "checkbox" && block.isChecked {
                        block.isChecked = false
                        block.touch()   // SYNC-02: daily reset is a real state change — must win LWW over a stale remote check
                        didChange = true
                    }
                }
                // Stamp the reset date even if no blocks were checked (note-level tracking)
                note.routineLastResetDate = startOfTodayIST
                note.touch()   // SYNC-02: routineLastResetDate advanced — stamp LWW clock
                didChange = true
            }
            if didChange { try context.save() }   // CR-01: explicit save
        } catch {
            // Non-fatal: log and return — never crash the app on scene activation (T-09-14)
            print("[RoutineResetService] reset failed: \(error)")
        }
    }
}
