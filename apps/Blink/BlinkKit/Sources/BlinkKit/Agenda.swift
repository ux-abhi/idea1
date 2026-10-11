// © Pexilim
import EventKit
import Foundation

/// One calendar occurrence. Identity = external id + occurrence start + source (ARCHITECTURE §36.1).
public struct AgendaEvent: Sendable, Equatable, Identifiable {
    public let extID: String
    public let source: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let url: URL?

    public var id: String { "\(source)|\(extID)|\(start.timeIntervalSince1970)" }

    public init(extID: String, source: String = "eventkit", title: String, start: Date, end: Date,
                location: String? = nil, url: URL? = nil) {
        self.extID = extID
        self.source = source
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.url = url
    }
}

public struct AgendaReminder: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?

    public init(id: String, title: String, due: Date?) {
        self.id = id
        self.title = title
        self.due = due
    }
}

extension AgendaReminder {
    /// Reminders that have a due date today or earlier. Undated ones stay in Reminders, out of the notch.
    public static func dueToday(_ reminders: [AgendaReminder], now: Date, calendar: Calendar = .current) -> [AgendaReminder] {
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return reminders.filter { ($0.due ?? .distantFuture) < endOfToday }
    }
}

/// Something with a due time: a timed Apple Reminder or a Blink task.
public struct DueItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date

    public init(id: String, title: String, due: Date) {
        self.id = id
        self.title = title
        self.due = due
    }
}

/// What's coming up: timed events (no all-day, no declined) and reminders due today.
public struct Agenda: Sendable, Equatable {
    public var events: [AgendaEvent]
    public var reminders: [AgendaReminder]

    public static let empty = Agenda(events: [], reminders: [])

    public init(events: [AgendaEvent], reminders: [AgendaReminder]) {
        self.events = events.sorted { $0.start < $1.start }
        self.reminders = reminders
    }

    /// The event happening now, or else the next one.
    public func next(after now: Date) -> AgendaEvent? {
        events.first { $0.end > now }
    }

    /// Events still to come or under way today, in the current calendar.
    public func today(now: Date, calendar: Calendar = .current) -> [AgendaEvent] {
        events.filter { $0.end > now && calendar.isDate($0.start, inSameDayAs: now) }
    }

    /// Timed reminders plus the given tasks, soonest first.
    public func dueItems(adding tasks: [DueItem] = []) -> [DueItem] {
        (reminders.compactMap { r in r.due.map { DueItem(id: r.id, title: r.title, due: $0) } } + tasks)
            .sorted { $0.due < $1.due }
    }

    /// The notch's one line: numbers first, short (§7 Voice).
    public func statusLine(now: Date, tasks: [DueItem] = [], calendar: Calendar = .current) -> String {
        let due = dueItems(adding: tasks)
        // A reminder or task due within the hour (or in the last 5 min) is told like a meeting.
        let soon = due.first { $0.due > now - MeetingCue.lingerAfterStart && $0.due.timeIntervalSince(now) <= 3600 }
        let event = today(now: now, calendar: calendar).first
        if let soon, event.map({ soon.due < $0.start }) ?? true {
            let minutes = Int((soon.due.timeIntervalSince(now) / 60).rounded(.up))
            return minutes <= 0 ? "\(soon.title) now" : "\(soon.title) in \(minutes) min"
        }
        if let event {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes <= 0 {
                let ago = Int(now.timeIntervalSince(event.start) / 60)
                return ago < 1 ? "\(event.title) now" : "\(event.title) · started \(ago) min ago"
            }
            if minutes <= 60 { return "\(event.title) in \(minutes) min" }
            return "Next: \(event.title) at \(event.start.formatted(date: .omitted, time: .shortened))"
        }
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let today = due.filter { $0.due < endOfToday }.count
        return today == 0 ? "All clear" : "\(today) due today"
    }
}

/// When the notch speaks first about a meeting (ARCHITECTURE §9.3, §8).
public enum MeetingCue: Equatable, Sendable {
    /// T−10 to T−3: peek once, eyes Heads-up.
    case headsUp(AgendaEvent)
    /// T−3 to T+5: P0, open the meeting card once.
    case imminent(AgendaEvent)
    /// 10 min before a reminder or task: peek once, eyes Heads-up (§7: "meeting/reminder ≤10 min").
    case dueSoon(DueItem)
    /// Due now to +5 min: a reminder or task you set for now (P0, §8).
    case due(DueItem)

    public var event: AgendaEvent? {
        switch self {
        case .headsUp(let e), .imminent(let e): e
        case .dueSoon, .due: nil
        }
    }

    /// Identity for "speak once": the event or the item.
    public var id: String {
        switch self {
        case .headsUp(let e), .imminent(let e): e.id
        case .dueSoon(let item), .due(let item): item.id
        }
    }

    static let headsUpLead: TimeInterval = 10 * 60
    static let imminentLead: TimeInterval = 3 * 60
    static let lingerAfterStart: TimeInterval = 5 * 60
}

