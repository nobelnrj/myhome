import SwiftUI

// MARK: - SyncStatusPresentation (pure)

/// SYNC-05 — the pure, deterministic mapping from `SyncStatusStore` state to the strings,
/// SF Symbols, and DesignTokens the sync surface renders. No SwiftUI state, no rendering,
/// every input passed in — so the whole presentation layer is unit-tested without a view.
///
/// This type defines ZERO colors: every `tint` returns an EXISTING `DesignTokens` member
/// (the dark-branch byte-identity guard, DarkBitIdentityTests, must stay green).
enum SyncStatusPresentation {

    /// Human-readable status line. `.idle` reads differently before vs. after a first sync so
    /// a never-synced phone doesn't claim to be "Up to date". `.error` is already a
    /// human-readable message from Plan 02, so it passes through verbatim.
    static func label(for status: PeerSyncStatus, lastSyncedAt: Date?) -> String {
        switch status {
        case .idle:
            return lastSyncedAt != nil ? "Up to date" : "Not synced yet"
        case .connecting:
            return "Looking for your other phone…"
        case .syncing:
            return "Syncing…"
        case .error(let message):
            return message
        }
    }

    /// SF Symbol name for the status glyph.
    static func systemImage(for status: PeerSyncStatus) -> String {
        switch status {
        case .idle:       return "checkmark.circle"
        case .connecting: return "dot.radiowaves.left.and.right"
        case .syncing:    return "arrow.triangle.2.circlepath"
        case .error:      return "exclamationmark.triangle"
        }
    }

    /// Status tint — always an EXISTING `DesignTokens` member (this file defines no colors).
    static func tint(for status: PeerSyncStatus) -> Color {
        switch status {
        case .idle:       return DesignTokens.positive
        case .connecting: return DesignTokens.label2
        case .syncing:    return DesignTokens.accentText
        case .error:      return DesignTokens.negative
        }
    }

    /// Relative "last synced" text. `nil` → "Never synced"; under a minute → "Just now"
    /// (an explicit branch that side-steps `RelativeDateTimeFormatter`'s "in 0 seconds"
    /// weirdness for sub-minute intervals); otherwise a named relative string ("2 minutes ago").
    static func relativeLastSynced(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never synced" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// One-line summary of the most recent merge. `nil` stats → `nil` (no row shown); a merge
    /// that changed nothing → "Nothing new — already in sync"; otherwise the non-zero
    /// components joined ("3 added · 2 updated · 1 removed"), always ≥1 component.
    static func mergeSummary(_ stats: MergeStats?) -> String? {
        guard let stats else { return nil }
        var parts: [String] = []
        if stats.inserted > 0 { parts.append("\(stats.inserted) added") }
        if stats.updated  > 0 { parts.append("\(stats.updated) updated") }
        if stats.deleted  > 0 { parts.append("\(stats.deleted) removed") }
        if parts.isEmpty { return "Nothing new — already in sync" }
        return parts.joined(separator: " · ")
    }
}
