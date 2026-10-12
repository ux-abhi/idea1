// © Pexilim
import Foundation

/// Typed actions in the notch ("/task Pay rent friday 9am"): done at once on this device, no AI involved.
public enum QuickCommand: Equatable, Sendable {
    case task(title: String, due: Date?)
    case remind(title: String, due: Date?)
    case note(String)
    case timer(minutes: Double)
    case focus

    /// Every command with an example, for the hint list.
    public static let all: [(name: String, example: String, about: String)] = [
        ("/task", "/task Send invoice friday 10am", "Add a task, with a date if you give one"),
        ("/remind", "/remind Call Sam tomorrow 4pm", "Add an Apple Reminder"),
        ("/note", "/note Idea for the website header", "Start a note"),
        ("/timer", "/timer 10", "Timer in minutes"),
        ("/focus", "/focus", "25-minute focus round"),
    ]

    /// The command for a finished line, or nil if it isn't one yet (still typing the name, or nothing after it).
    public static func parse(_ text: String, now: Date = .now) -> QuickCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let name = trimmed.prefix { !$0.isWhitespace }.lowercased()
        let rest = trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        switch name {
        case "/task", "/remind":
            guard !rest.isEmpty else { return nil }
            let parsed = TaskInput.parse(rest, now: now)
            guard !parsed.title.isEmpty else { return nil }
            return name == "/task" ? .task(title: parsed.title, due: parsed.due) : .remind(title: parsed.title, due: parsed.due)
        case "/note":
            return rest.isEmpty ? nil : .note(rest)
        case "/timer":
            // "10", "10m", "10 min", "1.5h"
            let lower = rest.lowercased()
            let hours = lower.hasSuffix("h") || lower.hasSuffix("hour") || lower.hasSuffix("hours")
            let number = Double(lower.filter { $0.isNumber || $0 == "." }) ?? 0
            let minutes = hours ? number * 60 : number
            return (1...480).contains(minutes) ? .timer(minutes: minutes) : nil
        case "/focus":
            return .focus
        default:
            return nil
        }
    }

    /// Commands that start with what's typed so far ("/re" → /remind), while the name isn't finished.
    public static func suggestions(for text: String) -> [(name: String, example: String, about: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("/"), !trimmed.contains(" ") else { return [] }
        return all.filter { $0.name.hasPrefix(trimmed) }
    }
}
