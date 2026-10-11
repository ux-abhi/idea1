// © Pexilim
import Foundation

/// One thing on today's timeline: a meeting, a Blink task or an Apple Reminder.
public struct DayEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case meeting, task, reminder }

    public let id: String
    public let kind: Kind
    public let title: String
    public let start: Date
    /// Meetings only.
    public let end: Date?
    /// For meetings: the event itself, for Join and location.
    public let event: AgendaEvent?
}

/// Today on one time axis (the "schedule checker", ARCHITECTURE §29 Phase 2): what slipped from earlier days,
/// what has no time, and everything timed in order, with where "now" falls.
public struct DayPlan: Equatable, Sendable {
    public var overdue: [DayEntry] = []
    public var anytime: [DayEntry] = []
    public var timed: [DayEntry] = []
    /// Index in `timed` where the now line goes (timed.count when everything is earlier).
    public var nowIndex = 0

    public var isEmpty: Bool { overdue.isEmpty && anytime.isEmpty && timed.isEmpty }

    public init(events: [AgendaEvent], tasks: [DueItem], reminders: [AgendaReminder], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        for event in events where event.start >= today && event.start < tomorrow {
            timed.append(DayEntry(id: event.id, kind: .meeting, title: event.title, start: event.start, end: event.end, event: event))
        }
        let due = tasks.map { (DayEntry.Kind.task, $0.id, $0.title, $0.due) }
            + reminders.compactMap { r in r.due.map { (DayEntry.Kind.reminder, r.id, r.title, $0) } }
        for (kind, id, title, at) in due where at < tomorrow {
            let entry = DayEntry(id: id, kind: kind, title: title, start: at, end: nil, event: nil)
            if at < today {
                overdue.append(entry)
            } else if kind == .reminder && at == today {
                // A reminder with a date but no time comes back as midnight: it belongs to the whole day.
                anytime.append(entry)
            } else {
                timed.append(entry)
            }
        }
        overdue.sort { $0.start < $1.start }
        timed.sort { $0.start < $1.start }
        // The now line sits before the first thing that hasn't started (a meeting under way stays above it).
        nowIndex = timed.firstIndex { $0.start > now } ?? timed.count
    }
}
