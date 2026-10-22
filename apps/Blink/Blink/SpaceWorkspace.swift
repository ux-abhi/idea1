// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// A Space as a project workspace: a cover with its icon, goal, deadline and progress, then three views of the same
/// work. Overview is the whole project at a glance; Board moves tasks between the Space's own columns by dragging;
/// Notes is its writing. Everything is the same task or note as in the rest of Blink, and reminders live in the
/// Space's own Apple Reminders list.
struct SpaceView: View {
    enum Tab: String, CaseIterable { case overview = "Overview", board = "Board", notes = "Notes" }

    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @AppStorage("space.tab") private var tab = Tab.overview.rawValue
    @State private var customizing = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SpaceCover(space: space, customize: { customizing = true })
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
                switch Tab(rawValue: tab) ?? .overview {
                case .overview: SpaceOverview(space: space, openNote: openNote, showBoard: { tab = Tab.board.rawValue })
                case .board: SpaceBoard(space: space)
                case .notes: SpaceNotes(space: space, openNote: openNote)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BlinkCanvas())
        .task(id: space.id) { await model.loadReminders(for: space) }
        .sheet(isPresented: $customizing) { SpaceCustomizer(space: space) }
        .toolbar {
            Menu {
                Button("Customize…") { customizing = true }
                Button("Rename…") { newTitle = space.title; renaming = true }
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
    }
}

// MARK: Cover

extension Space {
    /// The cover's gradient: Apple system colours only, so it works in light and dark.
    var coverColors: [Color] {
        switch cover {
        case "ocean": [.blue, .teal, .cyan]
        case "sunset": [.orange, .pink, .purple]
        case "forest": [.green, .mint, .teal]
        case "dusk": [.indigo, .purple, .black]
        case "rose": [.pink, .red, .orange]
        case "mono": [.gray, .black, .gray]
        default: [.purple, .blue, .mint] // aurora
        }
    }
}

/// The Space's header: its cover gradient, icon, name, goal, deadline, status and progress ring.
private struct SpaceCover: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let customize: () -> Void
    @State private var goal = ""
    @FocusState private var editingGoal: Bool

    var body: some View {
        let progress = Space.progress(of: model.items, in: space.id)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: space.coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(height: 210)
            HStack(alignment: .bottom, spacing: 16) {
                Image(systemName: space.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(space.title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    TextField("What's the goal? e.g. “Launch by December”", text: $goal, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.9))
                        .focused($editingGoal)
                        .onSubmit(saveGoal)
                        .onChange(of: editingGoal) { _, now in if !now { saveGoal() } }
                    HStack(spacing: 8) {
                        pill(space.status.rawValue.capitalized, symbol: space.status == .active ? "circle.fill" : "pause.circle")
                        if let due = space.dueAt {
                            let days = Calendar.current.dateComponents([.day], from: .now, to: due).day ?? 0
                            pill(days >= 0 ? "\(days) days left" : "\(-days) days late", symbol: "flag.fill")
                        }
                        pill("\(progress.done)/\(progress.total) done", symbol: "checkmark.circle")
                    }
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 7)
                    Circle().trim(from: 0, to: progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total))
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(progress.total == 0 ? "–" : "\(progress.done * 100 / max(progress.total, 1))%")
                        .font(.callout.weight(.semibold)).foregroundStyle(.white).monospacedDigit()
                }
                .frame(width: 62, height: 62)
                .accessibilityLabel("\(progress.done) of \(progress.total) tasks done")
            }
            .padding(22)
        }
        .clipShape(.rect(cornerRadius: Tokens.Radius.card + 6, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: customize) {
                Label("Customize", systemImage: "paintbrush.pointed")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: .capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(14)
        }
        .onAppear { goal = space.goal }
        .onChange(of: space.goal) { _, new in if !editingGoal { goal = new } }
    }

    private func pill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.18), in: .capsule)
            .foregroundStyle(.white)
    }

    private func saveGoal() {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != space.goal else { return }
        var changed = space
        changed.goal = trimmed
        Task { await model.saveSpace(changed) }
    }
}

