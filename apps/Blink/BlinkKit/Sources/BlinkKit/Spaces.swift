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

    public static let colors = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal", "indigo"]

    enum CodingKeys: String, CodingKey {
        case id, title, goal, status, color, icon
        case dueAt = "due_at"
    }

    public init(id: String = UUID().uuidString.lowercased(), title: String, goal: String = "", status: Status = .active,
                dueAt: Date? = nil, color: String = "blue", icon: String = "folder") {
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
    }

    /// Tasks done out of all tasks in the space, for its progress ring.
    public static func progress(of items: [BlinkItem], in spaceID: String) -> (done: Int, total: Int) {
        let tasks = items.filter { $0.type == .task && $0.spaceID == spaceID && $0.status != .archived }
        return (tasks.filter { $0.status == .done }.count, tasks.count)
    }
}
