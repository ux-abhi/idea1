// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// A Space as a canvas: a dark header with its icon, name and goal, and below it the plan as cards you drag and link.
/// The project sits in the middle; the tasks, sticky notes and reminders around it are the real ones from the rest of
/// Blink (a reminder lives in the Space's own Apple Reminders list), so ticking one here ticks it everywhere.
struct SpaceView: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @State private var customizing = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            SpaceHeader(space: space)
                .padding([.horizontal, .top], 20)
            SpaceCanvasView(space: space, openNote: openNote)
        }
        .background(BlinkCanvas())
        .task(id: space.id) { await model.loadCanvas(space) }
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

// MARK: Header

/// The Space's name, icon and goal on black, with its colour rising softly from the bottom.
private struct SpaceHeader: View {
    @Environment(AppModel.self) private var model
    let space: Space
    @State private var goal = ""
    @FocusState private var editingGoal: Bool

    var body: some View {
        let progress = Space.progress(of: model.items, in: space.id)
        HStack(spacing: 16) {
            Image(systemName: space.icon)
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: Tokens.Radius.tile, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(space.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                TextField("Add a goal, e.g. “Launch by December”", text: $goal, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
                    .focused($editingGoal)
                    .onSubmit(saveGoal)
                    .onChange(of: editingGoal) { _, now in if !now { saveGoal() } }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(progress.total == 0 ? "No tasks yet" : "\(progress.done) of \(progress.total) done")
                if let due = space.dueAt {
                    let days = Calendar.current.dateComponents([.day], from: .now, to: due).day ?? 0
                    Text(days >= 0 ? "\(days) days left" : "\(-days) days late").foregroundStyle(days < 0 ? .red : .secondary)
                }
            }
            .font(.callout.weight(.medium))
            .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HorizonGlow(tint: Color.system(space.color)))
        .clipShape(.rect(cornerRadius: Tokens.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear { goal = space.goal }
        .onChange(of: space.goal) { _, new in if !editingGoal { goal = new } }
    }

    private func saveGoal() {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != space.goal else { return }
        var changed = space
        changed.goal = trimmed
        Task { await model.saveSpace(changed) }
    }
}

/// Make the Space yours: icon, colour, deadline and status.
private struct SpaceCustomizer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: Space
    private static let icons = ["folder", "sparkles", "paperplane", "paintpalette", "book", "graduationcap", "airplane", "house",
                                "briefcase", "heart", "camera", "music.note", "leaf", "hammer", "chart.line.uptrend.xyaxis", "globe"]
    private static let colors = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal"]

    var body: some View {
        let current = model.spaces.first { $0.id == space.id } ?? space
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize \(current.title)").font(.title2.weight(.semibold))
            Text("Icon").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(Self.icons, id: \.self) { icon in
                    Button { update { $0.icon = icon } } label: {
                        Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                            .background(current.icon == icon ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05),
                                        in: .rect(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon)
                    .accessibilityAddTraits(current.icon == icon ? .isSelected : [])
                }
            }
            Text("Colour").font(.headline)
            HStack(spacing: 10) {
                ForEach(Self.colors, id: \.self) { name in
                    Button { update { $0.color = name } } label: {
                        Circle().fill(Color.system(name)).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: current.color == name ? 2 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.capitalized)
                    .accessibilityAddTraits(current.color == name ? .isSelected : [])
                }
            }
            HStack(spacing: 20) {
                LabeledContent("Deadline") {
                    DueMenu(due: current.dueAt, highlight: (current.dueAt ?? .distantFuture) < .now) { date in update { $0.dueAt = date } }
                }
                Picker("Status", selection: Binding(get: { current.status }, set: { s in update { $0.status = s } })) {
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

// MARK: Canvas

/// The plan as cards on a dotted sheet: drag a card to move it, drag from its dot to link it to another, and add new
/// ones from the bar at the bottom (linked to the selected card, or to the project).
private struct SpaceCanvasView: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @AppStorage("blinkPanel") private var showPanel = true
    @State private var selected: String?
    @State private var dragID: String?
    @State private var dragOffset: CGSize = .zero
    @State private var linkFrom: String?
    @State private var linkEnd: CGPoint = .zero

    private var nodes: [SpaceNode] { (model.canvasNodes[space.id] ?? []).filter { content(of: $0) != nil } }
    private var edges: [SpaceEdge] {
        let shown = Set(nodes.map(\.id))
        return (model.canvasEdges[space.id] ?? []).filter { shown.contains($0.from) && shown.contains($0.to) }
    }

    var body: some View {
        let nodes = nodes
        let edges = edges
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                DotGrid()
                    .contentShape(.rect)
                    .onTapGesture { selected = nil }
                Canvas { context, _ in
                    for edge in edges {
                        guard let a = nodes.first(where: { $0.id == edge.from }), let b = nodes.first(where: { $0.id == edge.to }) else { continue }
                        context.stroke(curve(point(a), point(b)), with: .color(.secondary.opacity(0.55)), lineWidth: 1.5)
                    }
                    if let from = nodes.first(where: { $0.id == linkFrom }) {
                        context.stroke(curve(point(from), linkEnd), with: .color(.accentColor),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    }
                }
                .allowsHitTesting(false)
                ForEach(nodes) { node in
                    card(node)
                        .position(point(node))
                }
            }
            .frame(width: AppModel.canvasSize.width, height: AppModel.canvasSize.height)
            .coordinateSpace(.named("canvas"))
        }
        .defaultScrollAnchor(.center)
        .overlay {
            if nodes.isEmpty { ProgressView().controlSize(.small) }
        }
        .overlay(alignment: .bottom) {
            CanvasToolbar(space: space, parent: nodes.first { $0.id == selected }, askBlink: askBlink, added: { selected = $0 })
                .padding(.bottom, 18)
        }
    }

    // MARK: Cards

    private enum Content {
        case project
        case item(BlinkItem)
        case reminder(AgendaReminder)
    }

    /// What a node points at, or nil when it's gone (deleted, finished reminder) and the next load will tidy it away.
    private func content(of node: SpaceNode) -> Content? {
        switch node.kind {
        case .project: .project
        case .task, .note: model.items.first { $0.id == node.ref && $0.status != .archived }.map(Content.item)
        case .reminder: model.spaceReminders[space.id]?.first { $0.id == node.ref }.map(Content.reminder)
        }
    }

    private func point(_ node: SpaceNode) -> CGPoint {
        let offset = node.id == dragID ? dragOffset : .zero
        return CGPoint(x: node.x + offset.width, y: node.y + offset.height)
    }

    /// A soft S-curve between two cards, leaving and arriving sideways.
    private func curve(_ a: CGPoint, _ b: CGPoint) -> Path {
        Path { path in
            let bend = max(abs(b.x - a.x) / 2, 40)
            path.move(to: a)
            path.addCurve(to: b, control1: CGPoint(x: a.x + (b.x >= a.x ? bend : -bend), y: a.y),
                          control2: CGPoint(x: b.x + (b.x >= a.x ? -bend : bend), y: b.y))
        }
    }

    @ViewBuilder
    private func card(_ node: SpaceNode) -> some View {
        let isSelected = selected == node.id
        let shape = RoundedRectangle(cornerRadius: node.kind == .note ? 8 : 14, style: .continuous)
        Group {
            switch content(of: node) {
            case .project: ProjectCard(space: space)
            case .item(let item) where node.kind == .note: StickyCard(note: item, tint: Color.system(node.color))
            case .item(let item): TaskCard(task: item, tint: Color.system(node.color))
            case .reminder(let reminder): ReminderCard(reminder: reminder, space: space)
            case nil: EmptyView()
            }
        }
        .frame(width: node.size.width, height: node.size.height)
        .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(isSelected ? 1 : 0))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .overlay(alignment: .trailing) { linkHandle(node) }
        .onTapGesture(count: 2) { if node.kind == .note, let ref = node.ref { openNote(ref) } }
        .onTapGesture { selected = node.id }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
                .onChanged { drag in
                    dragID = node.id
                    dragOffset = drag.translation
                }
                .onEnded { drag in
                    model.moveNode(node, x: node.x + drag.translation.width, y: node.y + drag.translation.height)
                    dragID = nil
                    dragOffset = .zero
                }
        )
        .contextMenu { menu(node) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The dot on a card's right edge: drag it onto another card to link the two.
    private func linkHandle(_ node: SpaceNode) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            .padding(8)
            .contentShape(.circle)
            .offset(x: 14)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { drag in
                        linkFrom = node.id
                        linkEnd = drag.location
                    }
                    .onEnded { drag in
                        linkFrom = nil
                        guard let target = nodes.first(where: { $0.id != node.id && $0.contains(x: drag.location.x, y: drag.location.y) })
                        else { return }
                        Task { await model.connect(node, to: target, in: space) }
                    }
            )
            .help("Drag onto another card to link them")
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func menu(_ node: SpaceNode) -> some View {
        switch content(of: node) {
        case .project:
            Button("Ask Blink About This Plan", action: askBlink)
        case .item(let item):
            if item.type == .note {
                Button("Open Note") { openNote(item.id) }
            } else {
                Button(item.status == .done ? "Mark Not Done" : "Mark Done") { Task { await model.toggle(item) } }
            }
            Menu("Colour") {
                ForEach(["yellow", "orange", "pink", "green", "mint", "blue", "purple"], id: \.self) { name in
                    Button(name.capitalized) { model.recolor(node, to: name) }
                }
            }
        case .reminder(let reminder):
            Button("Mark Done") { Task { await model.complete(reminder, in: space) } }
        case nil:
            EmptyView()
        }
        let links = edges.filter { $0.from == node.id || $0.to == node.id }
        if !links.isEmpty {
            Button("Remove Links") { Task { for edge in links { await model.disconnect(edge) } } }
        }
        if case .item(let item) = content(of: node) {
            Divider()
            Button(item.type == .note ? "Delete Note" : "Delete Task", role: .destructive) { Task { await model.deleteWithUndo(item) } }
        }
    }

    // MARK: Ask Blink

    private func askBlink() {
        showPanel = true
        Task {
            await model.ask("Look at this Space's plan. In a few lines, say where it stands and what's at risk, then suggest the next tasks it's missing as tasks I can approve.",
                            context: planSummary())
        }
    }

    /// The plan as plain text for Claude: the goal, every card, and what links to what.
    private func planSummary() -> String {
        var lines = ["Space: \(space.title)"]
        if !space.goal.isEmpty { lines.append("Goal: \(space.goal)") }
        if let due = space.dueAt { lines.append("Deadline: \(due.formatted(date: .abbreviated, time: .omitted))") }
        var names: [String: String] = [:]
        for node in nodes {
            switch content(of: node) {
            case .project: names[node.id] = space.title
            case .item(let item):
                let name = item.title.isEmpty ? String(item.body.prefix(60)) : item.title
                names[node.id] = name
                if item.type == .note {
                    lines.append("Sticky note: \(name)\(item.body.isEmpty ? "" : " — \(item.body.prefix(200))")")
                } else {
                    lines.append("Task\(item.status == .done ? " (done)" : ""): \(name)\(item.dueAt.map { " · due \(Agenda.dueLabel($0))" } ?? "")")
                }
            case .reminder(let reminder):
                names[node.id] = reminder.title
                lines.append("Reminder: \(reminder.title)\(reminder.due.map { " · \(Agenda.dueLabel($0))" } ?? "")")
            case nil: break
            }
        }
        for edge in edges { if let a = names[edge.from], let b = names[edge.to] { lines.append("Link: \(a) → \(b)") } }
        // The chat server takes at most 4000 characters of context (functions/chat input.ts).
        return String(lines.joined(separator: "\n").prefix(3900))
    }
}

/// The add bar floating over the canvas: + Task, + Sticky, + Reminder, and Ask Blink.
private struct CanvasToolbar: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let parent: SpaceNode?
    let askBlink: () -> Void
    let added: (String) -> Void
    @State private var adding: SpaceNode.Kind?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let adding {
                Image(systemName: symbol(adding)).foregroundStyle(.secondary).padding(.leading, 8).accessibilityHidden(true)
                TextField(placeholder(adding), text: $draft)
                    .textFieldStyle(.plain)
                    .frame(width: 300)
                    .focused($focused)
                    .onSubmit(add)
                    .onExitCommand { self.adding = nil }
                Button("Done") { self.adding = nil }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
            } else {
                tool("Task", symbol: symbol(.task), kind: .task)
                tool("Sticky", symbol: symbol(.note), kind: .note)
                tool("Reminder", symbol: symbol(.reminder), kind: .reminder)
                Divider().frame(height: 18).padding(.horizontal, 4)
                Button(action: askBlink) {
                    Label("Ask Blink", systemImage: "sparkles").padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(model.thinking)
            }
        }
        .font(.callout.weight(.medium))
        .padding(6)
        .frame(height: 44)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func tool(_ title: String, symbol: String, kind: SpaceNode.Kind) -> some View {
        Button {
            adding = kind
            focused = true
        } label: {
            Label(title, systemImage: symbol).padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help("Add a \(title.lowercased())\(parent.map { _ in " linked to the selected card" } ?? "")")
    }

    private func symbol(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .reminder: "bell"
        case .project: "folder"
        }
    }

    private func placeholder(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "Task, e.g. “Draft homepage friday”"
        case .note: "Sticky note"
        case .reminder: "Reminder, e.g. “Call the printer friday 10am”"
        case .project: ""
        }
    }

    /// Adds the card and keeps the field open for the next one; Escape or Done closes it.
    private func add() {
        guard let adding else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parsed = adding == .note ? (title: text, due: Date?.none) : { let p = TaskInput.parse(text); return (title: p.title, due: p.due) }()
        guard !parsed.title.isEmpty else { return }
        draft = ""
        Task {
            if let node = await model.addToCanvas(adding, title: parsed.title, due: parsed.due, in: space, linkedFrom: parent) {
                added(node.id)
            }
        }
    }
}

// MARK: Card faces

private struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    let space: Space

