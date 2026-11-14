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
    /// app's ⌘C, ⌘V and ⌘Q. An F-key (F1–F20) works alone: nobody types with it.
    public var isUsable: Bool {
        modifiers & (Self.option | Self.control) != 0 || modifiers & (Self.command | Self.shift) == Self.command | Self.shift
            || (key.count > 1 && key.first == "F" && key.dropFirst().allSatisfy(\.isNumber))
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

/// A voice command's actions, as the server sends them back: open an app, or open a link (in a named browser).
public struct VoiceCommand: Decodable, Sendable {
    public struct Action: Decodable, Sendable, Equatable {
        public let type: String
        public let app: String?
        public let url: String?
    }
    /// What was heard, the actions to take, and the short reply to say.
    public let text: String
    public let actions: [Action]
    public let say: String
}

/// Finds the installed app a spoken name means: "chrome" → "Google Chrome", "figma" → "Figma".
public enum AppMatch {
    private static let aliases = ["chrome": "google chrome", "vs code": "visual studio code", "vscode": "visual studio code",
                                  "settings": "system settings", "whatsapp": "whatsapp", "mail": "mail", "word": "microsoft word",
                                  "excel": "microsoft excel", "powerpoint": "microsoft powerpoint", "teams": "microsoft teams"]

    /// The best of `installed` (names without ".app") for `spoken`: the same name, then one that starts with it, then one
    /// that has it as a whole word. nil when nothing fits, rather than opening the wrong app.
    public static func best(_ spoken: String, among installed: [String]) -> String? {
        var want = spoken.lowercased().replacingOccurrences(of: ".app", with: "").trimmingCharacters(in: .whitespaces)
        want = aliases[want] ?? want
        guard !want.isEmpty else { return nil }
        let names = installed.map { ($0, $0.lowercased()) }
        if let exact = names.first(where: { $0.1 == want }) { return exact.0 }
        if let prefix = names.filter({ $0.1.hasPrefix(want) }).min(by: { $0.1.count < $1.1.count }) { return prefix.0 }
        return names.filter { $0.1.split(separator: " ").contains(Substring(want)) }.min { $0.1.count < $1.1.count }?.0
    }
}

/// What the owner calls their assistant: "Blink" unless renamed in Settings › General. The same rule as the server's:
/// letters, digits and spaces, up to 24 characters.
public enum AssistantName {
    public static let key = "assistant.name"
    public static let standard = "Blink"

    /// The name to save, or nil when it isn't usable (then the field says why and nothing changes).
    public static func checked(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard (1...24).contains(name.count), name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }) else { return nil }
        return name
    }

    /// The current name, for text that isn't a SwiftUI view watching it.
    public static var current: String { UserDefaults.standard.string(forKey: key).flatMap(checked) ?? standard }
}
