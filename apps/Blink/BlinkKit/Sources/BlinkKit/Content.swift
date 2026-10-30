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
    public let spaceID: String?

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

/// The writing check before approval (§36.4 "humanize and lint"): AI-sounding phrases, placeholders, platform limits
/// and the owner's never-say words. Blocking problems stop approval; the rest lower the score.
public enum ContentLint {
    public struct Issue: Equatable, Sendable {
        public let message: String
        public let blocks: Bool
    }

    /// Phrases that make a post read machine-written (one list for all platforms for now).
    static let tells = ["delve", "game-changer", "game changer", "unlock", "elevate", "in today's fast-paced", "tapestry",
                        "testament to", "seamless", "leverage", "embark", "realm", "navigate the", "it's not just",
                        "let's dive in", "in conclusion", "revolutionize", "supercharge"]

    public static func check(_ piece: ContentPiece, neverSay: [String] = []) -> (score: Int, issues: [Issue]) {
        var issues: [Issue] = []
        let all = ([piece.hook, piece.body] + piece.parts).joined(separator: "\n")
        let lower = all.lowercased()

        // An unfilled placeholder or template gap would post as-is: never approvable.
        if all.range(of: #"\{\{[^}]*\}\}|\[(insert|your|name|client|number|link)[^\]]*\]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            issues.append(Issue(message: "Has a placeholder to fill in", blocks: true))
        }
        switch piece.platform {
        case .x:
            let posts = piece.parts.isEmpty ? [piece.body] : piece.parts
            if let long = posts.firstIndex(where: { $0.count > 280 }) {
                issues.append(Issue(message: posts.count == 1 ? "Over 280 characters" : "Post \(long + 1) is over 280 characters", blocks: true))
            }
        case .linkedin:
            if piece.body.count > 3000 { issues.append(Issue(message: "Over LinkedIn's 3,000 characters", blocks: true)) }
        case .instagram:
            if piece.body.count > 2200 { issues.append(Issue(message: "Caption over 2,200 characters", blocks: true)) }
            if piece.format == "carousel" && piece.parts.count > 10 { issues.append(Issue(message: "More than 10 slides", blocks: true)) }
        }
        if piece.hashtags.count > 5 { issues.append(Issue(message: "\(piece.hashtags.count) hashtags; 3–5 read better", blocks: false)) }
        for word in neverSay where !word.isEmpty && lower.contains(word.lowercased()) {
            issues.append(Issue(message: "Uses “\(word)”, which you never say", blocks: false))
        }
        for tell in tells where lower.contains(tell) {
            issues.append(Issue(message: "Sounds like AI: “\(tell)”", blocks: false))
        }
        if all.filter({ $0 == "—" }).count > 1 { issues.append(Issue(message: "Several em dashes", blocks: false)) }

        let score = max(0, 100 - issues.reduce(0) { $0 + ($1.blocks ? 40 : 10) })
        return (score, issues)
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

/// A post idea to pick from (not saved until "Write this" turns it into drafts).
public struct ContentIdea: Decodable, Identifiable, Hashable, Sendable {
    public let title: String
    public let hook: String
    public let platform: ContentPiece.Platform
    public let format: String
    public let why: String
    /// For the week plan: the day it's planned for ("2026-10-14").
    public let day: String?
    public var id: String { title + platform.rawValue + (day ?? "") }

    public var formatName: String {
        switch format {
        case "reel_script": "Reel"
        case "carousel": "Carousel"
        case "thread": "Thread"
        default: "Post"
        }
    }
}

public extension HabitDay {
    /// The next `count` days from today as "2026-10-14" keys (the week plan's days, in the owner's time zone).
    public static func nextDays(_ count: Int = 7, from now: Date = .now, calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: today).map { key($0, calendar: calendar) } }
    }

    /// "Tue 14 Oct" for a "2026-10-14" key.
    public static func label(_ key: String, calendar: Calendar = .current) -> String {
        guard let date = date(fromKey: key, calendar: calendar) else { return key }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month())
    }
}

/// What reading the owner's Instagram page found: a suggested voice, what works, and the best recent posts.
public struct PageRead: Decodable, Sendable {
    public struct Analysis: Decodable, Sendable {
        public struct Voice: Decodable, Sendable { public let page, audience, topics, tone: String }
        public let voice: Voice
        public let works: [String]
        public let avoid: [String]
    }
    public struct Best: Decodable, Identifiable, Sendable {
        public let url: String
        public let kind: String
        public let likes: Int?
        public let comments: Int?
        public let views: Int?
        public let caption: String
        public var id: String { url }
    }
    public let handle: String
    public let read: Int
    public let analysis: Analysis?
    public let best: [Best]
}
