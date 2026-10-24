// © Pexilim
import Foundation

/// Every keyboard shortcut in Blink, for Settings and the ⌘/ window. The Swift side of `design/shortcuts.json`, whose
/// copy blinkk.app/shortcuts shows; `ShortcutTests` checks the two are the same.
public enum Shortcuts {
    public struct Item: Equatable, Sendable, Identifiable {
        public let keys: String
        public let what: String
        public var id: String { keys + what }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public let name: String
        public let items: [Item]
        public var id: String { name }
    }

    private static func group(_ name: String, _ items: [(String, String)]) -> Group {
        Group(name: name, items: items.map { Item(keys: $0.0, what: $0.1) })
    }

    public static let all: [Group] = [
        group("Anywhere on your Mac", [
            ("⌃⌥Space", "Ask Blink in the notch"),
            ("⌃⌥V", "Clipboard history"),
            ("⌃⌥K", "Search everything, in the notch"),
        ]),
        group("In the notch", [
            ("Esc", "Close the notch"),
            ("⌘⏎", "Approve the top card (Create & Invite on a meeting card)"),
            ("/", "Type / to see the notch commands (/task, /remind, /note, /timer, /spent, /meet…)"),
            ("Tab", "Finish a /command"),
            ("↑ ↓", "Move through search and clipboard results"),
        ]),
        group("In the window", [
            ("⌘1 – ⌘9", "Go to the pages in sidebar order: Today, Inbox, Calendar, Notes, Tasks, Content (when on), Money, Needs You, Activity"),
            ("⌘L", "Type in the bar at the bottom (not on Space pages)"),
            ("⌘K", "Search notes, tasks, posts and spaces"),
            ("⌘R", "Sync now"),
            ("⌥⌘B", "Show or hide the Blink panel"),
            ("⌃⌘S", "Show or hide the sidebar"),
            ("⌘Z", "Undo the last thing marked done (while Undo shows)"),
            ("⌘/", "This list of shortcuts"),
            ("⌘,", "Settings"),
        ]),
        group("Mail", [("R", "Reply"), ("E or Delete", "Mark done"), ("⌘⏎", "Send the reply you're reviewing")]),
        group("Notes", [("⌘N", "New note"), ("⌘[ or Esc", "Back to all notes")]),
        group("Calendar", [("⌘T", "Today"), ("⌘← ⌘→", "Previous or next week (or day)")]),
        group("Content", [("⌘N", "New post"), ("⌘⏎", "Write the drafts")]),
        group("Space canvas", [
            ("Double-click", "Add a card where you click"),
            ("Double-click a card", "Edit it"),
            ("⏎", "Edit the selected card"),
            ("Delete", "Delete the selected card"),
            ("Esc", "Deselect"),
            ("⌘= ⌘- ⌘0", "Zoom in, zoom out, actual size"),
            ("⇧⌘1", "Fit all cards"),
        ]),
        group("Type instead of clicking", [
            ("remind me to…", "An Apple Reminder, with a time if you give one"),
            ("task …", "A task"),
            ("note …", "A note"),
            ("meeting with …", "A Google Meet invite"),
            ("spent …", "Spending, sorted for you"),
            ("timer 10 · focus", "A timer, or a 25-minute focus round"),
        ]),
    ]
}
