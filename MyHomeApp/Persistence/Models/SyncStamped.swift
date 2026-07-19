import SwiftData
import Foundation

/// The exported sync-identity contract for Phase 18 (SYNC-01).
///
/// Every syncable @Model in SchemaV10 carries `syncID` (stable cross-device identity) and
/// `updatedAt` (the last-writer-wins clock). `SyncStamped` names that convention so the merge
/// engine (Plan 03), the transport layer (Plan 04), and Phases 19/20 (CloudKit / multi-device)
/// can operate over any syncable model uniformly — `func merge(_ incoming: some SyncStamped)`
/// rather than one overload per concrete type.
///
/// `AnyObject`-constrained because every conformer is a SwiftData `@Model` reference type; the
/// `set` requirements let the merge engine stamp `updatedAt` on write.
protocol SyncStamped: AnyObject {
    var syncID: UUID { get set }
    var updatedAt: Date { get set }
}

extension SyncStamped {
    /// Stamps the last-writer-wins clock to now. Call on every local mutation so the merge
    /// engine can resolve concurrent edits by most-recent `updatedAt`.
    func touch() {
        updatedAt = Date()
    }
}

// MARK: - Conformances for all 11 SchemaV10 syncable models
//
// Empty conformance extensions — every model already declares matching stored `syncID`/`updatedAt`
// properties in SchemaV10.swift, so the protocol requirements are satisfied structurally.
// DeletionLog is intentionally NOT SyncStamped: it is itself the delete-propagation mechanism,
// not a merge-target (it keys on entitySyncID, not its own syncID).

extension SchemaV10.Expense: SyncStamped {}
extension SchemaV10.Category: SyncStamped {}
extension SchemaV10.Note: SyncStamped {}
extension SchemaV10.NoteBlock: SyncStamped {}
extension SchemaV10.Account: SyncStamped {}
extension SchemaV10.Asset: SyncStamped {}
extension SchemaV10.NetWorthSnapshot: SyncStamped {}
extension SchemaV10.SIP: SyncStamped {}
extension SchemaV10.SIPAmountChange: SyncStamped {}
extension SchemaV10.Contribution: SyncStamped {}
extension SchemaV10.RoutineCompletion: SyncStamped {}
