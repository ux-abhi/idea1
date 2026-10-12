// © Pexilim
import Foundation

/// A note or task from the `item` table (ARCHITECTURE §16).
public struct BlinkItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case note, task }
    public enum Status: String, Codable, Sendable { case open, done, archived }

    public let id: String
    public let type: Kind
    public var title: String
    public var body: String
    public var status: Status
    public var dueAt: Date?
    public var updatedAt: Date
    /// The Space it belongs to, if any.
    public var spaceID: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, status
        case dueAt = "due_at", updatedAt = "updated_at", spaceID = "segment_id"
    }

    public init(id: String, type: Kind, title: String, body: String = "", status: Status = .open,
                dueAt: Date? = nil, updatedAt: Date = .now, spaceID: String? = nil) {
        self.spaceID = spaceID
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.status = status
        self.dueAt = dueAt
        self.updatedAt = updatedAt
    }

    /// Open tasks due by the end of today, overdue ones included.
    public func isDue(by now: Date, calendar: Calendar = .current) -> Bool {
        guard type == .task, status == .open, let dueAt,
              let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
        return dueAt < endOfToday
    }

    /// Replaces local items with the server's, except ones with edits not yet saved: those keep the local text,
    /// so a refresh never overwrites writing (data-loss guard).
    public static func merge(server: [BlinkItem], local: [BlinkItem], unsaved: Set<String>) -> [BlinkItem] {
        let keep = Dictionary(uniqueKeysWithValues: local.filter { unsaved.contains($0.id) }.map { ($0.id, $0) })
        var merged = server.map { keep[$0.id] ?? $0 }
        // An unsaved item the server doesn't know yet stays too.
        let serverIDs = Set(server.map(\.id))
        merged += keep.values.filter { !serverIDs.contains($0.id) }
        return merged
    }
}

/// Reads a due date out of what the user types, e.g. "Send invoice tomorrow at 10" → ("Send invoice", tomorrow 10:00).
public enum TaskInput {
    public static func parse(_ text: String, now: Date = .now) -> (title: String, due: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let date = match.date, let range = Range(match.range, in: trimmed),
              date >= now.addingTimeInterval(-60) else {
            return (trimmed, nil) // no date, or a past one ("notes from monday"): leave the text alone
        }
        var title = trimmed
        title.removeSubrange(range)
        // Drop a dangling "at" / "on" / "by" / "due" left where the date was.
        var words = title.split(separator: " ").map(String.init)
        while let last = words.last, ["at", "on", "by", "due"].contains(last.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        // A phrase that is only a date ("tomorrow") keeps the text as the title.
        return (title.isEmpty ? trimmed : title, date)
    }
}
