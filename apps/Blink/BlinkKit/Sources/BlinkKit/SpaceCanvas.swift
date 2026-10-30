// © Pexilim
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One thing on a Space's canvas: the project itself, a pointer to a real task, note or Apple Reminder (`ref`), or an
/// image (`ref` is its file on the server), with where it sits, its colour, and for stickies and images the size and
/// text size the owner gave it. The node is only a place; the thing it points at lives in Blink as usual.
public struct SpaceNode: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case project, task, note, reminder, image }
    public let id: String
    public let spaceID: String
    public let kind: Kind
    public let ref: String?
    public var x: Double
    public var y: Double
    public var color: String
    /// A size set by hand (stickies and images); nil draws the kind's own size.
    public var w: Double?
    public var h: Double?
    /// How much bigger a sticky's text is drawn; nil is 1.
    public var textScale: Double?

    enum CodingKeys: String, CodingKey { case id, kind, ref, x, y, color, w, h; case spaceID = "segment_id", textScale = "text_scale" }

    public init(id: String = UUID().uuidString.lowercased(), spaceID: String, kind: Kind, ref: String? = nil,
                x: Double, y: Double, color: String = "yellow", w: Double? = nil, h: Double? = nil) {
        (self.id, self.spaceID, self.kind, self.ref, self.x, self.y, self.color) = (id, spaceID, kind, ref, x, y, color)
        (self.w, self.h) = (w, h)
    }

    /// The size the node is drawn at, also used to find what a link was dropped on.
    public var size: (width: Double, height: Double) {
        let standard: (width: Double, height: Double) = switch kind {
        case .project: (240, 84)
        case .task: (220, 66)
        case .note: (190, 150)
        case .reminder: (220, 60)
        case .image: (260, 190)
        }
        return (w ?? standard.width, h ?? standard.height)
    }

    public var resizable: Bool { kind == .note || kind == .image }

    /// The sizes a sticky or image can be dragged to (the server allows a little more).
    public static func clamped(width: Double, height: Double) -> (width: Double, height: Double) {
        (min(max(width, 120), 1200), min(max(height, 90), 1200))
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
    /// The sheet the cards sit on; the project starts in its middle.
    public static let size = (width: 4000.0, height: 2600.0)

    /// A spot pulled inside the sheet, far enough from the edge that the whole card stays reachable.
    public static func onSheet(_ spot: (x: Double, y: Double)) -> (x: Double, y: Double) {
        (min(max(spot.x, 140), size.width - 140), min(max(spot.y, 90), size.height - 90))
    }

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

public enum CanvasImage {
    /// A picture made ready for the canvas: at most `maxPixels` on its long side, as JPEG, and with nothing but the
    /// pixels (no location, camera or other metadata leaves the Mac). Nil when the data isn't an image.
    public static func jpeg(from data: Data, maxPixels: Int = 2000) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, image.width, image.height)
    }

    /// The node size for a picture: 280 points on its long side, keeping its shape.
    public static func size(width: Int, height: Int) -> (width: Double, height: Double) {
        let long = Double(max(width, height, 1))
        return SpaceNode.clamped(width: 280 * Double(width) / long, height: 280 * Double(height) / long)
    }
}
