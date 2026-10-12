// © Pexilim
import Foundation

/// Where an open task or reminder sits on the Tasks page: late, today, later, or no date at all.
public enum DueGroup: String, CaseIterable, Sendable {
    case overdue = "Overdue", today = "Today", upcoming = "Upcoming", someday = "Someday"

    public static func of(_ due: Date?, now: Date, calendar: Calendar = .current) -> DueGroup {
        guard let due else { return .someday }
        if due < now { return .overdue }
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return .upcoming }
        return due < endOfToday ? .today : .upcoming
    }
}
