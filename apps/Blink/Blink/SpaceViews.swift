// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

extension Color {
    /// A Space's colour, stored on the server by its Apple system colour name.
    static func system(_ name: String) -> Color {
        switch name {
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "indigo": .indigo
        default: .blue
        }
    }
}

/// One Space: goal, due date and progress on top, then what's next, its notes, and what's done (§35.2, Project).
struct SpaceView: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @State private var goal = ""
    @State private var newTask = ""
    @State private var showDone = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @AppStorage("space.addAsReminder") private var addAsReminder = false

    var body: some View {
        let mine = model.items.filter { $0.spaceID == space.id }
        let open = mine.filter { $0.type == .task && $0.status == .open }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let done = mine.filter { $0.type == .task && $0.status == .done }
        let notes = mine.filter { $0.type == .note }.sorted { $0.updatedAt > $1.updatedAt }
        let progress = Space.progress(of: model.items, in: space.id)
        DashPage(space.title, summary: summary(open: open.count, progress: progress)) {
            DashCard {
                HStack(alignment: .center, spacing: 16) {
                    ProgressRing(done: progress.done, total: progress.total, tint: Color.system(space.color))
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What's the goal? e.g. \"Launch the website by November\"", text: $goal, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .onSubmit(saveGoal)
                        HStack(spacing: 12) {
                            DueMenu(due: space.dueAt, highlight: (space.dueAt ?? .distantFuture) < .now) { date in
                                var changed = space
                                changed.dueAt = date
                                Task { await model.saveSpace(changed) }
                            }
                            Picker("Status", selection: Binding(get: { space.status }, set: { status in
                                var changed = space
                                changed.status = status
                                Task { await model.saveSpace(changed) }
                            })) {
                                Text("Active").tag(Space.Status.active)
                                Text("Paused").tag(Space.Status.paused)
                                Text("Done").tag(Space.Status.done)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }

            // One add bar for the Space: a task (Blink) or a reminder (Apple Reminders, in the Space's own list).
            HStack(spacing: 10) {
                Picker("Add as", selection: $addAsReminder) {
                    Text("Task").tag(false)
                    Text("Reminder").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                AddField(placeholder: addAsReminder ? "Remind me in \(space.title), e.g. \"Call the printer friday 10am\""
                                                    : "Add a task to \(space.title), e.g. \"Draft homepage friday\"", text: $newTask) {
                    let parsed = TaskInput.parse(newTask)
                    guard !parsed.title.isEmpty else { return }
                    if addAsReminder {
                        Task { await model.addReminder(parsed.title, due: parsed.due, to: space) }
                    } else {
                        model.create(.task, title: parsed.title, due: parsed.due, space: space.id)
                    }
                    newTask = ""
                }
            }

            let reminders = model.spaceReminders[space.id] ?? []
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { tasksCard(open); remindersCard(reminders) }
                VStack(spacing: 14) { tasksCard(open); remindersCard(reminders) }
            }

            DashCard("Notes", trailing: "New Note", action: {
                openNote(model.create(.note, title: "", space: space.id).id)
            }) {
                if notes.isEmpty {
                    Text("Meeting notes, ideas and drafts for this space show here.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                        ForEach(notes) { note in
                            Button { openNote(note.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(note.title.isEmpty ? "New note" : note.title).font(.headline).lineLimit(1)
                                    Text(note.body.isEmpty ? " " : note.body).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                                    Spacer(minLength: 0)
                                    Text(note.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .cardSurface(radius: Tokens.Radius.tile)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !done.isEmpty {
                DashCard {
                    DisclosureGroup(isExpanded: $showDone) {
                        CardRows(items: done) { TaskRow(task: $0, showsSpace: false) }.padding(.top, 8)
                    } label: {
                        Text("Done (\(done.count))").font(.headline)
                    }
                }
            }
        }
        .task(id: space.id) { await model.loadReminders(for: space) }
        .toolbar {
            Menu {
                Button("Rename…") { newTitle = space.title; renaming = true }
                Menu("Colour") {
                    ForEach(Space.colors, id: \.self) { name in
                        Button(name.capitalized) {
                            var changed = space
                            changed.color = name
                            Task { await model.saveSpace(changed) }
                        }
                    }
                }
                Divider()
                Button("Delete Space…", role: .destructive) { confirmDelete = true }
            } label: {
                Label("Space", systemImage: "ellipsis.circle")
            }
        }
        .alert("Rename Space", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Save") {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return }
                var changed = space
                changed.title = title
                Task { await model.saveSpace(changed) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(space.title)”?", isPresented: $confirmDelete) {
            Button("Delete Space", role: .destructive) { Task { await model.deleteSpace(space) } }
        } message: {
            Text("Its tasks and notes are kept and move out of the space.")
        }
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
        .onAppear { goal = space.goal }
        .onDisappear(perform: saveGoal)
    }

    private func tasksCard(_ open: [BlinkItem]) -> some View {
        DashCard("Tasks · \(open.count)") {
            if open.isEmpty {
                Text("No open tasks. Add one above, or right-click any task › Move to Space.").foregroundStyle(.secondary)
            } else {
                CardRows(items: open) { TaskRow(task: $0, showsSpace: false) }
            }
        }
    }

    private func remindersCard(_ reminders: [AgendaReminder]) -> some View {
        DashCard("Reminders · \(reminders.count)") {
            if reminders.isEmpty {
                Text("Reminders added here go to a “\(space.title)” list in Apple Reminders, so they ring on your iPhone too.")
                    .foregroundStyle(.secondary)
            } else {
                CardRows(items: reminders) { reminder in
                    HStack(spacing: 10) {
                        Button { Task { await model.complete(reminder, in: space) } } label: {
                            Image(systemName: "circle").foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(reminder.title) done")
                        Text(reminder.title).lineLimit(1)
                        Spacer()
                        if let due = reminder.due { Text(Agenda.dueLabel(due)).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func summary(open: Int, progress: (done: Int, total: Int)) -> String {
        var parts = [open == 1 ? "1 open task" : "\(open) open tasks"]
        if let due = space.dueAt { parts.append("due \(due.formatted(.dateTime.weekday(.abbreviated).day().month()))") }
        if space.status != .active { parts.append(space.status.rawValue.capitalized) }
        return parts.joined(separator: " · ")
    }

    private func saveGoal() {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != space.goal else { return }
        var changed = space
        changed.goal = trimmed
        Task { await model.saveSpace(changed) }
    }
}

/// Done out of all tasks, as a ring with the percentage inside.
struct ProgressRing: View {
    let done: Int
    let total: Int
    let tint: Color

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(total == 0 ? "–" : "\(Int((fraction * 100).rounded()))%")
                .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .frame(width: 60, height: 60)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(total == 0 ? "No tasks yet" : "\(done) of \(total) tasks done")
    }
}

/// "All · ● Website · ● Visa": which Space a page shows. Hidden when there are no Spaces.
struct SpaceFilter: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: String

    var body: some View {
        if !model.spaces.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", id: "all", color: nil)
                    ForEach(model.spaces) { space in chip(space.title, id: space.id, color: Color.system(space.color)) }
                }
            }
        }
    }

    private func chip(_ title: String, id: String, color: Color?) -> some View {
        let on = selected == id
        return Button { selected = id } label: {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(on ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: .capsule)
            .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The small "● Website" tag on a task that belongs to a Space.
struct SpaceChip: View {
    let space: Space

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.system(space.color)).frame(width: 6, height: 6)
            Text(space.title).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("In \(space.title)")
    }
}

/// Right-click › Move to Space, for any task or note.
struct MoveToSpaceMenu: View {
    @Environment(AppModel.self) private var model
    let item: BlinkItem

    var body: some View {
        if !model.spaces.isEmpty {
            Menu("Move to Space") {
                ForEach(model.spaces) { space in
                    Button(space.title) { Task { await model.move(item, to: space.id) } }
                        .disabled(item.spaceID == space.id)
                }
                if item.spaceID != nil {
                    Divider()
                    Button("Remove from Space") { Task { await model.move(item, to: nil) } }
                }
            }
        }
    }
}

/// New Space: a name, an optional goal and due date, a colour.
struct NewSpaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let created: (String) -> Void
    @State private var title = ""
    @State private var goal = ""
    @State private var color = "blue"
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now

    var body: some View {
        Form {
            TextField("Name", text: $title, prompt: Text("e.g. Website launch"))
            TextField("Goal", text: $goal, prompt: Text("e.g. Launch by November"), axis: .vertical)
            Toggle("Due date", isOn: $hasDue)
            if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
            LabeledContent("Colour") {
                HStack(spacing: 6) {
                    ForEach(Space.colors, id: \.self) { name in
                        Button { color = name } label: {
                            Circle().fill(Color.system(name)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: color == name ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name.capitalized)
                        .accessibilityAddTraits(color == name ? .isSelected : [])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let space = Space(title: title.trimmingCharacters(in: .whitespaces),
                                      goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                      dueAt: hasDue ? due : nil, color: color)
                    Task { await model.createSpace(space) }
                    created(space.id)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
#endif
