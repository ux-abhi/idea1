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

    /// The notch's one line: numbers first, short (§7 Voice).
    public func statusLine(now: Date, calendar: Calendar = .current) -> String {
        if let event = today(now: now, calendar: calendar).first {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes <= 0 {
                let ago = Int(now.timeIntervalSince(event.start) / 60)
                return ago < 1 ? "\(event.title) now" : "\(event.title) · started \(ago) min ago"
            }
            if minutes <= 60 { return "\(event.title) in \(minutes) min" }
            return "Next: \(event.title) at \(event.start.formatted(date: .omitted, time: .shortened))"
        }
        switch reminders.count {
        case 0: return "All clear"
        case 1: return "1 reminder today"
        default: return "\(reminders.count) reminders today"
        }
    }
}

/// When the notch speaks first about a meeting (ARCHITECTURE §9.3, §8).
public enum MeetingCue: Equatable, Sendable {
    /// T−10 to T−3: peek once, eyes Heads-up.
    case headsUp(AgendaEvent)
    /// T−3 to T+5: P0, open the meeting card once.
    case imminent(AgendaEvent)

    public var event: AgendaEvent {
        switch self { case .headsUp(let e), .imminent(let e): e }
    }

    static let headsUpLead: TimeInterval = 10 * 60
    static let imminentLead: TimeInterval = 3 * 60
    static let lingerAfterStart: TimeInterval = 5 * 60
}

extension Agenda {
    /// The first event with something to say right now.
    public func cue(now: Date) -> MeetingCue? {
        for event in events where event.end > now {
            let toStart = event.start.timeIntervalSince(now)
            if toStart > MeetingCue.headsUpLead { return nil } // sorted: nothing later is closer
            if toStart > MeetingCue.imminentLead { return .headsUp(event) }
            if toStart > -MeetingCue.lingerAfterStart { return .imminent(event) }
        }
        return nil
    }

    /// The next moment `cue(now:)` can change, so the notch can sleep until then instead of polling.
    public func nextCueChange(after now: Date) -> Date? {
        events.flatMap { e in
            [e.start - MeetingCue.headsUpLead, e.start - MeetingCue.imminentLead, e.start + MeetingCue.lingerAfterStart]
        }
        .filter { $0 > now }
        .min()
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
        return Agenda(events: events, reminders: reminders)
    }
}
