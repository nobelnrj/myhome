import Testing
import SwiftUI
import Foundation
@testable import MyHome

/// SYNC-05 — proves every string / symbol / tint the sync surface shows is a pure, deterministic
/// function of `SyncStatusStore` state. The view is thin; this is where the display logic is tested.
@MainActor
struct SyncStatusPresentationTests {

    // MARK: - label(for:lastSyncedAt:)

    @Test("idle label depends on whether a sync ever happened")
    func idleLabel() {
        #expect(SyncStatusPresentation.label(for: .idle, lastSyncedAt: Date()) == "Up to date")
        #expect(SyncStatusPresentation.label(for: .idle, lastSyncedAt: nil) == "Not synced yet")
    }

    @Test("connecting / syncing labels")
    func transientLabels() {
        #expect(SyncStatusPresentation.label(for: .connecting, lastSyncedAt: nil)
                == "Looking for your other phone…")
        #expect(SyncStatusPresentation.label(for: .syncing, lastSyncedAt: Date()) == "Syncing…")
    }

    @Test("error label passes the message through verbatim")
    func errorLabel() {
        let msg = "Local Network permission is off"
        #expect(SyncStatusPresentation.label(for: .error(message: msg), lastSyncedAt: nil) == msg)
    }

    // MARK: - systemImage(for:)

    @Test("status symbols")
    func symbols() {
        #expect(SyncStatusPresentation.systemImage(for: .idle) == "checkmark.circle")
        #expect(SyncStatusPresentation.systemImage(for: .connecting) == "dot.radiowaves.left.and.right")
        #expect(SyncStatusPresentation.systemImage(for: .syncing) == "arrow.triangle.2.circlepath")
        #expect(SyncStatusPresentation.systemImage(for: .error(message: "x")) == "exclamationmark.triangle")
    }

    // MARK: - tint(for:) — token identity, not raw colors

    @Test("status tints resolve to existing DesignTokens members")
    func tints() {
        #expect(SyncStatusPresentation.tint(for: .idle) == DesignTokens.positive)
        #expect(SyncStatusPresentation.tint(for: .connecting) == DesignTokens.label2)
        #expect(SyncStatusPresentation.tint(for: .syncing) == DesignTokens.accentText)
        #expect(SyncStatusPresentation.tint(for: .error(message: "x")) == DesignTokens.negative)
    }

    // MARK: - relativeLastSynced(_:now:)

    @Test("nil date reads Never synced")
    func relativeNil() {
        #expect(SyncStatusPresentation.relativeLastSynced(nil) == "Never synced")
    }

    @Test("sub-minute reads Just now")
    func relativeJustNow() {
        let now = Date()
        let recent = now.addingTimeInterval(-10)
        #expect(SyncStatusPresentation.relativeLastSynced(recent, now: now) == "Just now")
    }

    @Test("90 seconds ago mentions minutes")
    func relativeMinutes() {
        let now = Date()
        let old = now.addingTimeInterval(-90)
        #expect(SyncStatusPresentation.relativeLastSynced(old, now: now).contains("minute"))
    }

    // MARK: - mergeSummary(_:)

    @Test("nil stats yields no summary row")
    func mergeNil() {
        #expect(SyncStatusPresentation.mergeSummary(nil) == nil)
    }

    @Test("mixed stats list only non-zero components")
    func mergeMixed() {
        let stats = MergeStats(inserted: 3, updated: 2, deleted: 1, skipped: 4, adopted: 0)
        #expect(SyncStatusPresentation.mergeSummary(stats) == "3 added · 2 updated · 1 removed")
    }

    @Test("zero-activity merge reads as already in sync")
    func mergeZero() {
        let stats = MergeStats(inserted: 0, updated: 0, deleted: 0, skipped: 0, adopted: 0)
        #expect(SyncStatusPresentation.mergeSummary(stats) == "Nothing new — already in sync")
    }

    @Test("omits zero leading components but keeps at least one")
    func mergePartial() {
        let stats = MergeStats(inserted: 0, updated: 0, deleted: 5, skipped: 0, adopted: 0)
        #expect(SyncStatusPresentation.mergeSummary(stats) == "5 removed")
    }
}
