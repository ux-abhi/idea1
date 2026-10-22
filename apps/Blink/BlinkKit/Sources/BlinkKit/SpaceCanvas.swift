// © Pexilim
import Foundation

/// One thing on a Space's canvas: the project itself, or a pointer to a real task, note or Apple Reminder (`ref`),
/// with where it sits and its colour. The node is only a place; the thing it points at lives in Blink as usual.
public struct SpaceNode: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case project, task, note, reminder }
    public let id: String
    public let spaceID: String
    public let kind: Kind
    public let ref: String?
    public var x: Double
    public var y: Double
    public var color: String

    enum CodingKeys: String, CodingKey { case id, kind, ref, x, y, color; case spaceID = "segment_id" }

    public init(id: String = UUID().uuidString.lowercased(), spaceID: String, kind: Kind, ref: String? = nil,
                x: Double, y: Double, color: String = "yellow") {
        (self.id, self.spaceID, self.kind, self.ref, self.x, self.y, self.color) = (id, spaceID, kind, ref, x, y, color)
    }

    /// The size each kind is drawn at, also used to find what a link was dropped on.
    public var size: (width: Double, height: Double) {
        switch kind {
        case .project: (240, 84)
        case .task: (220, 66)
        case .note: (190, 150)
        case .reminder: (220, 60)
        }
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        abs(px - x) <= size.width / 2 && abs(py - y) <= size.height / 2
    }
}

/// A line between two nodes of the same Space.
public struct SpaceEdge: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let spaceID: String
    public let from: String
    public let to: String
    enum CodingKeys: String, CodingKey { case id; case spaceID = "segment_id", from = "from_node", to = "to_node" }

    public init(id: String = UUID().uuidString.lowercased(), spaceID: String, from: String, to: String) {
        (self.id, self.spaceID, self.from, self.to) = (id, spaceID, from, to)
    }
}

public enum CanvasLayout {
    /// Where the next new node goes: on a ring around the project, the first free spot (so new things never stack).
    public static func freeSpot(around center: (x: Double, y: Double), taken: [SpaceNode], radius: Double = 300) -> (x: Double, y: Double) {
        for ring in 1...6 {
            let count = 6 * ring
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let spot = (x: center.x + cos(angle) * radius * Double(ring), y: center.y + sin(angle) * radius * 0.62 * Double(ring))
                if !taken.contains(where: { abs($0.x - spot.x) < 230 && abs($0.y - spot.y) < 150 }) { return spot }
            }
        }
        return (center.x + Double(taken.count) * 30, center.y + 400)
    }
}
