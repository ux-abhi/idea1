// © Pexilim
import Foundation

/// Where an open task or reminder sits on the Tasks page: late, today, later, or no date at all.
public enum DueGroup: String, CaseIterable, Sendable {
    case overdue = "Overdue", today = "Today", upcoming = "Upcoming", someday = "Someday"

    public static func of(_ due: Date?, now: Date, calendar: Calendar = .current) -> DueGroup {
        guard let due else { return .someday }
        // A reminder with a date but no time comes back as midnight: it belongs to the whole day, not to "late".
        if due == calendar.startOfDay(for: now) { return .today }
        if due < now { return .overdue }
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return .upcoming }
        return due < endOfToday ? .today : .upcoming
    }
}
