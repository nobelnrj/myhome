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

    // MARK: - Notes / Reminders (Phase 3)

    /// Formats a reminder date for display in note rows and the editor.
    ///
    /// All-day reminders show only the date ("29 May 2026").
    /// Timed reminders show date + time ("29 May 2026, 9:00 AM").
    /// Displays in the user's current timezone (D-02: store UTC, display local).
    func formattedAsReminderDate(isAllDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = isAllDay ? .none : .short
        return formatter.string(from: self)
    }

    /// Formats a reminder date as a compact short-form label for note row badges.
    ///
    /// Shows "Today", "Tomorrow", or "29 May" (no year unless different year).
    /// Displays in the user's current timezone (D-02: store UTC, display local).
    func formattedAsReminderBadge() -> String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInTomorrow(self) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        // Include year only when reminder is in a different calendar year
        let thisYear = cal.component(.year, from: Date())
        let reminderYear = cal.component(.year, from: self)
        if reminderYear == thisYear {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        }
        return formatter.string(from: self)
    }

    /// Formats this date as a calendar day number label ("1", "15", "31").
    ///
    /// Used in the Calendar month grid (03-06).
    /// Displays in the user's current timezone (D-02: store UTC, display local).
    func formattedAsCalendarDay() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    /// Formats this date as a short weekday abbreviation ("Mon", "Tue", …).
    ///
    /// Used in the Calendar grid column headers (03-06).
    /// Displays in the user's current timezone (D-02: store UTC, display local).
    func formattedAsWeekdayShort() -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}
