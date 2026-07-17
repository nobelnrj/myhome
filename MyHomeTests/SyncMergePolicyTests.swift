import Testing
import Foundation
@testable import MyHome

// Requirements: SYNC-02 — deterministic, convergent LWW conflict policy.
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SyncMergePolicyTests

/// SyncMergePolicyTests — pure value tests for `SyncMergePolicy`.
///
/// Proves the two properties that make P2P merge safe:
///   - last-writer-wins on updatedAt
///   - the exact-tie tiebreak is vantage-independent (both phones pick the SAME winner) so
///     ties converge instead of ping-ponging forever
///   - tombstones win on ties (no resurrection); an edit strictly after a delete survives
struct SyncMergePolicyTests {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let later = Date(timeIntervalSince1970: 1_700_000_100)

    // MARK: - remoteWins LWW

    @Test("newer remote wins")
    func newerRemoteWins() {
        #expect(SyncMergePolicy.remoteWins(
            localUpdatedAt: Self.base, localCanonical: Data("x".utf8),
            remoteUpdatedAt: Self.later, remoteCanonical: Data("y".utf8)) == true)
    }

    @Test("older remote loses")
    func olderRemoteLoses() {
        #expect(SyncMergePolicy.remoteWins(
            localUpdatedAt: Self.later, localCanonical: Data("x".utf8),
            remoteUpdatedAt: Self.base, remoteCanonical: Data("y".utf8)) == false)
    }

    // MARK: - Tiebreak convergence (the crux)

    @Test("exact tie, different bytes: both vantage points agree on ONE winner")
    func tieConvergesToSingleWinner() {
        let a = Data("AAAA".utf8)
        let b = Data("BBBB".utf8)
        let t = Self.base

        // Phone 1's vantage: local = A, remote = B
        let fromOneSide = SyncMergePolicy.remoteWins(
            localUpdatedAt: t, localCanonical: a, remoteUpdatedAt: t, remoteCanonical: b)
        // Phone 2's vantage: local = B, remote = A
        let fromOtherSide = SyncMergePolicy.remoteWins(
            localUpdatedAt: t, localCanonical: b, remoteUpdatedAt: t, remoteCanonical: a)

        // Exactly one side keeps the remote — i.e. both phones converge on the SAME record.
        #expect(fromOneSide != fromOtherSide,
                "tiebreak must be vantage-independent so ties converge")
    }

    @Test("exact tie, identical bytes: no-op from both sides (idempotent)")
    func tieIdenticalBytesIsNoOp() {
        let x = Data("SAME".utf8)
        let t = Self.base
        #expect(SyncMergePolicy.remoteWins(
            localUpdatedAt: t, localCanonical: x, remoteUpdatedAt: t, remoteCanonical: x) == false)
        // symmetric — swapping the identical byte buffers changes nothing
        #expect(SyncMergePolicy.remoteWins(
            localUpdatedAt: t, localCanonical: x, remoteUpdatedAt: t, remoteCanonical: x) == false)
    }

    // MARK: - tombstoneWins

    @Test("deletion after the last edit wins")
    func deleteAfterEditWins() {
        #expect(SyncMergePolicy.tombstoneWins(deletedAt: Self.later, recordUpdatedAt: Self.base) == true)
    }

    @Test("deletion exactly at the last edit still wins (no resurrection)")
    func deleteAtEditWins() {
        #expect(SyncMergePolicy.tombstoneWins(deletedAt: Self.base, recordUpdatedAt: Self.base) == true)
    }

    @Test("edit strictly after the delete survives (intentional LWW resurrection)")
    func editAfterDeleteSurvives() {
        #expect(SyncMergePolicy.tombstoneWins(deletedAt: Self.base, recordUpdatedAt: Self.later) == false)
    }
}
