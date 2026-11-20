// © Pexilim
import Foundation

/// One of this week's goals (`weekly_goal`): a counter the owner ticks by hand ("Create 5 posts", target 5) or a single
/// check (target 1). Nothing counts automatically.
public struct WeeklyGoal: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var target: Int
    public var doneCount: Int
    /// The Monday the week starts on ("2026-11-16").
    public var weekStart: String
    public var spaceID: String?
    public var position: Int

    enum CodingKeys: String, CodingKey {
        case id, title, target, position
        case doneCount = "done_count", weekStart = "week_start", spaceID = "segment_id"
    }

    public init(id: String = UUID().uuidString.lowercased(), title: String, target: Int = 1, doneCount: Int = 0,
                weekStart: String, spaceID: String? = nil, position: Int = 0) {
        (self.id, self.title, self.target, self.doneCount) = (id, title, max(1, min(target, 100)), doneCount)
        (self.weekStart, self.spaceID, self.position) = (weekStart, spaceID, position)
    }

    public var isCheck: Bool { target == 1 }
    public var isDone: Bool { doneCount >= target }
}

/// Plan my week: the week's Monday, reading goals from what the owner types, and moving what's left to next week.
public enum WeekPlan {
    /// The Monday of the week `date` is in, as "yyyy-MM-dd" (weeks start on Monday, as in Germany and India).
    public static func weekStart(of date: Date, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return HabitDay.key(start, calendar: cal)
    }

    /// Goals from text, one per line: "Create 5 posts" → 5, "Gym 3 times" or "3x gym" → "Gym", 3; a line without a
    /// count is a single check. Bullets and numbering are dropped; a number over 50 (a year, a price) isn't a count.
    public static func goals(from text: String) -> [(title: String, target: Int)] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: #"^([-•*]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            guard !line.isEmpty else { return nil }
            // "3 times", "3x", "x3": the count is said as a count, so it leaves the title.
            for pattern in [#"\b(\d{1,2})\s*(x|times|×)\b"#, #"\b(x|×)\s*(\d{1,2})\b"#] {
                if let match = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let n = Int(line[match].filter(\.isNumber)) ?? 1
                    let title = line.replacingCharacters(in: match, with: "")
                        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
                    if (1...50).contains(n), !title.isEmpty { return (String(title.prefix(200)), n) }
                }
            }
            // "Create 5 posts": the number is part of the goal, so the title stays as written.
            if let match = line.range(of: #"\b\d{1,2}\b"#, options: .regularExpression), let n = Int(line[match]), (2...50).contains(n) {
                return (String(line.prefix(200)), n)
            }
            return (String(line.prefix(200)), 1)
        }
    }

    /// Next week's copies of the goals not finished: what's left of each counter, nothing done yet.
    public static func carriedOver(_ goals: [WeeklyGoal], to week: String) -> [WeeklyGoal] {
        goals.filter { !$0.isDone }.enumerated().map { i, goal in
            WeeklyGoal(title: goal.title, target: goal.target - goal.doneCount, weekStart: week, spaceID: goal.spaceID, position: i)
        }
    }
}
