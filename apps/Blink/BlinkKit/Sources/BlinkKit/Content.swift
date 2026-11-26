// © Pexilim
import Foundation

/// A draft post for one platform, made from an idea (ARCHITECTURE §36.4, `content_piece`).
public struct ContentPiece: Codable, Identifiable, Equatable, Sendable {
    public enum Platform: String, Codable, Sendable, CaseIterable {
        case instagram, linkedin, x
        public var name: String {
            switch self {
            case .instagram: "Instagram"
            case .linkedin: "LinkedIn"
            case .x: "X"
            }
        }
        /// For tight lists: "IG", "in", "X".
        public var short: String {
            switch self {
            case .instagram: "IG"
            case .linkedin: "in"
            case .x: "X"
            }
        }
    }
    /// idea: a planned post not written yet (from the week plan); its `body` holds why it works.
    public enum Status: String, Codable, Sendable { case idea, drafted, approved, published, archived }

    public let id: String
    public let idea: String
    public let platform: Platform
    public let format: String
    public var hook: String
    public var body: String
    public var parts: [String]
    public var hashtags: [String]
    public var status: Status
    public var lintScore: Int?
    public var publishedAt: Date?
    public let createdAt: Date
    /// The day it's planned for in the weekly plan ("2026-10-14"), if any.
    public var plannedFor: String?
    /// The Space it was written for, if any (it then sits on that Space's canvas).
    public var spaceID: String?

    enum CodingKeys: String, CodingKey {
        case id, idea, platform, format, hook, body, parts, hashtags, status
        case lintScore = "lint_score", publishedAt = "published_at", createdAt = "created_at", plannedFor = "planned_for"
        case spaceID = "segment_id"
    }

    /// The columns the app may change, as the server update sends them. Every key is always sent (nil as null), so
    /// clearing a date clears it on the server too; a left-out key would keep the old value.
    struct Update: Encodable {
        let piece: ContentPiece
        enum Keys: String, CodingKey { case hook, body, parts, hashtags, status, lint_score, published_at, planned_for }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(piece.hook, forKey: .hook)
            try c.encode(piece.body, forKey: .body)
            try c.encode(piece.parts, forKey: .parts)
            try c.encode(piece.hashtags, forKey: .hashtags)
            try c.encode(piece.status.rawValue, forKey: .status)
            try c.encode(piece.lintScore, forKey: .lint_score)
            try c.encode(piece.publishedAt, forKey: .published_at)
            try c.encode(piece.plannedFor, forKey: .planned_for)
        }
    }

    /// What gets copied to post: a thread or carousel as numbered parts, then the hashtags.
    public var postText: String {
        let main = parts.isEmpty || format == "carousel" || format == "reel_script" ? body : parts.joined(separator: "\n\n")
        let tags = hashtags.map { "#\($0)" }.joined(separator: " ")
        return tags.isEmpty ? main : "\(main)\n\n\(tags)"
    }

}

/// Who the owner is online and how they write (`voice_profile`): drafts and ideas are made to fit it.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// "@yourname on Instagram: UX tips for junior designers"
    public var page: String
    public var audience: String
    public var topics: String
    /// How they sound.
    public var notes: String
    public var neverSay: [String]
    /// Their creator brief: a content directory (story, projects, pillars, rules), at most 40,000 characters.
    public var brief: String

    public static let briefLimit = 40_000

    enum CodingKeys: String, CodingKey { case page, audience, topics, notes, brief, neverSay = "never_say" }

    public init(page: String = "", audience: String = "", topics: String = "", notes: String = "", neverSay: [String] = [],
                brief: String = "") {
        self.brief = String(brief.prefix(Self.briefLimit))
        self.page = page
        self.audience = audience
        self.topics = topics
        self.notes = notes
        self.neverSay = neverSay
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decodeIfPresent(String.self, forKey: .page) ?? ""
        audience = try c.decodeIfPresent(String.self, forKey: .audience) ?? ""
        topics = try c.decodeIfPresent(String.self, forKey: .topics) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        neverSay = try c.decodeIfPresent([String].self, forKey: .neverSay) ?? []
        brief = try c.decodeIfPresent(String.self, forKey: .brief) ?? ""
    }

    /// Enough for drafts to be specific, rather than generic.
    public var isSetUp: Bool { !page.isEmpty || !topics.isEmpty || !brief.isEmpty }
}

/// Posts move once into a "Content" table in their Space (ADR-0004 §6): one card per post, the post's text in the
/// card's note, its day in Post at. A posted one is Done, so it never shows as overdue.
public enum ContentMove {
    public static let tableName = "Content"
    static let statuses: [(ContentPiece.Status, String)] = [(.idea, "Idea"), (.drafted, "Drafted"), (.approved, "Approved"), (.published, "Done")]

    /// The Content table: Post, Status, Platform, Post at, Media, with a board by Status and a calendar by Post at.
    public static func table() -> SpaceBlock.Data {
        let colors = ["gray", "blue", "orange", "green", "pink", "indigo", "teal"]
        let status = SpaceColumn(name: "Status", kind: .category,
                                 options: statuses.enumerated().map { SpaceOption(name: $0.element.1, color: colors[$0.offset]) })
        let platform = SpaceColumn(name: "Platform", kind: .category,
                                   options: ContentPiece.Platform.allCases.enumerated().map { SpaceOption(name: $0.element.name, color: colors[$0.offset + 4]) })
        let date = SpaceColumn(name: "Post at", kind: .date)
        var data = SpaceBlock.Data(text: tableName, columns: [SpaceColumn(name: "Post"), status, platform, date, SpaceColumn(name: "Media", kind: .file)])
        data.views = [SpaceTableView(name: "Board", kind: .board, groupBy: status.id), SpaceTableView(name: "Calendar", kind: .calendar, groupBy: date.id)]
        return data
    }

    /// One card's cells per post (archived ones stay out), by the table's column ids, with how many posts had their
    /// text cut to fit a card (a row holds 8 KB; the old post keeps the whole text until it's removed).
    public static func cards(_ pieces: [ContentPiece], columns: [SpaceColumn], calendar: Calendar = .current)
        -> (cards: [(pieceID: String, cells: [String: String])], clipped: Int) {
        let column = { (name: String) in columns.first { $0.name == name } }
        var clipped = 0
        let cards = pieces.filter { $0.status != .archived }.map { piece -> (String, [String: String]) in
            var cells: [String: String] = [:]
            let title = (piece.hook.isEmpty ? piece.idea : piece.hook).split(separator: "\n").first.map(String.init) ?? ""
            if let c = column("Post") { cells[c.id] = String(title.trimmingCharacters(in: .whitespaces).prefix(200)) }
            let statusName = statuses.first { $0.0 == piece.status }?.1
            if let c = column("Status"), let id = c.options?.first(where: { $0.name == statusName })?.id { cells[c.id] = id }
            if let c = column("Platform"), let id = c.options?.first(where: { $0.name == piece.platform.name })?.id { cells[c.id] = id }
            if let c = column("Post at") {
                if let day = piece.plannedFor, HabitDay.date(fromKey: day, calendar: calendar) != nil { cells[c.id] = String(day.prefix(10)) }
                else if let at = piece.publishedAt { cells[c.id] = SpaceTable.dateCell(at, timed: true, calendar: calendar) }
            }
            let text = SpaceTable.fitNote(piece.postText, with: cells)
            if text.count < piece.postText.count { clipped += 1 }
            if !text.isEmpty { cells[SpaceTable.noteKey] = text }
            return (piece.id, cells)
        }
        return (cards, clipped)
    }
}
