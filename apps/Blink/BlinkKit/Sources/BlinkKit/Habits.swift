// © Pexilim
import Foundation

/// A habit and its scheduled weekdays (Calendar weekdays, 1 = Sunday). Other days are rest days.
public struct Habit: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var weekdays: [Int]
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, weekdays
        case createdAt = "created_at"
    }

    public init(id: String, name: String, weekdays: [Int] = Array(1...7), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.createdAt = createdAt
    }
}

/// Done / Not today / Skip: all neutral words (§36.2).
public enum HabitAnswer: String, Codable, Sendable { case done, notToday = "not_today", skipped }

public struct HabitLog: Codable, Equatable, Sendable {
    public let habitID: String
    /// The habit day as "yyyy-MM-dd".
    public let day: String
    public let status: HabitAnswer

    enum CodingKeys: String, CodingKey {
        case habitID = "habit_id", day, status
    }

    public init(habitID: String, day: String, status: HabitAnswer) {
        self.habitID = habitID
        self.day = day
        self.status = status
    }
}

/// Habit days end at the owner's wake time, in the device's current time zone (§36.2).
public enum HabitDay {
    /// The start of the habit day that `date` belongs to. Before wake time it still counts as yesterday.
    public static func day(for date: Date, wakeHour: Int, wakeMinute: Int, calendar: Calendar = .current) -> Date {
        // Clock time, not elapsed seconds: on the days the clocks change, 07:30 is still after a 07:00 wake.
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let start = calendar.startOfDay(for: date)
        guard (time.hour ?? 0) * 60 + (time.minute ?? 0) < wakeHour * 60 + wakeMinute else { return start }
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    /// The day a "2026-10-12" key stands for.
    public static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func key(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The first day whose answers can count toward a streak: the day before the oldest habit was made (one added
    /// after midnight can answer for the running habit day), so long streaks are never cut short.
    public static func answersSince(_ habits: [Habit], today: Date, calendar: Calendar = .current) -> String {
        let oldest = min(habits.map { calendar.startOfDay(for: $0.createdAt) }.min() ?? today, today)
        return key(calendar.date(byAdding: .day, value: -1, to: oldest) ?? oldest, calendar: calendar)
    }
}

public struct HabitProgress: Equatable, Sendable {
    public let streak: Int
    /// Done out of scheduled, non-skipped days in the last 7 ("kept 5 of 7").
    public let kept: Int
    public let of: Int

    /// Celebrate only at 7, 30 and 100 days (§36.2).
    public var isMilestone: Bool { [7, 30, 100].contains(streak) }
}

extension Habit {
    /// Streak rules (§36.2): rest days and skips never break it; one missed day per week is forgiven
    /// automatically; an unanswered today doesn't count against it yet.
    public func progress(answers: [String: HabitAnswer], today: Date, calendar: Calendar = .current) -> HabitProgress {
        // Habit days run from wake time to wake time, so a habit added after midnight can already have an answer for
        // the day before its calendar date: count from whichever is earliest.
        let firstAnswer = answers.keys.min().flatMap { HabitDay.date(fromKey: $0, calendar: calendar) } ?? .distantFuture
        let created = min(calendar.startOfDay(for: createdAt), today, firstAnswer)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let start = answers[HabitDay.key(today, calendar: calendar)] == nil ? yesterday : today
        let (kept, of) = kept(answers, start, created, calendar)

        var streak = 0
        var forgivenWeeks = Set<String>()
        var day = start
        while day >= created {
            defer { day = calendar.date(byAdding: .day, value: -1, to: day) ?? created.addingTimeInterval(-1) }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue } // rest day
            switch answers[HabitDay.key(day, calendar: calendar)] {
            case .done: streak += 1
            case .skipped: continue
            case .notToday, nil:
                let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
                guard forgivenWeeks.insert("\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)").inserted else {
                    return HabitProgress(streak: streak, kept: kept, of: of)
                }
            }
        }
        return HabitProgress(streak: streak, kept: kept, of: of)
    }

    private func kept(_ answers: [String: HabitAnswer], _ end: Date, _ created: Date, _ calendar: Calendar) -> (Int, Int) {
        var done = 0, scheduled = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end), day >= created,
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            let answer = answers[HabitDay.key(day, calendar: calendar)]
            if answer == .skipped { continue }
            scheduled += 1
            if answer == .done { done += 1 }
        }
        return (done, scheduled)
    }
}
