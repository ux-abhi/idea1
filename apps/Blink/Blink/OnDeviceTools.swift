// © Pexilim
import BlinkKit
import Foundation
import FoundationModels

/// What the on-device model may do: the same small things the notch commands do, at once and with Undo (§36.4 green
/// tier). A meeting only opens the /meet card; the invite still needs the owner's check and Touch ID.
enum OnDeviceTools {
    /// `asked` is the owner's own message: tools that could be steered by text on screen check what was really asked.
    static func all(_ app: AppModel, asked: String) -> [any Tool] {
        [AddTask(app: app), AddReminder(app: app), AddNote(app: app), StartTimer(app: app, asked: asked.lowercased()),
         PrepareMeeting(app: app, asked: asked.lowercased())]
    }

    /// The date for some words, or a problem when there are words but no time still ahead in them ("in 10 min" works;
    /// a past "9am" doesn't), so nothing is added with a time that would silently never ring.
    nonisolated static func when(_ words: String) -> (date: Date?, problem: String?) {
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return (nil, nil) }
        if let date = TaskInput.when(w) { return (date, nil) }
        return (nil, "Not added: couldn't read the time “\(w)” as a time still ahead. Ask the owner for a day and clock time.")
    }

    nonisolated static func title(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }
}

struct AddTask: Tool {
    let app: AppModel
    let name = "add_task"
    let description = "Adds a task to the owner's Blink tasks. Use it when the owner asks you to add or remember a to-do."

    @Generable struct Arguments {
        @Guide(description: "The task, short, e.g. 'Send the invoice'") var title: String
        @Guide(description: "When it's due in plain words like 'tomorrow 4pm' or 'friday', or empty for no date") var due: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = OnDeviceTools.title(arguments.title)
        guard !title.isEmpty else { return "No task added: it had no title." }
        let (due, unread) = OnDeviceTools.when(arguments.due)
        if let unread { return unread }
        if let problem = await app.run(.task(title: title, due: due)) { return "Not added: \(problem)" }
        return "Added the task “\(title)”" + (due.map { ", due \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" } ?? "") + "."
    }
}

struct AddReminder: Tool {
    let app: AppModel
    let name = "add_reminder"
    let description = "Adds an Apple Reminder that alerts the owner at a time. Use it for 'remind me to…'."

    @Generable struct Arguments {
        @Guide(description: "What to be reminded of, e.g. 'Call Sam'") var title: String
        @Guide(description: "When, in plain words like 'today 4pm' or 'tomorrow morning', or empty") var due: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = OnDeviceTools.title(arguments.title)
        guard !title.isEmpty else { return "No reminder added: it had no title." }
        let (due, unread) = OnDeviceTools.when(arguments.due)
        if let unread { return unread }
        if let problem = await app.run(.remind(title: title, due: due)) { return "Not added: \(problem)" }
        return "Added the reminder “\(title)”" + (due.map { " for \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" } ?? "") + "."
    }
}

struct AddNote: Tool {
    let app: AppModel
    let name = "add_note"
    let description = "Starts a note in Blink with a title. Use it when the owner wants to jot something down."

    @Generable struct Arguments {
        @Guide(description: "The note's title or first line") var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = OnDeviceTools.title(arguments.title)
        guard !title.isEmpty else { return "No note started: it had no title." }
        await app.run(.note(title))
        return "Started the note “\(title)”."
    }
}

struct StartTimer: Tool {
    let app: AppModel
    let asked: String
    let name = "start_timer"
    let description = "Starts a countdown timer in the notch, or a 25-minute focus round."

    @Generable struct Arguments {
        @Guide(description: "Length in minutes, 1 to 480", .range(1...480)) var minutes: Int
        @Guide(description: "True for a focus round (25 minutes, then a break)") var focus: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        // Only when the owner asked for one, and never silently over a running one.
        guard ["timer", "focus", "minute", "min", "hour", "pomodoro"].contains(where: asked.contains) else {
            return "No timer started: the owner didn't ask for one."
        }
        if let running = await app.timer, !["instead", "replace", "restart", "new"].contains(where: asked.contains) {
            return "Not started: a \(running.label.lowercased()) is already running. Ask the owner if it should replace it."
        }
        if arguments.focus {
            await app.run(.focus)
            return "Started a 25-minute focus round."
        }
        let minutes = min(max(arguments.minutes, 1), 480)
        await app.run(.timer(minutes: Double(minutes)))
        return "Started a \(minutes)-minute timer."
    }
}

struct PrepareMeeting: Tool {
    let app: AppModel
    let asked: String
    let name = "prepare_meeting"
    let description = """
        Opens the Google Meet invite card filled in, for the owner to check and send with Touch ID. Use it when the owner \
        wants to set up or schedule a meeting. Nothing is sent until they approve.
        """

    @Generable struct Arguments {
        @Guide(description: "The meeting's title") var title: String
        @Guide(description: "When, in plain words like 'tomorrow 3pm', or empty") var when: String
        @Guide(description: "Guests' email addresses the owner gave; leave empty if none were given") var guests: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        // Only addresses the owner typed, as whole words: text on screen must never put an outside guest on a real invite
        // (not even "am@gmail.com" hiding inside "sam@gmail.com").
        let typed = Set(asked.split(whereSeparator: { " ,;<>()\n".contains($0) }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".!?:")) })
        let guests = arguments.guests.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { QuickCommand.isEmail($0) && typed.contains($0) }
        await app.run(.meet(title: OnDeviceTools.title(arguments.title), start: OnDeviceTools.when(arguments.when).date, guests: guests))
        return "Opened the invite card. The owner checks it, adds anyone missing, and sends it with Touch ID."
    }
}
