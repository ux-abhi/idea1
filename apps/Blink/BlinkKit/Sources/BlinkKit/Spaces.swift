// © Pexilim
import Foundation

/// A Space (ARCHITECTURE §35, "segment" on the server): a project with a goal, its tasks and notes.
public struct Space: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable { case active, paused, done, archived }

    public let id: String
    public var title: String
    public var goal: String
    public var status: Status
    public var dueAt: Date?
    /// An Apple system colour by name, one of `colors`.
    public var color: String
    public var icon: String
    /// A named gradient for the header, one of `covers`.
    public var cover: String
    /// The board's columns, left to right; the last one means done.
    public var columns: [String]

    public static let colors = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal", "indigo"]
    public static let covers = ["aurora", "ocean", "sunset", "forest", "dusk", "rose", "mono"]
    public static let defaultColumns = ["To do", "Doing", "Done"]

    enum CodingKeys: String, CodingKey {
        case id, title, goal, status, color, icon, cover, columns
        case dueAt = "due_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .active
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "folder"
        // A server from before covers and boards: the defaults.
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? "aurora"
        columns = try c.decodeIfPresent([String].self, forKey: .columns) ?? Self.defaultColumns
    }

    public init(id: String = UUID().uuidString.lowercased(), title: String, goal: String = "", status: Status = .active,
                dueAt: Date? = nil, color: String = "blue", icon: String = "folder", cover: String = "aurora",
                columns: [String] = Space.defaultColumns) {
        self.cover = cover
        self.columns = columns
        self.id = id
        self.title = title
        self.goal = goal
        self.status = status
        self.dueAt = dueAt
        self.color = color
        self.icon = icon
    }

    // Send due_at as null when cleared, rather than leaving the old date.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(goal, forKey: .goal)
        try c.encode(status, forKey: .status)
        try c.encode(dueAt, forKey: .dueAt)
        try c.encode(color, forKey: .color)
        try c.encode(icon, forKey: .icon)
        try c.encode(cover, forKey: .cover)
        try c.encode(columns, forKey: .columns)
    }

    /// Tasks done out of all tasks in the space, for its progress ring.
    public static func progress(of items: [BlinkItem], in spaceID: String) -> (done: Int, total: Int) {
        let tasks = items.filter { $0.type == .task && $0.spaceID == spaceID && $0.status != .archived }
        return (tasks.filter { $0.status == .done }.count, tasks.count)
    }
}
