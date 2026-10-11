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
        let shifted = date.addingTimeInterval(-Double(wakeHour * 3600 + wakeMinute * 60))
        return calendar.startOfDay(for: shifted)
    }

    public static func key(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
        // A habit added after midnight but before wake time belongs to the habit day still running (today).
        let created = min(calendar.startOfDay(for: createdAt), today)
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
