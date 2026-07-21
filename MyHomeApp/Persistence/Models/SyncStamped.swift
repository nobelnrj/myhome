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

// MARK: - Conformances for all 13 SchemaV11 syncable models
//
// Empty conformance extensions — every model already declares matching stored `syncID`/`updatedAt`
// properties in SchemaV11.swift, so the protocol requirements are satisfied structurally.
// DeletionLog is intentionally NOT SyncStamped: it is itself the delete-propagation mechanism,
// not a merge-target (it keys on entitySyncID, not its own syncID).
//
// STAB-08: these are EXPLICIT schema-version references that the typealias flip does NOT catch.
// They must be re-pointed by hand in the SAME commit as the container flip — a conformance left
// on the previous version silently detaches from the typealiased types and breaks every
// `touch()` / `deleteSynced` call site.

extension SchemaV11.Expense: SyncStamped {}
extension SchemaV11.Category: SyncStamped {}
extension SchemaV11.Note: SyncStamped {}
extension SchemaV11.NoteBlock: SyncStamped {}
extension SchemaV11.Account: SyncStamped {}
extension SchemaV11.Asset: SyncStamped {}
extension SchemaV11.NetWorthSnapshot: SyncStamped {}
extension SchemaV11.SIP: SyncStamped {}
extension SchemaV11.SIPAmountChange: SyncStamped {}
extension SchemaV11.Contribution: SyncStamped {}
extension SchemaV11.RoutineCompletion: SyncStamped {}

// NEW in SchemaV11 (Phase 20, plan 20-01) — the kitchen models are SyncStamped from birth
// (KTCH-04), so they flow through the Phase 18 merge engine exactly like every other record.
extension SchemaV11.PantryItem: SyncStamped {}
extension SchemaV11.ShoppingListItem: SyncStamped {}
