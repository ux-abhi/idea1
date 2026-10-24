// © Pexilim
import Foundation

/// The Sunday "Your week" card on Today: a calm look back, never a score. It shows on Sunday and Monday until it's
/// closed for that week.
public enum WeekReview {
    /// "2026-W43": the week a date belongs to, for "closed this week".
    public static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(parts.yearForWeekOfYear ?? 0)-W\(parts.weekOfYear ?? 0)"
    }

    /// True on Sunday and Monday, unless the card was closed this week (or, on Monday, the day before).
    public static func isShowing(now: Date, closedWeek: String?, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday, 2 = Monday
        guard weekday == 1 || weekday == 2 else { return false }
        // Monday belongs to a new week in most calendars: the review it shows is still the one Sunday opened.
        let reviewDay = weekday == 2 ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now) : now
        return closedWeek != weekKey(reviewDay, calendar: calendar)
    }

    /// The week being reviewed, as a key: Sunday's own week, also on Monday.
    public static func reviewedWeek(now: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: now)
        return weekKey(weekday == 2 ? (calendar.date(byAdding: .day, value: -1, to: now) ?? now) : now, calendar: calendar)
    }
}