    var body: some View {
        let progress = Space.progress(of: model.items, in: space.id)
        HStack(spacing: 12) {
            Image(systemName: space.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.system(space.color).gradient, in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(space.title).font(.headline).lineLimit(1)
                Text(progress.total == 0 ? "Add the first task below" : "\(progress.done) of \(progress.total) done")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.system(space.color).opacity(0.6), lineWidth: 1.5))
    }
}

private struct TaskCard: View {
    @Environment(AppModel.self) private var model
    let task: BlinkItem
    let tint: Color

    var body: some View {
        let done = task.status == .done
        HStack(spacing: 10) {
            Button { Task { await model.toggle(task) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark \(task.title) not done" : "Mark \(task.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.callout.weight(.medium)).strikethrough(done).lineLimit(2)
                    .foregroundStyle(done ? .secondary : .primary)
                if let due = task.dueAt {
                    Text(Agenda.dueLabel(due)).font(.caption).foregroundStyle(due < .now && !done ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 3).padding(.vertical, 14).accessibilityHidden(true) }
    }
}

private struct StickyCard: View {
    let note: BlinkItem
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title.isEmpty ? "Untitled note" : note.title).font(.callout.weight(.semibold)).lineLimit(2)
            if !note.body.isEmpty {
                Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(6)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.28), in: .rect(cornerRadius: 8, style: .continuous))
        .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to open")
    }
}

private struct ReminderCard: View {
    @Environment(AppModel.self) private var model
    let reminder: AgendaReminder
    let space: Space

    var body: some View {
        HStack(spacing: 10) {
            Button { Task { await model.complete(reminder, in: space) } } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(reminder.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(.callout.weight(.medium)).lineLimit(2)
                if let due = reminder.due {
                    Text(Agenda.dueLabel(due)).font(.caption).foregroundStyle(due < .now ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "bell.fill").font(.caption).foregroundStyle(.orange).accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Faint dots every 24 points, drawn once as one path.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 12.0, to: size.width, by: 24) {
                for y in stride(from: 12.0, to: size.height, by: 24) {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.3)))
        }
        .accessibilityHidden(true)
    }
}
#endif
