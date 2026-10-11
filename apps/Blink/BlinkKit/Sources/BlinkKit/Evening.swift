// © Pexilim
import Foundation

/// The evening check-in (ARCHITECTURE §9.4): due once per habit day, from the owner's evening time until they wake.
public enum EveningCheck {
    /// The moment today's check-in opens (the evening time on the current habit day).
    public static func opens(now: Date, evening: (hour: Int, minute: Int), wake: (hour: Int, minute: Int),
                             calendar: Calendar = .current) -> Date {
        let day = HabitDay.day(for: now, wakeHour: wake.hour, wakeMinute: wake.minute, calendar: calendar)
        return calendar.date(bySettingHour: evening.hour, minute: evening.minute, second: 0, of: day) ?? day
    }

    /// Due when it has opened and wasn't finished since it opened.
    public static func isDue(now: Date, evening: (hour: Int, minute: Int), wake: (hour: Int, minute: Int),
                             lastDone: Date?, calendar: Calendar = .current) -> Bool {
        let open = opens(now: now, evening: evening, wake: wake, calendar: calendar)
        return now >= open && (lastDone ?? .distantPast) < open
    }
}

extension Agenda {
    /// "2 meetings · first at 10:00" or "No meetings" for any day (tomorrow, in the evening check-in).
    public func dayLine(for day: Date, calendar: Calendar = .current) -> String {
        let events = self.events.filter { calendar.isDate($0.start, inSameDayAs: day) }
        guard let first = events.first else { return "No meetings" }
        let count = events.count == 1 ? "1 meeting" : "\(events.count) meetings"
        return "\(count) · first at \(first.start.formatted(date: .omitted, time: .shortened))"
    }
}
