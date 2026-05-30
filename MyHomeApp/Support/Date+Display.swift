import Foundation

extension Date {
    /// Formats this date for display in the expense list.
    ///
    /// Output uses the user's current locale and timezone (D-02: store UTC, display local).
    /// Example: "29 May 2026, 9:41 AM"
    func formattedForExpenseList() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current    // user's locale
        formatter.timeZone = .current  // user's timezone for display
        return formatter.string(from: self)
    }

    /// Formats this date for the date-picker row in the add/edit sheet.
    ///
    /// Shows "Today, 9:41 AM" when the date is today; otherwise "29 May 2026, 9:41 AM".
    func formattedForDatePickerRow() -> String {
        if Calendar.current.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            formatter.locale = .current
            formatter.timeZone = .current
            return "Today, \(formatter.string(from: self))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = .current
            formatter.timeZone = .current
            return formatter.string(from: self)
        }
    }

    /// Formats this date as "May 2026" for the Budgets tab month pager.
    ///
    /// Uses the user's current locale and timezone (D-02: store UTC, display local).
    /// Example: "May 2026"
    func formattedAsMonthYear() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        // Locale-adaptive ordering (e.g. year-before-month in ja/ko/zh).
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: self)
    }
}
