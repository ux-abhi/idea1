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
    }
    public enum Status: String, Codable, Sendable { case drafted, approved, published, archived }

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

    enum CodingKeys: String, CodingKey {
        case id, idea, platform, format, hook, body, parts, hashtags, status
        case lintScore = "lint_score", publishedAt = "published_at", createdAt = "created_at"
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

/// How the owner writes: notes and words they never use (`voice_profile`).
public struct VoiceProfile: Codable, Equatable, Sendable {
    public var notes: String
    public var neverSay: [String]
    enum CodingKeys: String, CodingKey { case notes, neverSay = "never_say" }
    public init(notes: String = "", neverSay: [String] = []) {
        self.notes = notes
        self.neverSay = neverSay
    }
}
