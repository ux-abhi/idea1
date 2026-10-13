// © Pexilim
import Foundation

/// The once-a-day reminder of mail waiting for a reply: from `hour` on, once per day, only when something is waiting.
public enum ReplyDigest {
    public static let hour = 10

    public static func due(now: Date, shownOn: String?, waiting: Int, calendar: Calendar = .current) -> Bool {
        waiting > 0 && calendar.component(.hour, from: now) >= hour && shownOn != HabitDay.key(now, calendar: calendar)
    }

    /// When today's digest could next show (10:00 today), for the notch's timer; nil once it's past.
    public static func nextTime(after now: Date, calendar: Calendar = .current) -> Date? {
        let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)
        return at.flatMap { $0 > now ? $0 : nil }
    }

    public static func text(_ waiting: Int) -> String {
        waiting == 1 ? "✉︎ 1 email is waiting for your reply" : "✉︎ \(waiting) emails are waiting for your reply"
    }
}
