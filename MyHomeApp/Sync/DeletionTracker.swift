import Foundation
import SwiftData

/// SYNC-01 — the single choke point for deleting a syncable record.
///
/// ALL deletes of syncable records MUST go through `deleteSynced` — a bare `context.delete()`
/// resurrects on the next merge, because a peer that still holds the record sees it as "missing"
/// (indistinguishable from never-synced) and re-imports it. `deleteSynced` writes a `DeletionLog`
/// tombstone in the SAME context (flushed by the caller's `save()`) so the record stays deleted
/// across devices via the Plan-03 merge engine.
///
/// The tombstone carries the deleted record's `syncID` + `SyncEntityKind` rawValue + `deletedAt`,
/// exactly the shape `SnapshotExporter` serializes and `SnapshotImporter` applies.
extension ModelContext {

    /// Tombstone-then-delete a syncable record in one call.
    ///
    /// Writes a `DeletionLog(entitySyncID: model.syncID, entityKindRaw: kind.rawValue)` BEFORE the
    /// delete so the tombstone captures the record's identity while it is still live, then deletes
    /// the row. The caller is responsible for `save()` (matching the pre-existing bare-delete call
    /// sites, which all persist explicitly per CR-01).
    ///
    /// Special case — Note: a Note's `blocks` are cascade-deleted by the store, but the OTHER phone
    /// still holds those blocks and would re-import them as orphans (their owning Note gone). So we
    /// tombstone every block with kind `.noteBlock` first, guaranteeing the cascade-deleted children
    /// are propagated as deletions too.
    func deleteSynced<T: PersistentModel & SyncStamped>(_ model: T, kind: SyncEntityKind) {
        // Cascade-aware: tombstone a Note's blocks before the store cascade-deletes them.
        if let note = model as? Note {
            for block in note.blocks ?? [] {
                insert(DeletionLog(entitySyncID: block.syncID, entityKindRaw: SyncEntityKind.noteBlock.rawValue))
            }
        }
        insert(DeletionLog(entitySyncID: model.syncID, entityKindRaw: kind.rawValue))
        delete(model)
    }

    /// Engine-only raw delete used by `SnapshotImporter` when APPLYING an already-recorded remote
    /// tombstone. Deliberately does NOT write a new `DeletionLog`: the tombstone that authorized this
    /// delete is already unioned into the local log, so re-tombstoning here would forge a fresher
    /// `deletedAt` and churn the LWW clock on every merge. User-initiated deletes MUST use
    /// `deleteSynced` instead — this method exists solely so the importer's tombstone-application
    /// step is not a bare `delete` masquerading as a user action.
    func deleteAppliedTombstone<T: PersistentModel>(_ model: T) {
        delete(model)
    }
}