extension Agenda {
    /// What the notch should say first right now: an imminent meeting, then anything due now, then a heads-up.
    public func cue(now: Date, tasks: [DueItem] = []) -> MeetingCue? {
        let meeting = meetingCue(now: now)
        if case .imminent = meeting { return meeting }
        let due = dueItems(adding: tasks)
        if let item = due.first(where: { $0.due <= now && now < $0.due + MeetingCue.lingerAfterStart }) {
            return .due(item)
        }
        if let meeting { return meeting }
        if let item = due.first(where: { $0.due > now && $0.due.timeIntervalSince(now) <= MeetingCue.headsUpLead }) {
            return .dueSoon(item)
        }
        return nil
    }

    private func meetingCue(now: Date) -> MeetingCue? {
        for event in events where event.end > now {
            let toStart = event.start.timeIntervalSince(now)
            if toStart > MeetingCue.headsUpLead { return nil } // sorted: nothing later is closer
            if toStart > MeetingCue.imminentLead { return .headsUp(event) }
            if toStart > -MeetingCue.lingerAfterStart { return .imminent(event) }
        }
        return nil
    }

    /// The next moment `cue(now:)` can change, so the notch can sleep until then instead of polling.
    public func nextCueChange(after now: Date, tasks: [DueItem] = []) -> Date? {
        let meetingTimes = events.flatMap { e in
            [e.start - MeetingCue.headsUpLead, e.start - MeetingCue.imminentLead, e.start + MeetingCue.lingerAfterStart]
        }
        let dueTimes = dueItems(adding: tasks).flatMap {
            [$0.due - MeetingCue.headsUpLead, $0.due, $0.due + MeetingCue.lingerAfterStart]
        }
        return (meetingTimes + dueTimes).filter { $0 > now }.min()
    }

    /// The morning brief's summary line, numbers first.
    public func briefLine(now: Date, calendar: Calendar = .current) -> String {
        let todays = events.filter { calendar.isDate($0.start, inSameDayAs: now) }
        var parts: [String] = []
        if let first = todays.first {
            parts.append(todays.count == 1 ? "1 meeting" : "\(todays.count) meetings")
            parts.append("first at \(first.start.formatted(date: .omitted, time: .shortened))")
        } else {
            parts.append("No meetings today")
        }
        if !reminders.isEmpty { parts.append(reminders.count == 1 ? "1 reminder" : "\(reminders.count) reminders") }
        return parts.joined(separator: " · ")
    }
}

extension AgendaEvent {
    /// A meeting link from the event's URL, or a location that is a web address.
    public var joinURL: URL? {
        if let url, url.scheme?.hasPrefix("http") == true { return url }
        guard let location, let url = URL(string: location.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

/// Reads the device's calendars and reminders. An actor so EventKit stays off the main actor (§36.1).
public actor CalendarReader {
    public enum Access: Sendable, Equatable { case notAsked, granted, denied }

    private let store = EKEventStore()

    public init() {}

    /// Both events and reminders need full access; anything less counts as denied.
    public nonisolated static var access: Access {
        let statuses = [EKEventStore.authorizationStatus(for: .event), EKEventStore.authorizationStatus(for: .reminder)]
        if statuses.allSatisfy({ $0 == .fullAccess }) { return .granted }
        if statuses.contains(.notDetermined) && !statuses.contains(where: { $0 == .denied || $0 == .restricted }) { return .notAsked }
        return .denied
    }

    public func requestAccess() async -> Access {
        _ = try? await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()
        return Self.access
    }

    /// Creates a reminder in the default list; returns its identifier for the action's result (undo later).
    public func addReminder(_ title: String, due: Date?, calendar: Calendar = .current) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public struct ReminderGone: Error {}

    /// Edits an Apple Reminder in place (synced by iCloud like any other edit).
    public func updateReminder(id: String, title: String? = nil, completed: Bool? = nil) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ReminderGone() }
        if let title { reminder.title = title }
        if let completed { reminder.isCompleted = completed }
        try store.save(reminder, commit: true)
    }

    public func setReminderDue(id: String, due: Date?, calendar: Calendar = .current) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ReminderGone() }
        reminder.dueDateComponents = due.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        try store.save(reminder, commit: true)
    }

    /// The span Blink reads and uploads: from now to the end of the 7th day.
    public static func window(from now: Date, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: now, end: max(end, now))
    }

    /// Timed events in `window`, plus incomplete reminders due by the end of today.
    public func agenda(in window: DateInterval, calendar: Calendar = .current) async -> Agenda {
        guard Self.access == .granted else { return .empty }
        let now = window.start
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate).compactMap { event -> AgendaEvent? in
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            guard !event.isAllDay, !declined, let start = event.startDate, let finish = event.endDate else { return nil }
            return AgendaEvent(extID: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier,
                               title: event.title ?? "Untitled", start: start, end: finish,
                               location: event.location, url: event.url)
        }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let reminderPredicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        let reminders: [AgendaReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: reminderPredicate) { found in
                let mapped = (found ?? []).map {
                    AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled",
                                   due: $0.dueDateComponents.flatMap { calendar.date(from: $0) })
                }
                continuation.resume(returning: mapped)
            }
        }
        return Agenda(events: events, reminders: AgendaReminder.dueToday(reminders, now: now, calendar: calendar))
    }
}