/// Make the Space yours: cover, icon, colour, deadline and status.
private struct SpaceCustomizer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: Space
    private static let icons = ["folder", "sparkles", "rocket", "paintpalette", "book", "graduationcap", "airplane", "house",
                                "briefcase", "heart", "camera", "music.note", "leaf", "hammer", "chart.line.uptrend.xyaxis", "globe"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize \(space.title)").font(.title2.weight(.semibold))
            Text("Cover").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(Space.covers, id: \.self) { name in
                    var preview = space
                    let _ = preview.cover = name
                    Button { update { $0.cover = name } } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: preview.coverColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(space.cover == name ? Color.white : .clear, lineWidth: 3))
                            .overlay(alignment: .bottomLeading) {
                                Text(name.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.white).padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name.capitalized) cover")
                }
            }
            Text("Icon").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(Self.icons, id: \.self) { icon in
                    Button { update { $0.icon = icon } } label: {
                        Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                            .background(space.icon == icon ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05),
                                        in: .rect(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon)
                }
            }
            HStack(spacing: 20) {
                LabeledContent("Deadline") {
                    DueMenu(due: space.dueAt, highlight: (space.dueAt ?? .distantFuture) < .now) { date in update { $0.dueAt = date } }
                }
                Picker("Status", selection: Binding(get: { space.status }, set: { s in update { $0.status = s } })) {
                    Text("Active").tag(Space.Status.active)
                    Text("Paused").tag(Space.Status.paused)
                    Text("Done").tag(Space.Status.done)
                }
                .fixedSize()
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func update(_ change: (inout Space) -> Void) {
        var changed = model.spaces.first { $0.id == space.id } ?? space
        change(&changed)
        Task { await model.saveSpace(changed) }
    }
}

// MARK: Overview

