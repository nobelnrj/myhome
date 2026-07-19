import Foundation

/// SYNC-02 — the pure conflict-resolution policy for the merge engine (Plan 03) and the
/// Phase 19 transport. Foundation only: no SwiftData, no persistence context. Every input is
/// a value type, so the whole policy is unit-testable with zero container or device.
///
/// The policy is deliberately tiny — two total functions — because a merge policy is exactly
/// where a subtle asymmetry causes two phones to disagree and never converge. Keeping it pure
/// and byte-deterministic lets us prove convergence with plain value tests.
public enum SyncMergePolicy {

    /// Last-writer-wins with a deterministic, convergent tiebreak.
    ///
    /// Returns `true` when the REMOTE record should overwrite the local one:
    ///   - `remoteUpdatedAt > localUpdatedAt`  → remote is newer → true
    ///   - `remoteUpdatedAt < localUpdatedAt`  → local is newer  → false
    ///   - EXACT tie on `updatedAt` → compare canonical bytes: the lexicographically GREATER
    ///     canonical encoding wins (remote wins iff `localCanonical < remoteCanonical`)
    ///   - identical canonical bytes → false (no-op: re-importing your own snapshot is idempotent)
    ///
    /// WHY the tiebreak must be a byte comparison and NOT "local always wins" / "remote always
    /// wins": both phones evaluate this from OPPOSITE vantage points. Phone A sees (localA,
    /// remoteB); phone B sees (localB, remoteA). A "remote wins" rule would make A pick B and B
    /// pick A — they diverge forever. Ranking by the record's own canonical bytes is a total
    /// order independent of vantage point, so both phones deterministically pick the SAME
    /// winner and converge.
    public static func remoteWins(
        localUpdatedAt: Date,
        localCanonical: Data,
        remoteUpdatedAt: Date,
        remoteCanonical: Data
    ) -> Bool {
        if remoteUpdatedAt > localUpdatedAt { return true }
        if remoteUpdatedAt < localUpdatedAt { return false }
        // Exact timestamp tie — break by total order on canonical bytes.
        // Identical bytes → not greater → false (idempotent no-op).
        return localCanonical.lexicographicallyPrecedes(remoteCanonical)
    }

    /// Whether a deletion tombstone should win over a record's current state.
    ///
    /// Returns `true` when the delete beats the record:
    ///   - `deletedAt >= recordUpdatedAt` → the tombstone wins (SYNC success criterion 2:
    ///     no resurrection). An EXACT tie resolves in favor of the deletion — a delete that
    ///     lands at the same instant as the record's last edit still removes it.
    ///   - `deletedAt < recordUpdatedAt` → the record was EDITED strictly after the deletion,
    ///     so the edit resurrects it. This edit-after-delete resurrection is intentional LWW
    ///     behavior: the newer user action (the edit) is honored.
    public static func tombstoneWins(deletedAt: Date, recordUpdatedAt: Date) -> Bool {
        deletedAt >= recordUpdatedAt
    }
}
