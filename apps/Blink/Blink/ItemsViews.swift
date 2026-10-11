// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

// MARK: Tasks

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var newTitle = ""
    @State private var showDone = false

    var body: some View {
        List {
            Section {
                TextField("Add a task, e.g. \"Send invoice tomorrow at 10\"", text: $newTitle)
                    .onSubmit(add)
                    .textFieldStyle(.plain)
                // Shows what Blink understood before Return.
                if let due = TaskInput.parse(newTitle).due {
                    Label("Due \(due.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if model.openTasks.isEmpty {
                    Text("No open tasks. Type above and press Return, for example \"Send invoice to Studio K\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.openTasks) { TaskRow(task: $0) }
            }
            if !model.doneTasks.isEmpty {
                Section(isExpanded: $showDone) {
                    ForEach(model.doneTasks) { TaskRow(task: $0) }
                } header: {
                    Text("Done (\(model.doneTasks.count))")
                }
            }
        }
        .navigationTitle("Tasks")
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
        .task { await model.loadItems() }
    }

    private func add() {
        let parsed = TaskInput.parse(newTitle)
        guard !parsed.title.isEmpty else { return }
        model.create(.task, title: parsed.title, due: parsed.due)
        newTitle = ""
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: BlinkItem
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.toggle(task) }
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? .green : .secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == .done ? "Mark as not done" : "Mark as done")

            TextField("Task", text: $title)
                .textFieldStyle(.plain)
                .strikethrough(task.status == .done)
                .foregroundStyle(task.status == .done ? .secondary : .primary)
                .onSubmit(commit)

            Spacer()
            DueMenu(task: task)
        }
        .onAppear { title = task.title }
        .onChange(of: task.title) { title = task.title }
        .contextMenu {
            Button("Delete", role: .destructive) { Task { await model.delete(task) } }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        var changed = task
        changed.title = trimmed
        model.edit(changed)
        Task { await model.save(task.id) }
    }
}

/// Due date: one-click choices, or one compact date-and-time field like Reminders. Picking applies at once.
struct DueMenu: View {
    @Environment(AppModel.self) private var model
    let task: BlinkItem
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            if let due = task.dueAt {
                Text(due, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .foregroundStyle(task.isDue(by: .now) ? .orange : .secondary)
            } else {
                Image(systemName: "calendar.badge.plus").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.dueAt == nil ? "Add due date" : "Change due date")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                quick("This evening", "moon", Self.at(hour: 18, daysFromToday: 0))
                quick("Tomorrow morning", "sunrise", Self.at(hour: 9, daysFromToday: 1))
                quick("Next Monday", "calendar", Self.nextMonday())
                Divider().padding(.vertical, 4)
                DatePicker("Custom", selection: Binding(
                    get: { task.dueAt ?? Self.at(hour: 18, daysFromToday: 0) },
                    set: { set($0, close: false) }
                ), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                if task.dueAt != nil {
                    Divider().padding(.vertical, 4)
                    Button(role: .destructive) { set(nil) } label: { Label("Remove Due Date", systemImage: "xmark.circle") }
                        .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: 260)
        }
    }

    private func quick(_ title: String, _ symbol: String, _ date: Date) -> some View {
        Button { set(date) } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(date, format: .dateTime.weekday(.abbreviated).hour().minute()).foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    private func set(_ due: Date?, close: Bool = true) {
        var changed = task
        changed.dueAt = due
        model.edit(changed)
        if close { showing = false }
        Task { await model.save(task.id) }
    }

    static func at(hour: Int, daysFromToday: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: daysFromToday, to: cal.startOfDay(for: .now)) ?? .now
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func nextMonday() -> Date {
        let cal = Calendar.current
        let monday = cal.nextDate(after: .now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? .now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
    }
}

// MARK: Notes

struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        HSplitView {
            List(model.notes, selection: $selection) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "New note" : note.title).lineLimit(1)
                    Text(note.body.isEmpty ? note.updatedAt.formatted(.relative(presentation: .named)) : note.body)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(note.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { Task { await model.delete(note) } }
                }
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            Group {
                if let id = selection, let note = model.notes.first(where: { $0.id == id }) {
                    NoteEditor(note: note).id(note.id)
                } else {
                    ContentUnavailableView {
                        Label(model.notes.isEmpty ? "No notes yet" : "Pick a note", systemImage: "note.text")
                    } description: {
                        Text("Notes you write here are kept on your server and searchable later, for example meeting notes or an idea.")
                    } actions: {
                        Button("New Note", action: newNote)
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Notes")
        .toolbar {
            Button(action: newNote) { Label("New Note", systemImage: "square.and.pencil") }
                .keyboardShortcut("n")
        }
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
        .task { await model.loadItems() }
    }

    private func newNote() {
        selection = model.create(.note, title: "").id
    }
}

struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    let note: BlinkItem
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
        }
        .padding(20)
        .onAppear {
            title = note.title
            text = note.body
        }
        .onChange(of: title) { apply() }
        .onChange(of: text) { apply() }
        // Saves after a 1 s pause in typing; a new keystroke cancels the pending save.
        .task(id: "\(title)\u{0}\(text)") {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await model.saveIfNeeded(note.id)
        }
    }

    private func apply() {
        guard title != note.title || text != note.body else { return }
        var changed = note
        changed.title = title
        changed.body = text
        model.edit(changed)
    }
}

struct SaveProblemBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let problem = model.saveProblem {
            Label(problem, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}
#endif
