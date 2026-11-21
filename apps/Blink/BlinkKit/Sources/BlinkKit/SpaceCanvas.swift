// © Pexilim
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One thing on a Space's canvas: the project itself, a pointer to a real task, note or Apple Reminder (`ref`), or an
/// image (`ref` is its file on the server), with where it sits, its colour, and for stickies and images the size and
/// text size the owner gave it. The node is only a place; the thing it points at lives in Blink as usual.
public struct SpaceNode: Codable, Identifiable, Equatable, Sendable {
    /// `block`: one of the page's tables (ref → the block). `card`: one row of a table (ref → the row, label → its table).
    public enum Kind: String, Codable, Sendable { case project, task, note, reminder, image, post, heading, section, link, block, card }
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
    /// How much bigger a sticky's or heading's text is drawn; nil is 1.
    public var textScale: Double?
    /// A heading's text, a section's title, or a link's title (the only nodes that hold text themselves).
    public var label: String?
    /// A link card's web address.
    public var url: String?

    enum CodingKeys: String, CodingKey { case id, kind, ref, x, y, color, w, h, label, url; case spaceID = "segment_id", textScale = "text_scale" }

    public init(id: String = UUID().uuidString.lowercased(), spaceID: String, kind: Kind, ref: String? = nil,
                x: Double, y: Double, color: String = "yellow", w: Double? = nil, h: Double? = nil, label: String? = nil, url: String? = nil) {
        (self.id, self.spaceID, self.kind, self.ref, self.x, self.y, self.color) = (id, spaceID, kind, ref, x, y, color)
        (self.w, self.h, self.label, self.url) = (w, h, label, url)
    }

    /// A pasted address as a link card's web address: http(s) only (what the server takes), "https://" added when left
    /// out ("blinkk.app"); nil for anything else.
    public static func webAddress(_ typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000, !text.contains(" ") else { return nil }
        let full = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") ? text : "https://" + text
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".") else { return nil }
        return full
    }

    /// The size the node is drawn at, also used to find what a link was dropped on.
    public var size: (width: Double, height: Double) {
        let standard: (width: Double, height: Double) = switch kind {
        case .project: (240, 84)
        case .task: (220, 66)
        case .note: (190, 150)
        case .reminder: (220, 60)
        case .image: (260, 190)
        case .post: (240, 76)
        case .heading: (320, 56 * (textScale ?? 1))
        case .section: (640, 420)
        case .link: (260, 72)
        case .block: (280, 84)
        case .card: (240, 72)
        }
        return (w ?? standard.width, h ?? standard.height)
    }

    /// Everything but the project can be made bigger, so long text can be read on the card itself.
    public var resizable: Bool { kind != .project }

    /// The sizes a sticky or image can be dragged to (the server allows a little more).
    public static func clamped(width: Double, height: Double) -> (width: Double, height: Double) {
        (min(max(width, 120), 1200), min(max(height, 60), 1200))
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        abs(px - x) <= size.width / 2 && abs(py - y) <= size.height / 2
    }

    /// Headings and sections organise the canvas; they aren't linked like cards.
    public var linkable: Bool { kind != .heading && kind != .section }

    /// What moves along when this section is dragged: every other node whose middle sits inside it (a section only
    /// when it fits inside whole).
    public func carried(in nodes: [SpaceNode]) -> [SpaceNode] {
        guard kind == .section else { return [] }
        return nodes.filter { other in
            guard other.id != id else { return false }
            if other.kind == .section {
                return contains(x: other.x - other.size.width / 2, y: other.y - other.size.height / 2)
                    && contains(x: other.x + other.size.width / 2, y: other.y + other.size.height / 2)
            }
            return contains(x: other.x, y: other.y)
        }
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


/// One block on a Space's page (Page mode, ADR-0002): its kind, where it sits, and only how it shows. Tasks, notes and
/// posts a block lists stay where they are, linked to the Space; a page's blocks are what a template would carry.
public struct SpaceBlock: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case heading, text, tasks, content, note, link, image, timer, stopwatch, table, file

        /// What the "/" menu and the side panel offer; `content` is kept only so old pages still open (ADR-0004).
        public static var addable: [Kind] { allCases.filter { $0 != .content } }

        public var title: String {
            switch self {
            case .heading: "Heading"
            case .text: "Text"
            case .tasks: "Task list"
            case .content: "Content board"
            case .note: "Note"
            case .link: "Link"
            case .image: "Picture"
            case .timer: "Timer"
            case .stopwatch: "Stopwatch"
            case .table: "Table"
            case .file: "File"
            }
        }

        public var symbol: String {
            switch self {
            case .heading: "textformat.size"
            case .text: "text.alignleft"
            case .tasks: "checklist"
            case .content: "square.grid.3x2"
            case .note: "note.text"
            case .link: "link"
            case .image: "photo"
            case .timer: "timer"
            case .stopwatch: "stopwatch"
            case .table: "tablecells"
            case .file: "doc.richtext"
            }
        }
    }

    /// How a block shows: only the fields its kind uses.
    public struct Data: Codable, Equatable, Sendable {
        /// A heading's or text block's words; a link's title.
        public var text: String?
        /// A link's web address.
        public var url: String?
        /// The note a note block shows, or a picture's file on the server.
        public var ref: String?
        /// A timer's length.
        public var minutes: Int?
        /// A table's columns (its rows are stored apart, in `space_table_row`).
        public var columns: [SpaceColumn]?
        /// A table's saved views (Table, Board…) and the one showing.
        public var views: [SpaceTableView]?
        public var activeView: String?
        /// A file's text as read on the Mac (the start of a PDF or Word file), so the Space knows what it says.
        public var body: String?
        /// A file's size in bytes and its type.
        public var size: Int?
        public var type: String?
        public init(text: String? = nil, url: String? = nil, ref: String? = nil, minutes: Int? = nil, columns: [SpaceColumn]? = nil) {
            (self.text, self.url, self.ref, self.minutes, self.columns) = (text, url, ref, minutes, columns)
        }
    }

    public let id: String
    public let spaceID: String
    public var position: Double
    public let kind: Kind
    public var data: Data

    enum CodingKeys: String, CodingKey { case id, position, kind, data; case spaceID = "segment_id" }

    public init(id: String = UUID().uuidString.lowercased(), spaceID: String, position: Double, kind: Kind, data: Data = Data()) {
        (self.id, self.spaceID, self.position, self.kind, self.data) = (id, spaceID, position, kind, data)
    }

    /// The position for a block placed between two others (or after the last): halfway, so nothing else moves.
    public static func position(between before: Double?, and after: Double?) -> Double {
        switch (before, after) {
        case let (b?, a?): (b + a) / 2
        case let (b?, nil): b + 1
        case let (nil, a?): a - 1
        case (nil, nil): 1
        }
    }
}
