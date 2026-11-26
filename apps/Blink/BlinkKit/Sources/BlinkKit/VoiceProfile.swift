// © Pexilim
import Foundation

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
