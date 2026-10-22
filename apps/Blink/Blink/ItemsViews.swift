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
    /// Select mode: tick several tasks and reminders, then finish or delete them together.
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmDelete = false
    @AppStorage("addAsReminder") private var addAsReminder = false
    @AppStorage("tasks.space") private var spaceFilter = "all"
    /// "all", "tasks" (Blink's own) or "reminders" (Apple Reminders).
    @AppStorage("tasks.kind") private var kindFilter = "all"

    var body: some View {
        let all = openEntries
        let entries = all.filter { entry in
            switch entry.kind {
            case .task: kindFilter != "reminders"
            case .reminder: kindFilter != "tasks"
            }
        }
        let habitsToday = model.habits.filter { model.isScheduledToday($0) }
        let doneToday = habitsToday.filter { model.answerToday($0) == .done }.count
        DashPage("Tasks & Habits", summary: "\(entries.count) open · \(habitsToday.isEmpty ? "no habits today" : "\(doneToday) of \(habitsToday.count) habits done")") {
            HStack(spacing: 6) {
                FilterPill(title: "All", count: all.count, on: kindFilter == "all") { kindFilter = "all" }
                FilterPill(title: "Tasks", count: all.filter { if case .task = $0.kind { true } else { false } }.count,
                           on: kindFilter == "tasks") { kindFilter = "tasks" }
                FilterPill(title: "Reminders", count: all.filter { if case .reminder = $0.kind { true } else { false } }.count,
                           on: kindFilter == "reminders") { kindFilter = "reminders" }
                    .help("From Apple Reminders, on all your devices")
                Spacer()
                SpaceFilter(selected: $spaceFilter)
                    .task(id: spaceFilter) {
                        if let space = model.spaces.first(where: { $0.id == spaceFilter }) { await model.loadReminders(for: space) }
                    }
            }
            DashCard("Tasks", trailing: entries.isEmpty ? nil : (selecting ? "Cancel" : "Select"),
                     action: { selecting.toggle(); selected = [] }) {
                AddField(placeholder: addAsReminder ? "Add a reminder, e.g. “call Sam 4pm”" : "Add a task, e.g. “send invoice friday”",
                         text: $newTitle, action: add)
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 4) {
                            FilterPill(title: "Task", on: !addAsReminder) { addAsReminder = false }
                            FilterPill(title: "Reminder", on: addAsReminder) { addAsReminder = true }
                                .help("Reminders go to Apple Reminders on all your devices")
                        }
                        .padding(.trailing, 8)
                    }
                // Shows what Blink understood before Return.
                if let due = TaskInput.parse(newTitle).due {
                    Label("Due \(due.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if entries.isEmpty {
                    Text("Nothing open.").foregroundStyle(.secondary)
                }
                // Blink tasks and Apple Reminders together, by when they're due, in one card.
                ForEach(DueGroup.allCases, id: \.self) { group in
                    let rows = entries.filter { $0.group == group }
                    if !rows.isEmpty {
                        Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                        CardRows(items: rows) { entry in
                            selectable(entry.id) {
                                switch entry.kind {
                                case .task(let task): TaskRow(task: task)
                                case .reminder(let reminder): ReminderRow(reminder: reminder)
                                }
                            }
                        }
                    }
                }
            }

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
            }
            .help("Skips and rest days never break a streak, and one missed day a week is forgiven.")

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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if selecting { selectionBar }
                SaveProblemBar()
            }
        }
        .confirmationDialog("Delete \(selected.count) item\(selected.count == 1 ? "" : "s")?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let (tasks, reminders) = chosen()
                Task { await model.deleteAll(tasks: tasks, reminders: reminders) }
                selected = []
                selecting = false
            }
        } message: {
            Text("Reminders are removed from Apple Reminders too. This can't be undone from Blink yet.")
        }
        .task {
            await model.loadItems()
            await model.loadHabits()
        }
    }

    /// A tick box in front of a row while selecting.
    private func selectable<Row: View>(_ id: String, @ViewBuilder row: () -> Row) -> some View {
        HStack(spacing: 10) {
            if selecting {
                Button {
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    Image(systemName: selected.contains(id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected.contains(id) ? Color.accentColor : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select")
                .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
            }
            row()
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selected.count) selected").foregroundStyle(.secondary)
            Button("Select All") {
                selected = Set(openEntries.map(\.id))
            }
            Spacer()
            Button("Mark Done") {
                let (tasks, reminders) = chosen()
                Task { await model.completeAll(tasks: tasks, reminders: reminders) }
                selected = []
                selecting = false
            }
            .disabled(selected.isEmpty)
            Button("Delete…", role: .destructive) { confirmDelete = true }
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func chosen() -> ([BlinkItem], [AgendaReminder]) {
        (model.openTasks.filter { selected.contains($0.id) }, model.allReminders.filter { selected.contains($0.id) })
    }

    /// One row on the Tasks page: a Blink task or an Apple Reminder.
    private struct Entry: Identifiable {
        enum Kind { case task(BlinkItem), reminder(AgendaReminder) }
        let kind: Kind
        let id: String
        let due: Date?
        let group: DueGroup
    }

    private var openEntries: [Entry] {
        let now = Date.now
        // One Space: its tasks and the reminders in its own Reminders list.
        let space = model.spaces.first { $0.id == spaceFilter }
        let tasks = model.openTasks.filter { space == nil || $0.spaceID == space?.id }
            .map { Entry(kind: .task($0), id: $0.id, due: $0.dueAt, group: DueGroup.of($0.dueAt, now: now)) }
        let reminders = (space.map { model.spaceReminders[$0.id] ?? [] } ?? model.allReminders).map {
            Entry(kind: .reminder($0), id: $0.id, due: $0.due, group: DueGroup.of($0.due, now: now))
        }
        return (tasks + reminders).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    private func add() {
        let parsed = TaskInput.parse(newTitle)
        guard !parsed.title.isEmpty else { return }
        // With a Space picked above, what's added belongs to it (a reminder goes to its Reminders list).
        let space = model.spaces.first { $0.id == spaceFilter }
        if addAsReminder {
            if let space { Task { await model.addReminder(parsed.title, due: parsed.due, to: space) } }
            else { Task { await model.run(.remind(title: parsed.title, due: parsed.due)) } }
        } else {
            model.create(.task, title: parsed.title, due: parsed.due, space: space?.id)
        }
        newTitle = ""
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: BlinkItem
    /// Off inside a Space's own page, where the chip would only repeat its name.
    var showsSpace = true
    @State private var title = ""
    @FocusState private var editing: Bool

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
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, now in if !now { commit() } } // clicking away saves too

            Spacer()
            Tag(text: "Task", tint: .blue)
            if showsSpace, let space = model.spaces.first(where: { $0.id == task.spaceID }) {
                SpaceChip(space: space)
            }
            DueMenu(due: task.dueAt, highlight: task.isDue(by: .now)) { date in
                var changed = task
                changed.dueAt = date
                model.edit(changed)
                Task { await model.save(task.id) }
            }
        }
        .onAppear { title = task.title }
        // A title synced from elsewhere replaces the field only if you haven't changed it.
        .onChange(of: task.title) { old, new in if title == old { title = new } }
        .contextMenu {
            MoveToSpaceMenu(item: task)
            Button("Delete", role: .destructive) { Task { await model.deleteWithUndo(task) } }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { title = task.title; return }
        guard trimmed != task.title else { return }
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
                Text(Agenda.dueLabel(due))
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
                    Button("Not Today") { Task { await model.answer(habit, .notToday) } }
                        .help("Missed it today. No guilt, the streak just pauses.")
                    Button("Skip") { Task { await model.answer(habit, .skipped) } }
                        .help("A planned rest day. It doesn't count against you.")
                    Divider()
                    Button("Reset Today") { Task { await model.answer(habit, nil) } }
                } label: {
                    Label(word(answer), systemImage: symbol(answer))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Menu {
                    Button("Not Today") { Task { await model.answer(habit, .notToday) } }
                    Button("Skip (Rest Day)") { Task { await model.answer(habit, .skipped) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Not today pauses the streak; a skip is a planned rest day")
                Button { Task { await model.answer(habit, .done) } } label: {
                    Image(systemName: "circle").imageScale(.large).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(habit.name) done today")
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
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.complete(reminder) }
            } label: {
                Image(systemName: "circle").foregroundStyle(.orange).imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark as done")

            TextField("Reminder", text: $title)
                .textFieldStyle(.plain)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, now in if !now { commit() } } // clicking away saves too
            Spacer()
            Tag(text: "Reminder", tint: .orange, symbol: "bell.fill")
            DueMenu(due: reminder.due, highlight: (reminder.due ?? .distantFuture) < .now) { date in
                Task { await model.setDue(reminder, to: date) }
            }
        }
        .onAppear { title = reminder.title }
        .onChange(of: reminder.title) { old, new in if title == old { title = new } }
        .help("From Apple Reminders")
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { title = reminder.title; return }
        guard trimmed != reminder.title else { return }
        Task { await model.rename(reminder, to: trimmed) }
    }
}

// MARK: Notes

/// Notes as a board of cards, like paper on a desk: each card shows where it lives (its Space, or when it was edited),
/// its title big, and the start of its text. A click opens the note full width, with a back button; an empty note is
/// thrown away on the way back, so blank notes never pile up.
struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var query = ""
    @AppStorage("notes.space") private var spaceFilter = "all"

    var body: some View {
        Group {
            if let id = selection, let note = model.notes.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    HStack {
                        Button { close() } label: { Label("Notes", systemImage: "chevron.left") }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("[", modifiers: .command)
                            .help("Back to all notes (⌘[)")
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                    NoteEditor(note: note).id(note.id)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                }
                .onExitCommand(perform: close)
            } else {
                board
            }
        }
        .background(BlinkCanvas())
        // On the page, not the board: a toolbar item that comes and goes while a note opens crashes AppKit's toolbar.
        .searchable(text: $query, placement: .toolbar, prompt: "Search notes")
        .onChange(of: query) { if !query.isEmpty { close() } } // searching shows the board
        .onAppear {
            if let id = model.focusNoteID {
                selection = id
                model.focusNoteID = nil
            }
        }
        .toolbar {
            Button(action: newNote) { Label("New Note", systemImage: "square.and.pencil") }
                .keyboardShortcut("n")
                .help("New note (⌘N)")
        }
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
        .task { await model.loadItems() }
        .onChange(of: selection, initial: true) { model.openNoteID = selection }
        .onDisappear {
            model.openNoteID = nil
            discardIfEmpty(selection)
        }
    }

    private var shown: [BlinkItem] {
        model.notes.filter { (spaceFilter == "all" || $0.spaceID == spaceFilter)
                             && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)) }
    }

    private var board: some View {
        let shown = shown
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes").font(.system(.largeTitle, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                        Text(shown.count == 1 ? "1 note" : "\(shown.count) notes").foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpaceFilter(selected: $spaceFilter)
                }
                if shown.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)], alignment: .leading, spacing: 16) {
                        NewNoteCard(action: newNote)
                        ForEach(shown) { note in
                            NoteCard(note: note, space: model.spaces.first { $0.id == note.spaceID }) { selection = note.id }
                                .contextMenu {
                                    Button("Open") { selection = note.id }
                                    MoveToSpaceMenu(item: note)
                                    Divider()
                                    Button("Delete", role: .destructive) { Task { await model.deleteWithUndo(note) } }
                                }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func newNote() {
        discardIfEmpty(selection)
        selection = model.create(.note, title: "", space: spaceFilter == "all" ? nil : spaceFilter).id
    }

    private func close() {
        discardIfEmpty(selection)
        selection = nil
    }

    /// A note left with no title and no text is removed without asking: nothing is lost.
    private func discardIfEmpty(_ id: String?) {
        guard let id, let note = model.notes.first(where: { $0.id == id }), note.isBlank else { return }
        Task { await model.delete(note) }
    }
}

/// One note on the board: where it lives, its title big, the start of its text.
private struct NoteCard: View {
    let note: BlinkItem
    let space: Space?
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let space {
                        Circle().fill(Color.system(space.color)).frame(width: 7, height: 7)
                        Text(space.title)
                    } else {
                        Text(note.updatedAt.formatted(.relative(presentation: .named)))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: Tokens.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(hovering ? 0.18 : 0.07)))
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
            .contentShape(.rect(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(note.title.isEmpty ? "Untitled note" : note.title)
        .accessibilityHint("Opens the note")
    }
}

/// The first card on the board: a dashed outline that makes a new note.
private struct NewNoteCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus").font(.title2.weight(.semibold))
                Text("New Note").font(.callout.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(.rect(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
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
                TextField("Title", text: $title, axis: .vertical)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
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
        // Leaving (Back, ⌘N, another page) cancels the pending save below, so send the last words now.
        .onDisappear { Task { await model.saveIfNeeded(note.id) } }
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
