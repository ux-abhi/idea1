// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The glass bar floating at the bottom of every page (the Space canvas has its own): one box that adds what the page
/// is about. Money takes spending (Blink sorts it, you check, you save), Tasks a task or reminder, Notes a new note;
/// everywhere else plain commands work ("remind me to…", "meeting with…") and anything else is a question for Blink.
struct QuickBar: View {
    @Environment(AppModel.self) private var model
    let page: MainWindow.Page
    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("addAsReminder") private var addAsReminder = false
    @AppStorage("tasks.space") private var tasksSpace = "all"
    @AppStorage("notes.space") private var notesSpace = "all"
    @AppStorage("blinkPanel") private var showPanel = true

    private enum Kind { case money, tasks, notes, ask }

    private var kind: Kind {
        switch page {
        case .section(.money): .money
        case .section(.tasks): .tasks
        case .section(.notes): .notes
        default: .ask
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
            if kind == .tasks {
                FilterPill(title: "Task", on: !addAsReminder) { addAsReminder = false }
                FilterPill(title: "Reminder", on: addAsReminder) { addAsReminder = true }
                    .help("Reminders go to Apple Reminders on all your devices")
            }
            if model.sortingSpends || (kind == .ask && model.thinking) {
                ProgressView().controlSize(.small)
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(buttonLabel)
                .help(buttonLabel)
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .onChange(of: page) { text = "" }
    }

    private var symbol: String {
        switch kind {
        case .money: "eurosign.circle"
        case .tasks: addAsReminder ? "bell" : "checkmark.circle"
        case .notes: "square.and.pencil"
        case .ask: "sparkles"
        }
    }

    private var placeholder: String {
        switch kind {
        case .money: "What did you spend? e.g. lunch 8.50, bus 3"
        case .tasks: addAsReminder ? "Add a reminder, e.g. “call Sam 4pm”" : "Add a task, e.g. “send invoice friday”"
        case .notes: "New note: type a title and press Return"
        case .ask: "“Remind me to…”, “meeting with sam@… 3pm”, or ask Blink"
        }
    }

    private var buttonLabel: String {
        switch kind {
        case .money: "Sort spending"
        case .tasks: addAsReminder ? "Add reminder" : "Add task"
        case .notes: "Add note"
        case .ask: "Send"
        }
    }

    private func submit() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        switch kind {
        case .money:
            guard !model.sortingSpends else { return }
            text = ""
            // The drafts show at the top of Money to check before saving.
            Task { model.spendDrafts += await model.sortSpends(typed) }
        case .tasks:
            let parsed = TaskInput.parse(typed)
            guard !parsed.title.isEmpty else { return }
            text = ""
            // With a Space picked on the page, what's added belongs to it (a reminder goes to its Reminders list).
            let space = model.spaces.first { $0.id == tasksSpace }
            if addAsReminder {
                if let space { Task { await model.addReminder(parsed.title, due: parsed.due, to: space) } }
                else { Task { await model.run(.remind(title: parsed.title, due: parsed.due)) } }
            } else {
                model.create(.task, title: parsed.title, due: parsed.due, space: space?.id)
            }
        case .notes:
            text = ""
            let note = model.create(.note, title: typed, space: notesSpace == "all" ? nil : notesSpace)
            Task { await model.save(note.id) }
        case .ask:
            guard !model.thinking else { return }
            text = ""
            if let command = QuickCommand.parse(typed) {
                Task { _ = await model.run(command) }
            } else {
                showPanel = true
                // The server takes at most 2000 characters (functions/chat input.ts).
                Task { await model.ask(String(typed.prefix(1990))) }
            }
        }
    }
}
#endif
