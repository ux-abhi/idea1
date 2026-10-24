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

    /// Where an unfinished task or reminder goes with "Move to tomorrow": the same time tomorrow, or 9:00 tomorrow when
    /// it had no time (a day-only one, or none at all).
    public static func movedToTomorrow(_ due: Date?, timed: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let time = (due.map { calendar.dateComponents([.hour, .minute], from: $0) }).flatMap { timed ? $0 : nil }
        return calendar.date(bySettingHour: time?.hour ?? 9, minute: time?.minute ?? 0, second: 0, of: tomorrow) ?? tomorrow
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
