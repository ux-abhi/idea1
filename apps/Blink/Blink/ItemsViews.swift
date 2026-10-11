// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

// MARK: Tasks

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var newTitle = ""
    @State private var newHabit = ""
    @State private var showDone = false

    var body: some View {
        let habitsToday = model.habits.filter { model.isScheduledToday($0) }
        let doneToday = habitsToday.filter { model.answerToday($0) == .done }.count
        DashPage("Tasks & Habits", summary: "\(model.openTasks.count) open · \(habitsToday.isEmpty ? "no habits today" : "\(doneToday) of \(habitsToday.count) habits done")") {
            DashCard("Habits") {
                if !model.habits.isEmpty {
                    CardRows(items: model.habits) { HabitRow(habit: $0) }
                    Divider()
                }
                AddField(placeholder: "Add a habit, e.g. \"Read 20 pages\"", text: $newHabit) {
                    let name = newHabit.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    newHabit = ""
                    Task { await model.addHabit(name) }
                }
                Text("Skips and rest days never break a streak, and one missed day a week is forgiven.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            DashCard("Tasks") {
                AddField(placeholder: "Add a task, e.g. \"Send invoice tomorrow at 10\"", text: $newTitle, action: add)
                // Shows what Blink understood before Return.
                if let due = TaskInput.parse(newTitle).due {
                    Label("Due \(due.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.openTasks.isEmpty {
                    Text("No open tasks. Type above and press Return.").foregroundStyle(.secondary)
                } else {
                    Divider()
                    CardRows(items: model.openTasks) { TaskRow(task: $0) }
                }
            }

            if !model.agenda.reminders.isEmpty {
                DashCard("Apple Reminders due today") {
                    CardRows(items: model.agenda.reminders) { ReminderRow(reminder: $0) }
                }
            }

            if !model.doneTasks.isEmpty {
                DashCard {
                    DisclosureGroup(isExpanded: $showDone) {
                        CardRows(items: model.doneTasks) { TaskRow(task: $0) }.padding(.top, 8)
                    } label: {
                        Text("Done (\(model.doneTasks.count))").font(.headline)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
        .task {
            await model.loadItems()
            await model.loadHabits()
        }
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
            DueMenu(due: task.dueAt, highlight: task.isDue(by: .now)) { date in
                var changed = task
                changed.dueAt = date
                model.edit(changed)
                Task { await model.save(task.id) }
            }
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
    let due: Date?
    let highlight: Bool
    let onSet: (Date?) -> Void
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            if let due {
                Text(due, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .foregroundStyle(highlight ? .orange : .secondary)
            } else {
                Image(systemName: "calendar.badge.plus").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(due == nil ? "Add due date" : "Change due date")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                quick("This evening", "moon", Self.at(hour: 18, daysFromToday: 0))
                quick("Tomorrow morning", "sunrise", Self.at(hour: 9, daysFromToday: 1))
                quick("Next Monday", "calendar", Self.nextMonday())
                Divider().padding(.vertical, 4)
                DatePicker("Custom", selection: Binding(
                    get: { due ?? Self.at(hour: 18, daysFromToday: 0) },
                    set: { set($0, close: false) }
                ), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                if due != nil {
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

    private func set(_ date: Date?, close: Bool = true) {
        onSet(date)
        if close { showing = false }
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

/// One habit: the last 7 days, the streak, and today's Done / Not today / Skip (§36.2: neutral, no guilt).
struct HabitRow: View {
    @Environment(AppModel.self) private var model
    let habit: Habit

    var body: some View {
        let progress = model.progress(habit)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                HStack(spacing: 6) {
                    LastSevenDays(habit: habit)
                    Text(summary(progress)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.isScheduledToday(habit) {
                Text("Rest day").font(.caption).foregroundStyle(.secondary)
            } else if let answer = model.answerToday(habit) {
                Menu {
                    Button("Done") { Task { await model.answer(habit, .done) } }
                    Button("Not today") { Task { await model.answer(habit, .notToday) } }
                    Button("Skip") { Task { await model.answer(habit, .skipped) } }
                    Divider()
                    Button("Clear") { Task { await model.answer(habit, nil) } }
                } label: {
                    Label(word(answer), systemImage: symbol(answer))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                HStack(spacing: 6) {
                    Button("Done") { Task { await model.answer(habit, .done) } }
                        .buttonStyle(.borderedProminent)
                    Button("Not today") { Task { await model.answer(habit, .notToday) } }
                    Button("Skip") { Task { await model.answer(habit, .skipped) } }
                }
                .controlSize(.small)
            }
        }
        .contextMenu {
            Button("Every Day") { Task { await model.setWeekdays(habit, to: Array(1...7)) } }
            Button("Weekdays") { Task { await model.setWeekdays(habit, to: [2, 3, 4, 5, 6]) } }
            Button("Weekends") { Task { await model.setWeekdays(habit, to: [1, 7]) } }
            Divider()
            Button("Remove Habit", role: .destructive) { Task { await model.archive(habit) } }
        }
    }

    private func summary(_ p: HabitProgress) -> String {
        let run = p.streak == 1 ? "1 day" : "\(p.streak) days"
        return p.of == 0 ? run : "\(run) · kept \(p.kept) of \(p.of)"
    }

    private func word(_ a: HabitAnswer) -> String {
        switch a { case .done: "Done"; case .notToday: "Not today"; case .skipped: "Skipped" }
    }

    private func symbol(_ a: HabitAnswer) -> String {
        switch a { case .done: "checkmark.circle.fill"; case .notToday: "circle.dashed"; case .skipped: "forward.end" }
    }
}

/// Seven small marks, oldest first: done, skipped, not done (neutral dashed), rest day, today still open.
struct LastSevenDays: View {
    @Environment(AppModel.self) private var model
    let habit: Habit

    var body: some View {
        let cal = Calendar.current
        HStack(spacing: 2) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: -offset, to: model.habitToday) ?? model.habitToday
                let answer = model.habitAnswers[habit.id]?[HabitDay.key(day)]
                let scheduled = habit.weekdays.contains(cal.component(.weekday, from: day))
                Image(systemName: mark(answer: answer, scheduled: scheduled, isToday: offset == 0))
                    .foregroundStyle(answer == .done ? .green : .secondary)
                    .font(.caption2)
            }
        }
        .accessibilityHidden(true) // the summary text says the same in words
    }

    private func mark(answer: HabitAnswer?, scheduled: Bool, isToday: Bool) -> String {
        switch answer {
        case .done: "checkmark.circle.fill"
        case .skipped: "forward.end"
        case .notToday: "circle.dashed"
        case nil: !scheduled ? "minus" : (isToday ? "circle" : "circle.dashed")
        }
    }
}

/// An Apple Reminder, editable in place: tick off, rename, change the due date.
struct ReminderRow: View {
    @Environment(AppModel.self) private var model
    let reminder: AgendaReminder
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.complete(reminder) }
            } label: {
                Image(systemName: "circle").foregroundStyle(.secondary).imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark as done")

            TextField("Reminder", text: $title)
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = title.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, trimmed != reminder.title else { return }
                    Task { await model.rename(reminder, to: trimmed) }
                }
            Spacer()
            DueMenu(due: reminder.due, highlight: (reminder.due ?? .distantFuture) < .now) { date in
                Task { await model.setDue(reminder, to: date) }
            }
        }
        .onAppear { title = reminder.title }
        .onChange(of: reminder.title) { title = reminder.title }
        .help("From Apple Reminders")
    }
}

// MARK: Notes

struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    Text(model.notes.count == 1 ? "1 note" : "\(model.notes.count) notes").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.notes) { note in
                            Button { selection = note.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.title.isEmpty ? "New note" : note.title).font(.headline).lineLimit(1)
                                    Text(note.body.isEmpty ? note.updatedAt.formatted(.relative(presentation: .named)) : note.body)
                                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(selection == note.id ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.background),
                                            in: .rect(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(selection == note.id ? Color.accentColor : .clear, lineWidth: 1.5))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) { Task { await model.delete(note) } }
                            }
                        }
                    }
                }
            }
            .frame(width: 260)

            Group {
                if let id = selection, let note = model.notes.first(where: { $0.id == id }) {
                    NoteEditor(note: note).id(note.id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.secondary)
                        Text(model.notes.isEmpty ? "No notes yet" : "Pick a note").font(.headline)
                        Text("Notes you write here are kept on your server and searchable later, for example meeting notes or an idea.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                        Button("New Note", action: newNote).buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
        }
        .padding(20)
        .background(BlinkCanvas())
        .navigationTitle("Notes")
        .onAppear {
            if let id = model.focusNoteID {
                selection = id
                model.focusNoteID = nil
            }
        }
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
    /// Improve: a preview the owner accepts or cancels; Undo puts the previous text back.
    @State private var working: BlinkServer.TextTask?
    @State private var preview: (task: BlinkServer.TextTask, text: String)?
    @State private var undoText: String?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                Spacer()
                if let undoText {
                    Button("Undo") {
                        text = undoText
                        self.undoText = nil
                    }
                }
                if working != nil {
                    ProgressView().controlSize(.small)
                }
                Menu {
                    ForEach(BlinkServer.TextTask.allCases, id: \.self) { task in
                        Button(task.title) { improve(task) }
                    }
                } label: {
                    Label("Improve", systemImage: "wand.and.stars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(working != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Fix, shorten, clarify or summarise this note")
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
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
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview { previewSheet(preview.task, preview.text) }
        }
    }

    private func previewSheet(_ task: BlinkServer.TextTask, _ result: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(task.title).font(.headline)
            ScrollView {
                Text(result)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
            HStack {
                Button("Cancel", role: .cancel) { preview = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if task == .summarize {
                    Button("Add Below") { accept(text + "\n\nSummary\n" + result) }
                }
                Button("Replace") { accept(result) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func improve(_ task: BlinkServer.TextTask) {
        guard let server = model.server else { return }
        working = task
        problem = nil
        let current = text
        Task {
            defer { working = nil }
            do {
                preview = (task, try await server.edit(current, task: task))
            } catch let error as BlinkServer.ChatProblem {
                problem = error.message
            } catch {
                problem = "Couldn't reach your server. Try again in a moment."
            }
        }
    }

    private func accept(_ new: String) {
        undoText = text
        text = new
        preview = nil
    }

    private func apply() {
        guard title != note.title || text != note.body else { return }
        var changed = note
        changed.title = title
        changed.body = text
        model.edit(changed)
    }
}

/// A plain add field with a round "+" (the Look v3 pill-and-plus).
struct AddField: View {
    let placeholder: String
    @Binding var text: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor).imageScale(.large)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(action)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
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
