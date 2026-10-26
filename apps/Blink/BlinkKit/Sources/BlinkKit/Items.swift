// © Pexilim
import Foundation

/// A note or task from the `item` table (ARCHITECTURE §16).
public struct BlinkItem: Codable, Identifiable, Equatable, Sendable {
    /// Nothing written: no title and no text, spaces and new lines aside.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
    /// Its column on the Space's board (nil: the first column, or the last when done).
    public var stage: String?
    /// When work on it starts, for the Space's timeline.
    public var startAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, status, stage
        case dueAt = "due_at", updatedAt = "updated_at", spaceID = "segment_id", startAt = "start_at"
    }

    public init(id: String, type: Kind, title: String, body: String = "", status: Status = .open,
                dueAt: Date? = nil, updatedAt: Date = .now, spaceID: String? = nil, stage: String? = nil, startAt: Date? = nil) {
        self.spaceID = spaceID
        self.stage = stage
        self.startAt = startAt
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
        let keep = Dictionary(local.filter { unsaved.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = server.map { keep[$0.id] ?? $0 }
        // An unsaved item the server doesn't know yet stays too.
        let serverIDs = Set(server.map(\.id))
        merged += keep.values.filter { !serverIDs.contains($0.id) }
        return merged
    }
}

/// Text another app sends through the Services menu, split into a note: the first line is the title (up to 120
/// characters); the body keeps all of the text when the title had to be cut, so nothing is lost. `trimmed` says the
/// body hit its 20,000-character cap.
public enum ServiceNote {
    public static func split(_ text: String) -> (title: String, body: String, trimmed: Bool) {
        let lines = text.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let first = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        let title = String(first.prefix(120))
        let body = title.count < first.count ? text : (lines.count > 1 ? String(lines[1]) : "")
        return (title, String(body.prefix(20_000)), body.count > 20_000)
    }
}

/// Reads a due date out of what the user types, e.g. "Send invoice tomorrow at 10" → ("Send invoice", tomorrow 10:00).
public enum TaskInput {
    /// When, from words alone ("tomorrow 4pm", "in 10 minutes", "in 2 hours"). Nil when they hold no time still ahead.
    public static func when(_ words: String, now: Date = .now) -> Date? {
        let w = words.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = w.wholeMatch(of: /in (\d{1,3}) ?(min|mins|minute|minutes|h|hr|hrs|hour|hours)/), let n = Double(m.1) {
            return now.addingTimeInterval(n * (m.2.hasPrefix("h") ? 3600 : 60))
        }
        return parse("x " + w, now: now).due
    }

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
