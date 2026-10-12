// © Pexilim
import Foundation

/// One of the owner's own Instagram posts, as the page reader (Apify) last saw it (`social_post`).
public struct PagePost: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case image, video, carousel
        public var title: String {
            switch self {
            case .image: "Photo"
            case .video: "Reel"
            case .carousel: "Carousel"
            }
        }
        public var symbol: String {
            switch self {
            case .image: "photo"
            case .video: "play.rectangle"
            case .carousel: "square.stack"
            }
        }
    }

    public let url: String
    public let kind: Kind
    public let caption: String
    public let likes: Int?
    public let comments: Int?
    public let views: Int?
    public let postedAt: Date?

    public var id: String { url }
    /// Likes plus comments: what the page shows for every post, whatever its format.
    public var engagement: Int { (likes ?? 0) + (comments ?? 0) }

    enum CodingKeys: String, CodingKey { case url, kind, caption, likes, comments, views, postedAt = "posted_at" }

    public init(url: String, kind: Kind, caption: String, likes: Int?, comments: Int?, views: Int?, postedAt: Date?) {
        (self.url, self.kind, self.caption, self.likes, self.comments, self.views, self.postedAt) =
            (url, kind, caption, likes, comments, views, postedAt)
    }
}

/// A connected account on the Content overview (`social_account`). Instagram's posts come through Apify; follower
/// numbers are typed in. `followers` nil means no account there yet.
public struct SocialAccount: Codable, Equatable, Sendable {
    public enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
        case instagram, linkedin, x
        public var id: String { rawValue }
        public var name: String {
            switch self {
            case .instagram: "Instagram"
            case .linkedin: "LinkedIn"
            case .x: "X"
            }
        }
    }

    public var platform: Platform
    public var handle: String
    public var followers: Int?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey { case platform, handle, followers, updatedAt = "updated_at" }

    public init(platform: Platform, handle: String, followers: Int?, updatedAt: Date? = nil) {
        (self.platform, self.handle, self.followers, self.updatedAt) = (platform, handle, followers, updatedAt)
    }
}

/// How the owner's posts perform, from what the page reader saw.
public enum ContentStats {
    public struct Summary: Equatable, Sendable {
        public let posts: Int
        public let averageLikes: Int
        public let averageComments: Int
        /// Reels only: other formats have no view count.
        public let averageReelViews: Int?
        /// Average engagement of these posts against the same number of posts before them: 0.2 = 20% better.
        public let change: Double?
    }

    /// The latest `count` posts (newest first), with the change against the `count` posts before them.
    public static func summary(_ posts: [PagePost], count: Int = 12) -> Summary {
        let sorted = newestFirst(posts)
        let recent = Array(sorted.prefix(count))
        let before = Array(sorted.dropFirst(count).prefix(count))
        let reels = recent.compactMap { $0.kind == .video ? $0.views : nil }
        let now = average(recent.map(\.engagement)), then = average(before.map(\.engagement))
        return Summary(
            posts: recent.count,
            averageLikes: average(recent.compactMap(\.likes)),
            averageComments: average(recent.compactMap(\.comments)),
            averageReelViews: reels.isEmpty ? nil : average(reels),
            change: then > 0 && before.count == count ? Double(now - then) / Double(then) : nil) // like with like only
    }

    /// Average engagement (and reel views) per format, best first; formats never posted are left out.
    public static func byFormat(_ posts: [PagePost]) -> [(kind: PagePost.Kind, posts: Int, engagement: Int, views: Int?)] {
        Dictionary(grouping: posts, by: \.kind).map { kind, list in
            let views = list.compactMap(\.views)
            return (kind: kind, posts: list.count, engagement: average(list.map(\.engagement)), views: views.isEmpty ? nil : average(views))
        }
        .sorted { $0.engagement > $1.engagement }
    }

    /// Average engagement by weekday the post went out (1 = Sunday … 7 = Saturday, as `Calendar` counts), days posted on only.
    public static func byWeekday(_ posts: [PagePost], calendar: Calendar = .current) -> [(weekday: Int, posts: Int, engagement: Int)] {
        Dictionary(grouping: posts.filter { $0.postedAt != nil }) { calendar.component(.weekday, from: $0.postedAt!) }
            .map { (weekday: $0.key, posts: $0.value.count, engagement: average($0.value.map(\.engagement))) }
            .sorted { $0.weekday < $1.weekday }
    }

    /// The strongest posts by engagement.
    public static func top(_ posts: [PagePost], count: Int = 5) -> [PagePost] {
        Array(posts.sorted { $0.engagement > $1.engagement }.prefix(count))
    }

    /// Posts per week for the last `weeks` weeks, oldest first (index 0 = `weeks - 1` weeks ago).
    public static func perWeek(_ posts: [PagePost], weeks: Int = 8, now: Date = .now, calendar: Calendar = .current) -> [Int] {
        var counts = Array(repeating: 0, count: weeks)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        for post in posts {
            guard let at = post.postedAt, let week = calendar.dateInterval(of: .weekOfYear, for: at)?.start,
                  let ago = calendar.dateComponents([.weekOfYear], from: week, to: thisWeek).weekOfYear,
                  (0..<weeks).contains(ago) else { continue }
            counts[weeks - 1 - ago] += 1
        }
        return counts
    }

    public static func newestFirst(_ posts: [PagePost]) -> [PagePost] {
        posts.sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
    }

    static func average(_ values: [Int]) -> Int {
        values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
