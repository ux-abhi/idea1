// © Pexilim
import EventKit
import Foundation

/// One calendar occurrence. Identity = external id + occurrence start + source (ARCHITECTURE §36.1).
/// Where each meeting of one day sits in a calendar column: meetings that overlap share the width side by side.
public struct EventLane: Equatable, Sendable {
    public let event: AgendaEvent
    /// 0-based position among `of` side-by-side lanes.
    public let lane: Int
    public let of: Int

    /// Greedy lanes: each meeting takes the first lane free at its start; a group of overlapping meetings shares one
    /// lane count, so their widths line up.
    public static func layout(_ events: [AgendaEvent]) -> [EventLane] {
        let sorted = events.sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        var result: [EventLane] = []
        var group: [(AgendaEvent, Int)] = []
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast
        func close() {
            result += group.map { EventLane(event: $0.0, lane: $0.1, of: max(laneEnds.count, 1)) }
            group = []; laneEnds = []
        }
        for event in sorted {
            if event.start >= groupEnd { close() }
            let lane = laneEnds.firstIndex { $0 <= event.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(event.end) } else { laneEnds[lane] = event.end }
            group.append((event, lane))
            groupEnd = max(groupEnd, event.end)
        }
        close()
        return result
    }
}

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
    /// False for a reminder set for a day without a time: it counts as due today but never cues at midnight.
    public let timed: Bool

    public init(id: String, title: String, due: Date?, timed: Bool = true) {
        self.id = id
        self.title = title
        self.due = due
        self.timed = timed
    }

    /// EventKit's due components: the date, and whether it has a time of day.
    static func due(from components: DateComponents?, calendar: Calendar) -> (date: Date?, timed: Bool) {
        (components.flatMap { calendar.date(from: $0) }, components?.hour != nil)
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
        (reminders.compactMap { r in r.timed ? r.due.map { DueItem(id: r.id, title: r.title, due: $0) } : nil } + tasks)
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

    /// Identity for "speak once": the event, or the item at its due time, so an item moved with Later cues again.
    public var id: String {
        switch self {
        case .headsUp(let e), .imminent(let e): e.id
        case .dueSoon(let item), .due(let item): "\(item.id)@\(Int(item.due.timeIntervalSince1970))"
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

    /// Today's hero: one big value and a caption, e.g. ("12 min", "until Design review"), ("3", "due today").
    public func hero(now: Date, tasks: [DueItem] = [], calendar: Calendar = .current) -> (value: String, caption: String) {
        if let event = today(now: now, calendar: calendar).first {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes <= 0 { return ("Now", event.title) }
            if minutes < 60 { return ("\(minutes) min", "until \(event.title)") }
            if minutes < 180 {
                let h = minutes / 60, m = minutes % 60
                return (m == 0 ? "\(h) h" : "\(h) h \(m) min", "until \(event.title)")
            }
            return (event.start.formatted(date: .omitted, time: .shortened), "Next: \(event.title)")
        }
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let due = dueItems(adding: tasks).filter { $0.due < endOfToday }.count
        if due > 0 { return ("\(due)", "due today") }
        return ("All clear", "Nothing else on your calendar today")
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

extension Agenda {
    /// One copy of each meeting: the same title at the same times in two calendars (an invite in iCloud and Google) shows once.
    public static func uniqued(_ events: [AgendaEvent]) -> [AgendaEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert("\($0.title.lowercased())|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)").inserted }
    }

    /// "Fri 23 Oct, 18:00", or "Fri 1 Oct 2027" when it's another year and no time was set (a day-only date is midnight).
    public static func dueLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month()
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if parts.hour != 0 || parts.minute != 0 { style = style.hour().minute() }
        return date.formatted(style)
    }

    /// Meetings the owner marked done are hidden from `shown`. A done id is kept while the calendar still lists it or its
    /// start was under a day ago, so a calendar that's still loading (Google after wake) never brings a done meeting back.
    public static func hidingDone(_ events: [AgendaEvent], done: Set<String>, now: Date) -> (shown: [AgendaEvent], keep: Set<String>) {
        let listed = Set(events.map(\.id))
        let keep = done.filter { id in
            // The id ends in the start time ("source|extID|seconds"); one that can't be read is dropped.
            listed.contains(id) || (id.split(separator: "|").last.flatMap { Double($0) }.map { now.timeIntervalSince1970 - $0 < 86_400 } ?? false)
        }
        return (events.filter { !keep.contains($0.id) }, keep)
    }
}

extension AgendaEvent {
    /// A link to a known call service (Meet, Zoom, Teams…) from the event's URL (CalendarReader also fills it from the
    /// notes) or its location. Any other web address is never a Join button: invites and mail come from strangers.
    public var joinURL: URL? {
        Self.meetingLink(in: url?.absoluteString) ?? Self.meetingLink(in: location)
    }

    /// Join is offered from 10 minutes before the start until the meeting ends (not just the first minutes).
    public func joinable(at now: Date) -> Bool {
        start.timeIntervalSince(now) <= MeetingCue.headsUpLead && now < end
    }

    /// The first video-call link in some text, e.g. the Meet link Google Calendar puts in an invite's notes. Only known
    /// call services count, so a random link in the notes never becomes a Join button.
    public static func meetingLink(in text: String?) -> URL? {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first { url in
            guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    static let meetingHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com",
                               "whereby.com", "meet.jit.si", "facetime.apple.com"]
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
    public func addReminder(_ title: String, due: Date?, notes: String? = nil, url: URL? = nil, list: String? = nil,
                            calendar: Calendar = .current) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.calendar = try list.map { try reminderList(named: $0) } ?? store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public struct ReminderGone: Error {}

    /// The Reminders list a Space keeps its reminders in (named like the Space), made the first time it's needed, in
    /// the same account as the default list so it syncs to the owner's iPhone.
    public func reminderList(named name: String) throws -> EKCalendar {
        if let list = store.calendars(for: .reminder).first(where: { $0.title == name }) { return list }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw ReminderGone()
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    /// A Space was renamed: its Reminders list follows, so the two stay linked.
    public func renameReminderList(from old: String, to new: String) throws {
        guard old != new, let list = store.calendars(for: .reminder).first(where: { $0.title == old }) else { return }
        list.title = new
        try store.saveCalendar(list, commit: true)
    }

    /// Open reminders in one list (a Space's), soonest first; empty when the list doesn't exist yet.
    public func reminders(inList name: String, calendar: Calendar = .current) async -> [AgendaReminder] {
        guard Self.access == .granted, let list = store.calendars(for: .reminder).first(where: { $0.title == name }) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let mapped = (found ?? []).map {
                    let due = AgendaReminder.due(from: $0.dueDateComponents, calendar: calendar)
                    return AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled", due: due.date, timed: due.timed)
                }
                continuation.resume(returning: mapped.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    /// Adds an event to the default calendar (the owner's own; no guests); returns its identifier for Undo.
    public func addEvent(_ title: String, start: Date, end: Date?, allDay: Bool, location: String, notes: String, url: URL?) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        // A calendar day, not 24 hours: the clock-change day is 23 or 25 hours long.
        event.endDate = end ?? (allDay ? Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start : start.addingTimeInterval(3600))
        event.isAllDay = allDay
        if !location.isEmpty { event.location = location }
        event.notes = notes
        event.url = url
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
    }

    public func deleteEvent(id: String) throws {
        guard let event = store.calendarItem(withIdentifier: id) as? EKEvent else { throw ReminderGone() }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// Every incomplete reminder (any date, at most `limit`), for chat: Claude can then propose finishing or deleting one.
    public func openReminders(limit: Int = 50, calendar: Calendar = .current) async -> [AgendaReminder] {
        guard Self.access == .granted else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let mapped = (found ?? []).prefix(limit).map {
                    let due = AgendaReminder.due(from: $0.dueDateComponents, calendar: calendar)
                    return AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled", due: due.date, timed: due.timed)
                }
                continuation.resume(returning: Array(mapped))
            }
        }
    }

    public func deleteReminder(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ReminderGone() }
        try store.remove(reminder, commit: true)
    }

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

    /// The span Blink reads and uploads: from now to the end of the 14th day (the 14-day snapshot, ARCHITECTURE §15).
    public static func window(from now: Date, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: now, end: max(end, now))
    }

    /// Timed events in `window`, plus incomplete reminders due by the end of today.
    public func agenda(in window: DateInterval, calendar: Calendar = .current) async -> Agenda {
        guard Self.access == .granted else { return .empty }
        let now = window.start
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let found = store.events(matching: predicate).compactMap { event -> AgendaEvent? in
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            guard !event.isAllDay, !declined, let start = event.startDate, let finish = event.endDate else { return nil }
            return AgendaEvent(extID: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier,
                               title: event.title ?? "Untitled", start: start, end: finish,
                               location: event.location, url: AgendaEvent.meetingLink(in: event.url?.absoluteString) ?? AgendaEvent.meetingLink(in: event.location)
                                ?? AgendaEvent.meetingLink(in: event.notes) ?? event.url)
        }

        let events = Agenda.uniqued(found)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let reminderPredicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        let reminders: [AgendaReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: reminderPredicate) { found in
                let mapped = (found ?? []).map {
                    let due = AgendaReminder.due(from: $0.dueDateComponents, calendar: calendar)
                    return AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled", due: due.date, timed: due.timed)
                }
                continuation.resume(returning: mapped)
            }
        }
        return Agenda(events: events, reminders: AgendaReminder.dueToday(reminders, now: now, calendar: calendar))
    }
}