private struct SpaceOverview: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    let showBoard: () -> Void
    @State private var newTask = ""
    @AppStorage("space.addAsReminder") private var addAsReminder = false

    var body: some View {
        let mine = model.items.filter { $0.spaceID == space.id }
        let open = mine.filter { $0.type == .task && $0.status == .open }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let notes = mine.filter { $0.type == .note }.sorted { $0.updatedAt > $1.updatedAt }
        let reminders = model.spaceReminders[space.id] ?? []
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker("Add as", selection: $addAsReminder) {
                    Text("Task").tag(false)
                    Text("Reminder").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                AddField(placeholder: addAsReminder ? "Remind me, e.g. \"Call the printer friday 10am\"" : "Add a task, e.g. \"Draft homepage friday\"",
                         text: $newTask) {
                    let parsed = TaskInput.parse(newTask)
                    guard !parsed.title.isEmpty else { return }
                    if addAsReminder { Task { await model.addReminder(parsed.title, due: parsed.due, to: space) } }
                    else { model.create(.task, title: parsed.title, due: parsed.due, space: space.id) }
                    newTask = ""
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                // Where the work stands, column by column; a click opens the board.
                WidgetTile(title: "Board", symbol: "rectangle.split.3x1", tint: .indigo, open: showBoard) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(space.columns, id: \.self) { column in
                            let count = mine.filter { $0.type == .task && space.column(of: $0) == column }.count
                            HStack {
                                Text(column).font(.callout)
                                Spacer()
                                Text("\(count)").font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                WidgetTile(title: "Next up · \(open.count)", symbol: "checklist", tint: .orange) {
                    if open.isEmpty { Text("Nothing open. Add a task above.").foregroundStyle(.secondary) }
                    else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(open.prefix(4)) { task in
                                HStack(spacing: 8) {
                                    Button { Task { await model.toggle(task) } } label: { Image(systemName: "circle").foregroundStyle(.orange) }
                                        .buttonStyle(.plain).accessibilityLabel("Mark \(task.title) done")
                                    Text(task.title).font(.callout).lineLimit(1)
                                    Spacer()
                                    if let due = task.dueAt { Text(Agenda.dueLabel(due)).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                WidgetTile(title: "Reminders · \(reminders.count)", symbol: "bell.fill", tint: .red) {
                    if reminders.isEmpty {
                        Text("Reminders here go to a “\(space.title)” list in Apple Reminders.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(reminders.prefix(4)) { reminder in
                                HStack(spacing: 8) {
                                    Button { Task { await model.complete(reminder, in: space) } } label: { Image(systemName: "circle").foregroundStyle(.red) }
                                        .buttonStyle(.plain).accessibilityLabel("Mark \(reminder.title) done")
                                    Text(reminder.title).font(.callout).lineLimit(1)
                                    Spacer()
                                    if let due = reminder.due { Text(Agenda.dueLabel(due)).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                WidgetTile(title: "Latest notes · \(notes.count)", symbol: "note.text", tint: .yellow) {
                    if notes.isEmpty {
                        Button("Write the first note") { openNote(model.create(.note, title: "", space: space.id).id) }.buttonStyle(.link)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(notes.prefix(3)) { note in
                                Button { openNote(note.id) } label: {
                                    HStack {
                                        Text(note.title.isEmpty ? "New note" : note.title).font(.callout).lineLimit(1)
                                        Spacer()
                                        Text(note.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Board

/// The Space's columns side by side; cards drag between them (the last column means done). Columns can be added,
/// renamed and removed.
private struct SpaceBoard: View {
    @Environment(AppModel.self) private var model
    let space: Space
    @State private var addingColumn = false
    @State private var newColumn = ""

    var body: some View {
        let tasks = model.items.filter { $0.spaceID == space.id && $0.type == .task && $0.status != .archived }
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(space.columns, id: \.self) { column in
                    BoardColumn(space: space, column: column,
                                cards: tasks.filter { space.column(of: $0) == column }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) })
                }
                if space.columns.count < 8 {
                    Button { addingColumn = true } label: {
                        Label("Add Column", systemImage: "plus")
                            .frame(width: 180, height: 44)
                            .cardSurface(radius: Tokens.Radius.tile)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
        }
        .alert("New Column", isPresented: $addingColumn) {
            TextField("e.g. Review", text: $newColumn)
            Button("Add") { let name = newColumn; newColumn = ""; Task { await model.addColumn(name, to: space) } }
            Button("Cancel", role: .cancel) { newColumn = "" }
        }
    }
}

private struct BoardColumn: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let column: String
    let cards: [BlinkItem]
    @State private var targeted = false
    @State private var adding = ""
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let isDone = column == space.columns.last
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(isDone ? Color.green : Color.system(space.color)).frame(width: 8, height: 8)
                Text(column).font(.headline)
                Text("\(cards.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.primary.opacity(0.06), in: .capsule)
                Spacer()
                Menu {
                    Button("Rename…") { newName = column; renaming = true }
                    if space.columns.count > 2 && !isDone {
                        Button("Remove Column", role: .destructive) { Task { await model.removeColumn(column, from: space) } }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("\(column) options")
            }
            ForEach(cards) { task in
                BoardCard(task: task, done: isDone)
                    .draggable(task.id)
            }
            if !isDone {
                TextField("Add a card", text: $adding)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        let parsed = TaskInput.parse(adding)
                        guard !parsed.title.isEmpty else { return }
                        var item = model.create(.task, title: parsed.title, due: parsed.due, space: space.id)
                        item.stage = column
                        model.edit(item)
                        Task { await model.save(item.id) }
                        adding = ""
                    }
            }
        }
        .padding(14)
        .frame(width: 270, alignment: .top)
        .frame(minHeight: 260, alignment: .top)
        .cardSurface(radius: Tokens.Radius.tile)
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { if let task = model.items.first(where: { $0.id == id && $0.type == .task }) { model.move(task, toColumn: column, in: space) } }
            return true
        } isTargeted: { targeted = $0 }
        .alert("Rename Column", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await model.renameColumn(column, to: newName, in: space) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct BoardCard: View {
    @Environment(AppModel.self) private var model
    let task: BlinkItem
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.callout.weight(.medium)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let due = task.dueAt {
                    let late = due < .now && !done
                    Label(Agenda.dueLabel(due), systemImage: "calendar")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((late ? Color.orange : Color.primary).opacity(late ? 0.2 : 0.06), in: .capsule)
                        .foregroundStyle(late ? .orange : .secondary)
                }
                if !task.body.isEmpty { Image(systemName: "text.alignleft").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .contextMenu {
            Button(done ? "Mark Not Done" : "Mark Done") { Task { await model.toggle(task) } }
            Button("Delete", role: .destructive) { Task { await model.deleteWithUndo(task) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag to another column")
    }
}

// MARK: Notes

private struct SpaceNotes: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @State private var query = ""

    var body: some View {
        let notes = model.items.filter { $0.spaceID == space.id && $0.type == .note }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PageSearchField(prompt: "Search \(space.title)'s notes", text: $query)
                Spacer()
                Button { openNote(model.create(.note, title: "", space: space.id).id) } label: { Label("New Note", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderedProminent)
            }
            if notes.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "note.text",
                                       description: Text("Meeting notes, ideas and drafts for \(space.title) live here, and in Notes."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(notes) { note in
                        Button { openNote(note.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(note.title.isEmpty ? "New note" : note.title).font(.headline).lineLimit(2)
                                Text(note.body.isEmpty ? " " : note.body).font(.callout).foregroundStyle(.secondary).lineLimit(5)
                                Spacer(minLength: 0)
                                Text(note.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                            .cardSurface(radius: Tokens.Radius.tile)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .draggable(note.id)
                    }
                }
            }
        }
    }
}
#endif
