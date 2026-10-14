// © Pexilim
import Foundation

/// Typed actions in the notch ("/task Pay rent friday 9am"): done at once on this device, no AI involved.
public enum QuickCommand: Equatable, Sendable {
    case task(title: String, due: Date?)
    case remind(title: String, due: Date?)
    case note(String)
    case timer(minutes: Double)
    case focus
    /// Drafts for the owner's usual platforms, saved to Content.
    case post(idea: String)
    /// Ideas for the owner's page, optionally around a theme.
    case ideas(theme: String)
    /// Spending in the owner's words ("8.50 lunch, 3 bus"); the AI sorts it into categories.
    case spent(String)
    /// Clears the conversation on this Mac (cards waiting for approval stay).
    case clear
    /// Opens the Google Meet invite card, filled with whatever was typed ("/meet Review sam@x.com fri 3pm").
    case meet(title: String, start: Date?, guests: [String])

    /// Every command with an example, for the hint list.
    public static let all: [(name: String, example: String, about: String)] = [
        ("/task", "/task Send invoice friday 10am", "Add a task, with a date if you give one"),
        ("/remind", "/remind Call Sam tomorrow 4pm", "Add an Apple Reminder"),
        ("/note", "/note Idea for the website header", "Start a note"),
        ("/timer", "/timer 10", "Timer in minutes"),
        ("/focus", "/focus", "25-minute focus round"),
        ("/post", "/post 3 checkout mistakes that lose users", "Write drafts for your platforms"),
        ("/ideas", "/ideas video ideas for my page", "Post ideas for your page"),
        ("/spent", "/spent 8.50 lunch, 3 bus", "Add what you spent; Blink sorts it"),
        ("/meet", "/meet Design review sam@example.com tomorrow 3pm", "Set up a Google Meet and invite people"),
        ("/clear", "/clear", "Clear this chat"),
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
        case "/post":
            return rest.isEmpty ? nil : .post(idea: rest)
        case "/ideas":
            return .ideas(theme: rest)
        case "/spent":
            return rest.contains(where: \.isNumber) ? .spent(rest) : nil
        case "/clear":
            return .clear
        case "/meet":
            // Emails are guests; a date is the start; what's left is the title.
            let guests = rest.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>;")) }
                .filter(isEmail)
            let words = rest.split(separator: " ").filter { word in !guests.contains { word.contains($0) } }
            let parsed = TaskInput.parse(words.joined(separator: " "), now: now)
            var title = parsed.title
            while let joiner = [" with", " and"].first(where: { title.lowercased().hasSuffix($0) }) { title = String(title.dropLast(joiner.count)) }
            return .meet(title: title.trimmingCharacters(in: .whitespaces), start: parsed.due, guests: guests.map { $0.lowercased() })
        default:
            return nil
        }
    }

    /// An address Google will take as a guest. Same rule as the server's (functions/google/input.ts EMAIL).
    public static func isEmail(_ text: String) -> Bool {
        text.wholeMatch(of: /[^\s@<>,;"]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}/) != nil
    }

    /// Commands that start with what's typed so far ("/re" → /remind), while the name isn't finished.
    public static func suggestions(for text: String) -> [(name: String, example: String, about: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("/"), !trimmed.contains(" ") else { return [] }
        return all.filter { $0.name.hasPrefix(trimmed) }
    }
}
