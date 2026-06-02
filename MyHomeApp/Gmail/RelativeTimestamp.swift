import Foundation

// MARK: - Date.relativeToNow (D6-16, ING-05, SET-05)

extension Date {
    /// Returns a human-readable relative date string (e.g., "2 hours ago").
    ///
    /// Uses `RelativeDateTimeFormatter` with `unitsStyle = .full` (D6-16).
    /// Display format: "Last synced 2 hours ago".
    ///
    /// ING-05: Always-visible last-synced timestamp in Settings.
    /// SET-05: Relative display format.
    var relativeToNow: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
