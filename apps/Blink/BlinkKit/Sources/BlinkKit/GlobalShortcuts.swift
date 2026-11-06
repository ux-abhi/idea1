// © Pexilim
import Foundation

/// A global shortcut the owner picked: the key, its modifiers (Carbon's bits, which RegisterEventHotKey takes as they
/// are), and the key's name for the screen ("K", "Space").
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var key: String

    public static let command: UInt32 = 0x100, shift: UInt32 = 0x200, option: UInt32 = 0x800, control: UInt32 = 0x1000

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        (self.keyCode, self.modifiers, self.key) = (keyCode, modifiers, key)
    }

    /// "⌃⌥K", in the order macOS menus write them.
    public var label: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
    }

    /// A global shortcut needs ⌃ or ⌥, or ⌘ with ⇧: plain keys would swallow typing, and ⌘ alone would take over every
    /// app's ⌘C, ⌘V and ⌘Q.
    public var isUsable: Bool {
        modifiers & (Self.option | Self.control) != 0 || modifiers & (Self.command | Self.shift) == Self.command | Self.shift
    }
}

/// Pressing fn (🌐) twice quickly, alone: starts dictation; one more press ends it. A press held long, or with another
/// key or modifier in it (fn-arrow, fn-F5), doesn't count, so fn keeps its everyday jobs.
public struct FnTaps: Sendable {
    public enum Tap: Equatable, Sendable { case single, double }

    /// Longest press that still counts as a tap, and longest wait between the two taps, in seconds.
    static let press = 0.35, between = 0.45
    private var downAt: TimeInterval?
    private var lastTap: TimeInterval?
    private var mixed = false

    public init() {}

    /// fn went down (`down`) or up at `time`. Returns a tap when fn comes up from a clean, short press.
    public mutating func fn(down: Bool, at time: TimeInterval) -> Tap? {
        if down {
            (downAt, mixed) = (time, false)
            return nil
        }
        defer { downAt = nil }
        guard let downAt, !mixed, time - downAt <= Self.press else {
            lastTap = nil
            return nil
        }
        if let lastTap, time - lastTap <= Self.between {
            self.lastTap = nil
            return .double
        }
        lastTap = time
        return .single
    }

    /// Another key or modifier while fn is down, or typing between taps: not a double press.
    public mutating func otherKey() {
        mixed = downAt != nil
        lastTap = nil
    }
}

/// What dictation types: the words as said, minus filler sounds ("um", "uh", "äh"), tidied and capitalised.
public enum Dictated {
    private static let fillers =
        try! NSRegularExpression(pattern: #"\b(?:u+m+|u+h+|e+r+m+|ä+h+m*|h+m+)\b[,.]?\s*"#, options: .caseInsensitive)

    public static func clean(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let bare = fillers.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        let words = bare.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = words.first else { return "" }
        return first.uppercased() + words.dropFirst()
    }
}
