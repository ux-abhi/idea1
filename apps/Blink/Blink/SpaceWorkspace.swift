// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// A Space as a canvas, FigJam-style: the plan as cards you add, edit, drag and link right where they are. The project
/// sits in the middle; the tasks, sticky notes and reminders around it are the real ones from the rest of Blink (a
/// reminder lives in the Space's own Apple Reminders list), so ticking one here ticks it everywhere.
struct SpaceView: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @State private var customizing = false
    @State private var confirmDelete = false

    var body: some View {
        SpaceCanvasView(space: space, openNote: openNote, customize: { customizing = true }, delete: { confirmDelete = true })
        .task(id: space.id) { await model.loadCanvas(space) }
        .sheet(isPresented: $customizing) { SpaceCustomizer(space: space) }
        .confirmationDialog("Delete “\(space.title)”?", isPresented: $confirmDelete) {
            Button("Delete Space", role: .destructive) { Task { await model.deleteSpace(space) } }
        } message: {
            Text("Its tasks and notes are kept and move out of the space.")
        }
        .safeAreaInset(edge: .bottom) { SaveProblemBar() }
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

/// What a card on the canvas points at.
private enum CardContent {
    case project
    case item(BlinkItem)
    case reminder(AgendaReminder)
    case image(String)
}

/// A card being written before it exists: where it goes, what kind, and what's typed so far.
private struct CardDraft: Equatable {
    var kind: SpaceNode.Kind
    var x: Double
    var y: Double
    var parentID: String?
    var text = ""
}

/// The plan as cards on a dotted sheet that pans and zooms. Double-click empty space to add a card there, double-click
/// a card to edit it in place, drag a card to move it, and drag from its dot to link it (or let go on empty space to
/// add a linked task there). Nothing here ever leaves the page.
private struct SpaceCanvasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let space: Space
    let openNote: (String) -> Void
    let customize: () -> Void
    let delete: () -> Void
    @AppStorage("blinkPanel") private var showPanel = true
    @State private var selected: String?
    @State private var editing: String?
    @State private var hovered: String?
    @State private var draft: CardDraft?
    /// A card being dragged, and the link being drawn: they reset on their own if a gesture is cancelled.
    @GestureState private var moving: (id: String, offset: CGSize)?
    @GestureState private var linking: (from: String, end: CGPoint)?
    @GestureState private var resizing: (id: String, by: CGSize)?
    @State private var pickingImage = false
    @State private var scale = 1.0
    /// A pinch under way: how much it has zoomed so far and where the fingers are, in view points. Until it ends the
    /// sheet is only scaled on screen (cheap and smooth); the real zoom is applied once, when the fingers lift.
    @GestureState private var pinch: (by: Double, at: CGPoint)? // resets itself if the pinch is cancelled
    /// After a zoom, where the view is scrolling to: until the scroll lands (a frame later than the new size), the sheet
    /// is shifted there on screen, so the zoom doesn't jump for a frame.
    @State private var settling: CGPoint?
    @State private var position = ScrollPosition()
    /// The part of the sheet on screen, in zoomed points.
    @State private var viewport = CGRect.zero
    @State private var centred = false
    @FocusState private var canvasFocused: Bool

    private static let zoomRange = 0.3...2.0

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
                Color.clear
                    .contentShape(.rect)
                    .gesture(SpatialTapGesture(count: 2).onEnded { tap in
                        startDraft(.task, at: (tap.location.x / scale, tap.location.y / scale), parent: nil)
                    })
                    .simultaneousGesture(TapGesture().onEnded { clearSelection() })
                Canvas { context, _ in
                    for edge in edges {
                        guard let a = nodes.first(where: { $0.id == edge.from }), let b = nodes.first(where: { $0.id == edge.to }) else { continue }
                        let (from, to) = ports(a, b)
                        context.stroke(curve(from, to), with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
                    }
                    if let linking, let from = nodes.first(where: { $0.id == linking.from }) {
                        let start = CGPoint(x: (point(from).x + from.size.width / 2) * scale, y: point(from).y * scale)
                        context.stroke(curve(start, CGPoint(x: linking.end.x * scale, y: linking.end.y * scale)), with: .color(.accentColor),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    }
                }
                .allowsHitTesting(false)
                ForEach(nodes) { node in
                    card(node)
                        .position(x: point(node).x * scale, y: point(node).y * scale)
                }
                if draft != nil {
                    DraftCard(draft: $draft, commit: finishDraft)
                        .scaleEffect(scale)
                        .position(x: (draft?.x ?? 0) * scale, y: (draft?.y ?? 0) * scale)
                }
            }
            .frame(width: AppModel.canvasSize.width * scale, height: AppModel.canvasSize.height * scale)
            // Sheet points are read before the on-screen pinch and settle shifts, so drops and links land where they look.
            .coordinateSpace(.named("canvas"))
            .dropDestination(for: URL.self) { urls, spot in
                let files = urls.filter(\.isFileURL).prefix(10)
                for (i, file) in files.enumerated() {
                    addImage(from: file, at: (spot.x / scale + Double(i) * 30, spot.y / scale + Double(i) * 30))
                }
                return !files.isEmpty
            }
            .scaleEffect(pinch?.by ?? 1, anchor: pinchAnchor)
            .offset(x: settling.map { viewport.minX - $0.x } ?? 0, y: settling.map { viewport.minY - $0.y } ?? 0)
        }
        .scrollPosition($position)
        // Opens on the middle of the sheet, where the project starts, even before the cards have loaded.
        .defaultScrollAnchor(.center)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
            viewport = rect
            // The scroll has landed (where the sheet's edges allow), so the on-screen shift can go.
            settling = nil
            centreOnceLoaded()
        }
        .onChange(of: nodes.isEmpty) { centreOnceLoaded() }
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { change, state, _ in state = (pinched(change.magnification) / scale, change.startLocation) }
                .onEnded { change in
                    let at = change.startLocation
                    zoom(to: pinched(change.magnification), keeping: ((viewport.minX + at.x) / scale, (viewport.minY + at.y) / scale), at: at)
                }
        )
        .background {
            ZStack {
                CanvasBackdrop(tint: Color.system(space.color))
                DotGrid(spacing: 24 * scale * (pinch?.by ?? 1), origin: dotOrigin)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($canvasFocused)
        .onDeleteCommand(perform: deleteSelected)
        .onExitCommand { draft != nil ? (draft = nil) : clearSelection() }
        .onKeyPress(.return) {
            guard let selected, editing == nil, draft == nil, ![.project, .image].contains(nodes.first(where: { $0.id == selected })?.kind) else { return .ignored }
            editing = selected
            return .handled
        }
        .overlay {
            if nodes.isEmpty { ProgressView().controlSize(.small) }
        }
        .overlay(alignment: .topLeading) { SpaceTitleCard(space: space, customize: customize, delete: delete).padding(16) }
        .overlay(alignment: .topTrailing) { SpaceProgressPill(space: space).padding(16) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if nodes.count <= 1 && draft == nil {
                    Text("Double-click anywhere to add a card. Drag a card's dot onto another to link them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                addBar
            }
            .padding(.bottom, 18)
        }
        .overlay(alignment: .bottomTrailing) { zoomBar.padding(18) }
        .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            for (i, file) in ((try? result.get()) ?? []).prefix(10).enumerated() {
                addImage(from: file, at: (viewCentre.x + Double(i) * 30, viewCentre.y + Double(i) * 30))
            }
        }
        .onChange(of: editing) { _, now in if now == nil && draft == nil { canvasFocused = true } }
        .onDisappear(perform: finishDraft)
    }

    // MARK: Cards

    /// What a node points at, or nil when it's gone (deleted, finished reminder).
    private func content(of node: SpaceNode) -> CardContent? {
        switch node.kind {
        case .project: .project
        case .task, .note: model.items.first { $0.id == node.ref && $0.status != .archived }.map(CardContent.item)
        case .reminder: model.spaceReminders[space.id]?.first { $0.id == node.ref }.map(CardContent.reminder)
        case .image: node.ref.map(CardContent.image)
        }
    }

    /// Where a node is drawn now, in sheet points: its spot plus any drag under way.
    private func point(_ node: SpaceNode) -> CGPoint {
        let offset = moving?.id == node.id ? moving?.offset ?? .zero : .zero
        let size = shown(node).size
        let grown = (width: size.width - node.size.width, height: size.height - node.size.height)
        return CGPoint(x: node.x + offset.width + grown.width / 2, y: node.y + offset.height + grown.height / 2)
    }

    /// A node as drawn now: with the size it's being dragged to, if any.
    private func shown(_ node: SpaceNode) -> SpaceNode {
        guard let resizing, resizing.id == node.id else { return node }
        var live = node
        // Whole points: a fraction-of-a-point size each frame makes the text rewrap and the edges shimmer.
        (live.w, live.h) = SpaceNode.clamped(width: (node.size.width + resizing.by.width).rounded(),
                                             height: (node.size.height + resizing.by.height).rounded())
        return live
    }

    /// A link leaves the side of one card facing the other and arrives at the other's near side, in zoomed points.
    private func ports(_ a: SpaceNode, _ b: SpaceNode) -> (CGPoint, CGPoint) {
        let pa = point(a), pb = point(b)
        let rightward = pb.x >= pa.x
        let from = CGPoint(x: pa.x + (rightward ? a.size.width : -a.size.width) / 2, y: pa.y)
        let to = CGPoint(x: pb.x + (rightward ? -b.size.width : b.size.width) / 2, y: pb.y)
        return (CGPoint(x: from.x * scale, y: from.y * scale), CGPoint(x: to.x * scale, y: to.y * scale))
    }

    private func curve(_ a: CGPoint, _ b: CGPoint) -> Path {
        Path { path in
            let bend = max(abs(b.x - a.x) / 2, 30)
            let sign: CGFloat = b.x >= a.x ? 1 : -1
            path.move(to: a)
            path.addCurve(to: b, control1: CGPoint(x: a.x + sign * bend, y: a.y), control2: CGPoint(x: b.x - sign * bend, y: b.y))
        }
    }

    private func card(_ node: SpaceNode) -> some View {
        let isSelected = selected == node.id
        let isEditing = editing == node.id
        let active = isSelected || hovered == node.id
        return CanvasCard(node: shown(node), space: space, content: content(of: node) ?? .project, selected: isSelected, editing: $editing)
            .overlay(alignment: .trailing) {
                linkPort(node).opacity(active || linking?.from == node.id ? 1 : 0)
            }
            .overlay(alignment: .bottomTrailing) {
                if node.resizable && !isEditing { resizeHandle(node).opacity(active || resizing?.id == node.id ? 1 : 0) }
            }
            .onHover { inside in hovered = inside ? node.id : (hovered == node.id ? nil : hovered) }
            .scaleEffect(scale)
            .onTapGesture(count: 2) { edit(node) }
            .simultaneousGesture(TapGesture().onEnded {
                if draft != nil { finishDraft() }
                selected = node.id
                if !isEditing { editing = nil; canvasFocused = true }
            })
            .gesture(moveGesture(node), including: isEditing ? .subviews : .all)
            .contextMenu { menu(node) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Edit") { edit(node) }
            .accessibilityAction(named: "Select") { selected = node.id }
    }

    private func edit(_ node: SpaceNode) {
        guard node.kind != .project, node.kind != .image else { return }
        if draft != nil { finishDraft() }
        selected = node.id
        editing = node.id
    }

    private func moveGesture(_ node: SpaceNode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .updating($moving) { drag, state, _ in
                state = (node.id, CGSize(width: drag.translation.width / scale, height: drag.translation.height / scale))
            }
            .onChanged { _ in if selected != node.id { selected = node.id } }
            .onEnded { drag in
                model.moveNode(node, x: node.x + drag.translation.width / scale, y: node.y + drag.translation.height / scale)
            }
    }

    /// The corner of a sticky or picture: drag it to make the card bigger or smaller.
    private func resizeHandle(_ node: SpaceNode) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.accentColor, in: .circle)
            .padding(4)
            .contentShape(.rect)
            .offset(x: 8, y: 8)
            // High priority, so the card's own move gesture never runs alongside it (the card would move and resize at once).
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .updating($resizing) { drag, state, _ in
                        state = (node.id, CGSize(width: drag.translation.width / scale, height: drag.translation.height / scale))
                    }
                    .onEnded { drag in
                        model.resize(node, width: (node.size.width + drag.translation.width / scale).rounded(),
                                     height: (node.size.height + drag.translation.height / scale).rounded())
                    }
            )
            .help("Drag to resize")
            .accessibilityHidden(true)
    }

    /// The dot on a card's right edge: drop it on another card to link the two, or on empty space for a new linked task.
    private func linkPort(_ node: SpaceNode) -> some View {
        Circle()
            .fill(.background)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 14, height: 14)
            .padding(8)
            .contentShape(.circle)
            .offset(x: 15)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .updating($linking) { drag, state, _ in
                        state = (node.id, CGPoint(x: drag.location.x / scale, y: drag.location.y / scale))
                    }
                    .onEnded { drag in
                        let end = CGPoint(x: drag.location.x / scale, y: drag.location.y / scale)
                        if let target = nodes.first(where: { $0.id != node.id && $0.contains(x: end.x, y: end.y) }) {
                            Task { await model.connect(node, to: target, in: space) }
                        } else if hypot(end.x - node.x, end.y - node.y) > node.size.width / 2 + 40 {
                            startDraft(.task, at: (end.x + 130, end.y), parent: node)
                        }
                    }
            )
            .help("Drag to another card to link them, or to empty space to add a linked task")
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func menu(_ node: SpaceNode) -> some View {
        switch content(of: node) {
        case .project:
            Button("Ask Blink About This Plan", action: askBlink)
        case .item(let item):
            Button("Edit") { edit(node) }
            if item.type == .note {
                Button("Open in Notes") { openNote(item.id) }
                Menu("Colour") {
                    ForEach(CanvasCard.stickyColors, id: \.self) { name in
                        Button(name.capitalized) { model.recolor(node, to: name) }
                    }
                }
                Picker("Text Size", selection: Binding(get: { node.textScale ?? 1 }, set: { model.setTextScale(node, to: $0) })) {
                    ForEach(CanvasCard.textScales, id: \.scale) { Text($0.name).tag($0.scale) }
                }
            } else {
                Button(item.status == .done ? "Mark Not Done" : "Mark Done") { Task { await model.toggle(item) } }
                dueMenu { due in
                    var changed = item
                    changed.dueAt = due
                    model.edit(changed)
                    Task { await model.save(changed.id) }
                }
            }
        case .reminder(let reminder):
            Button("Edit") { edit(node) }
            Button("Mark Done") { Task { await model.complete(reminder, in: space) } }
            dueMenu { due in
                Task {
                    await model.setDue(reminder, to: due)
                    await model.loadReminders(for: space)
                }
            }
        case .image:
            sizeMenu(node)
        case nil:
            EmptyView()
        }
        if node.kind == .note { sizeMenu(node) }
        let others = nodes.filter { other in
            other.id != node.id && !edges.contains { ($0.from == node.id && $0.to == other.id) || ($0.from == other.id && $0.to == node.id) }
        }
        if !others.isEmpty {
            Menu("Link To") {
                ForEach(others) { other in
                    Button(name(of: other)) { Task { await model.connect(node, to: other, in: space) } }
                }
            }
        }
        Button("Add Linked Task") { startDraft(.task, at: (node.x + node.size.width / 2 + 170, node.y), parent: node) }
        let links = edges.filter { $0.from == node.id || $0.to == node.id }
        if !links.isEmpty {
            Button("Remove Links") { Task { for edge in links { await model.disconnect(edge) } } }
        }
        if case .item(let item) = content(of: node) {
            Divider()
            Button(item.type == .note ? "Delete Note" : "Delete Task", role: .destructive) { Task { await model.deleteWithUndo(item) } }
        } else if node.kind == .image {
            Divider()
            Button("Remove Picture", role: .destructive) { Task { await model.removeImage(node) } }
        }
    }

    /// Sizes to pick for a sticky or picture, for when dragging its corner isn't handy (and for VoiceOver).
    private func sizeMenu(_ node: SpaceNode) -> some View {
        Menu("Size") {
            // Shrinks both sides by the same amount, so a picture keeps its shape at the smallest size.
            let smaller = max(0.75, 120 / node.size.width, 90 / node.size.height)
            Button("Smaller") { model.resize(node, width: node.size.width * smaller, height: node.size.height * smaller) }
            Button("Larger") { model.resize(node, width: node.size.width * 1.33, height: node.size.height * 1.33) }
            if node.kind == .note { Button("Standard") { model.resize(node, width: 190, height: 150) } }
        }
    }

    private func name(of node: SpaceNode) -> String {
        switch content(of: node) {
        case .project: space.title
        case .item(let item): item.title.isEmpty ? "Untitled" : item.title
        case .reminder(let reminder): reminder.title
        case .image: "Picture"
        case nil: ""
        }
    }

    private func dueMenu(_ set: @escaping (Date?) -> Void) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let at9 = { (days: Int) in calendar.date(byAdding: .hour, value: 24 * days + 9, to: today) }
        return Menu("Due") {
            Button("Today") { set(calendar.date(byAdding: .hour, value: 17, to: today)) }
            Button("Tomorrow") { set(at9(1)) }
            Button("Next Week") { set(at9(7)) }
            Divider()
            Button("No Due Date") { set(nil) }
        }
    }

    // MARK: Adding

    private func startDraft(_ kind: SpaceNode.Kind, at spot: (x: Double, y: Double), parent: SpaceNode?) {
        if draft != nil { finishDraft() }
        editing = nil
        selected = nil
        draft = CardDraft(kind: kind, x: spot.x, y: spot.y, parentID: parent?.id)
        let shown = CGRect(x: viewport.minX / scale, y: viewport.minY / scale, width: viewport.width / scale, height: viewport.height / scale)
        if viewport.width > 0, !shown.insetBy(dx: 150, dy: 80).contains(CGPoint(x: spot.x, y: spot.y)) { centre(on: spot) }
    }

    /// Makes the card from what's typed; an empty draft just goes away.
    private func finishDraft() {
        guard let done = draft else { return }
        draft = nil
        let text = done.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parsed = done.kind == .note ? (title: text, due: Date?.none) : { let p = TaskInput.parse(text); return (title: p.title, due: p.due) }()
        let parent = nodes.first { $0.id == done.parentID }
        Task {
            if let node = await model.addToCanvas(done.kind, title: parsed.title, due: parsed.due, in: space, linkedFrom: parent,
                                                  at: (done.x, done.y)) {
                selected = node.id
                canvasFocused = true
            }
        }
    }

    /// A new card from the bar: next to the selected card and linked to it, or in the middle of the view.
    private func add(_ kind: SpaceNode.Kind) {
        if let parent = nodes.first(where: { $0.id == selected }) {
            let spot = CanvasLayout.freeSpot(around: (parent.x, parent.y), taken: nodes, radius: 280)
            startDraft(kind, at: spot, parent: parent)
        } else {
            startDraft(kind, at: viewCentre, parent: nil)
        }
    }

    private func clearSelection() {
        if draft != nil { finishDraft() }
        selected = nil
        editing = nil
        canvasFocused = true
    }

    private func deleteSelected() {
        guard editing == nil, let node = nodes.first(where: { $0.id == selected }) else { return }
        switch content(of: node) {
        case .item(let item):
            selected = nil
            Task { await model.deleteWithUndo(item) }
        case .image:
            selected = nil
            Task { await model.removeImage(node) }
        default: break
        }
    }

    private func addImage(from file: URL, at spot: (x: Double, y: Double)) {
        Task { await model.addImage(from: file, in: space, at: spot) }
    }

    private var addBar: some View {
        HStack(spacing: 2) {
            barButton("Task", symbol: "checkmark.circle") { add(.task) }
            barButton("Sticky", symbol: "note.text") { add(.note) }
            barButton("Reminder", symbol: "bell") { add(.reminder) }
            barButton("Picture", symbol: "photo") { pickingImage = true }
            Divider().frame(height: 18).padding(.horizontal, 6)
            barButton("Ask Blink", symbol: "sparkles", action: askBlink)
                .foregroundStyle(Color.accentColor)
                .disabled(model.thinking)
        }
        .font(.callout.weight(.medium))
        .padding(5)
        .glassEffect(.regular, in: .capsule)
    }

    private func barButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).padding(.horizontal, 10).padding(.vertical, 7).contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(title == "Ask Blink" ? "Ask Blink to explain this plan and suggest what's missing"
              : title == "Picture" ? "Add a picture (or drop one onto the canvas)"
              : "Add a \(title.lowercased()), linked to the selected card if one is selected")
    }

    // MARK: Moving around

    private var viewCentre: (x: Double, y: Double) {
        guard viewport.width > 0 else { return AppModel.canvasCenter }
        return (viewport.midX / scale, viewport.midY / scale)
    }

    /// Scrolls so `spot` (in sheet points) is in the middle of the view.
    private func centre(on spot: (x: Double, y: Double), animated: Bool = true) {
        let target = CGPoint(x: max(spot.x * scale - viewport.width / 2, 0), y: max(spot.y * scale - viewport.height / 2, 0))
        if animated && !reduceMotion {
            withAnimation(.smooth(duration: 0.3)) { position.scrollTo(point: target) }
        } else {
            position.scrollTo(point: target)
        }
    }

    /// Zooms so the sheet point `spot` stays at `at` in the view (by default: the middle stays the middle).
    private func zoom(to new: Double, keeping spot: (x: Double, y: Double)? = nil, at: CGPoint? = nil) {
        let at = at ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let keep = spot ?? viewCentre
        scale = min(max(new, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        // Where the scroll can really go: never past the sheet's edges.
        let target = CGPoint(x: min(max(keep.x * scale - at.x, 0), max(AppModel.canvasSize.width * scale - viewport.width, 0)),
                             y: min(max(keep.y * scale - at.y, 0), max(AppModel.canvasSize.height * scale - viewport.height, 0)))
        settling = target
        position.scrollTo(point: target)
        // If the scroll lands anywhere else (or not at all), stop shifting soon anyway.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if settling == target { settling = nil }
        }
    }

    private func pinched(_ magnification: Double) -> Double {
        min(max(scale * magnification, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// The point a pinch scales the sheet around, as a fraction of the (zoomed) sheet.
    private var pinchAnchor: UnitPoint {
        guard let pinch else { return .center }
        return UnitPoint(x: (viewport.minX + pinch.at.x) / (AppModel.canvasSize.width * scale),
                         y: (viewport.minY + pinch.at.y) / (AppModel.canvasSize.height * scale))
    }

    /// Where a dot of the grid sits in the view, so the dots move with scrolling and with a pinch under way.
    private var dotOrigin: CGPoint {
        let by = pinch?.by ?? 1, at = pinch?.at ?? .zero
        let shown = settling ?? viewport.origin // the dots shift with the sheet while a zoom settles
        return CGPoint(x: (12 * scale - shown.x - at.x) * by + at.x, y: (12 * scale - shown.y - at.y) * by + at.y)
    }

    /// Zooms and scrolls so every card fits in the view.
    private func fitAll() {
        guard !nodes.isEmpty, viewport.width > 0 else { return }
        let left = nodes.map { $0.x - $0.size.width / 2 }.min() ?? 0, right = nodes.map { $0.x + $0.size.width / 2 }.max() ?? 0
        let top = nodes.map { $0.y - $0.size.height / 2 }.min() ?? 0, bottom = nodes.map { $0.y + $0.size.height / 2 }.max() ?? 0
        // Room for the title card at the top and the add bar at the bottom.
        let fit = min(viewport.width / (right - left + 160), (viewport.height - 160) / (bottom - top + 80), 1.2)
        scale = min(max(fit, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        centre(on: ((left + right) / 2, (top + bottom) / 2), animated: false)
    }

    /// The first time the cards and the view are both ready: the project in the middle.
    private func centreOnceLoaded() {
        guard !centred, viewport.width > 0, let project = nodes.first(where: { $0.kind == .project }) else { return }
        centred = true
        // After this layout pass: a scroll asked for in the same pass as the first geometry is dropped.
        Task { centre(on: (project.x, project.y), animated: false) }
    }

    private var zoomBar: some View {
        HStack(spacing: 0) {
            Button("Zoom Out", systemImage: "minus") { zoom(to: scale / 1.25) }
                .keyboardShortcut("-", modifiers: .command)
            Button { zoom(to: 1) } label: {
                Text("\(Int((scale * 100).rounded()))%").monospacedDigit().frame(minWidth: 44)
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Actual size (⌘0)")
            .accessibilityLabel("Zoom \(Int((scale * 100).rounded())) percent, actual size")
            Button("Zoom In", systemImage: "plus") { zoom(to: scale * 1.25) }
                .keyboardShortcut("=", modifiers: .command)
            Divider().frame(height: 16).padding(.horizontal, 4)
            Button("Fit All Cards", systemImage: "arrow.up.left.and.arrow.down.right", action: fitAll)
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Ask Blink

    private func askBlink() {
        showPanel = true
        Task {
            await model.ask("Look at this Space's plan. In a few lines, say where it stands and what's at risk, then suggest the next tasks it's missing as tasks I can approve.",
                            context: planSummary(), space: space.id)
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
            case .image: names[node.id] = "a picture"
            case nil: break
            }
        }
        for edge in edges { if let a = names[edge.from], let b = names[edge.to] { lines.append("Link: \(a) → \(b)") } }
        // The chat server takes at most 4000 characters of context (functions/chat input.ts).
        return String(lines.joined(separator: "\n").prefix(3900))
    }
}

// MARK: Card

/// One card: an icon tile, the title and a quiet line under it; a sticky note is a square of colour instead. While
/// editing, the title (and a sticky's text) becomes a field right on the card, saved when you press Return or click away.
private struct CanvasCard: View {
    @Environment(AppModel.self) private var model
    let node: SpaceNode
    let space: Space
    let content: CardContent
    let selected: Bool
    @Binding var editing: String?
    @State private var title = ""
    @State private var text = ""
    @State private var cancelled = false
    @FocusState private var field: Field?

    enum Field { case title, text }
    static let stickyColors = ["yellow", "orange", "pink", "green", "mint", "teal"]
    static let textScales = [(name: "Small", scale: 0.85), (name: "Standard", scale: 1.0), (name: "Large", scale: 1.5),
                             (name: "Extra Large", scale: 2.2)]

    private var isEditing: Bool { editing == node.id }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: node.kind == .note ? 6 : 16, style: .continuous) }

    var body: some View {
        Group {
            switch content {
            case .image(let path): picture(path)
            default: if node.kind == .note { sticky } else { row }
            }
        }
        .frame(width: node.size.width, height: node.size.height)
        .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .onChange(of: isEditing, initial: true) { was, now in
            if now {
                load()
                Task { field = .title } // after the field is on screen
            } else if was && !cancelled {
                commit()
            }
        }
        .onChange(of: field) { _, now in if now == nil && isEditing { editing = nil } }
    }

    private var row: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .focused($field, equals: .title)
                        .onSubmit { editing = nil }
                        .onExitCommand(perform: cancel)
                } else {
                    Text(displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                }
                Text(subtitle).font(.caption).foregroundStyle(isOverdue ? .red : .secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thickMaterial, in: shape)
        .overlay(shape.strokeBorder(node.kind == .project ? Color.system(space.color).opacity(0.7) : Color.primary.opacity(0.08)))
    }

    /// The project's icon, or the circle that ticks a task or reminder off.
    @ViewBuilder
    private var tile: some View {
        let tint = node.kind == .reminder ? Color.orange : Color.system(node.kind == .project ? space.color : node.color)
        switch content {
        case .project:
            Image(systemName: space.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
        case .item(let task):
            Button { Task { await model.toggle(task) } } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.green : tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")
        case .reminder(let reminder):
            Button { Task { await model.complete(reminder, in: space) } } label: {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Mark done")
            .accessibilityLabel("Mark \(reminder.title) done")
        case .image:
            EmptyView()
        }
    }

    /// A sticky's text, at the size picked for it (Text Size in its menu).
    private func stickyFont(_ weight: Font.Weight = .regular) -> Font {
        .system(size: NSFont.preferredFont(forTextStyle: .callout).pointSize * (node.textScale ?? 1), weight: weight)
    }

    private var sticky: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("Title", text: $title, axis: .vertical)
                    .font(stickyFont(.semibold))
                    .lineLimit(1...3)
                    .focused($field, equals: .title)
                    .onSubmit { field = .text }
                // Scrolls inside the sticky, so a long note can all be read and edited at any card size.
                TextEditor(text: $text)
                    .font(stickyFont())
                    .scrollContentBackground(.hidden)
                    .focused($field, equals: .text)
                    .onExitCommand(perform: cancel)
                    .accessibilityLabel("Note text")
            } else if case .item(let note) = content {
                Text(note.title.isEmpty ? "Untitled note" : note.title).font(stickyFont(.semibold)).lineLimit(3)
                if !note.body.isEmpty { Text(note.body).font(stickyFont()).opacity(0.75) }
            }
            Spacer(minLength: 0)
        }
        .textFieldStyle(.plain)
        .foregroundStyle(.black.opacity(0.85))
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.system(node.color).opacity(0.9), in: shape)
        .clipShape(shape) // long text is cut at the card's edge instead of spilling out
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: isEditing ? .contain : .combine)
        .accessibilityHint(isEditing ? "" : "Double-click to edit")
    }

    /// A picture, filling its card; a soft placeholder while it loads.
    private func picture(_ path: String) -> some View {
        Group {
            if let image = model.canvasImages[path] {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: node.size.width, height: node.size.height)
        .clipShape(shape)
        .task(id: path) { await model.loadCanvasImage(path) }
        .accessibilityElement()
        .accessibilityLabel("Picture")
        .accessibilityAddTraits(.isImage)
    }

    private var isDone: Bool { if case .item(let item) = content { item.status == .done } else { false } }

    private var due: Date? {
        switch content {
        case .project: space.dueAt
        case .item(let item): item.dueAt
        case .reminder(let reminder): reminder.due
        case .image: nil
        }
    }

    private var isOverdue: Bool { !isDone && (due ?? .distantFuture) < .now }

    private var displayTitle: String {
        switch content {
        case .project: space.title
        case .item(let item): item.title.isEmpty ? "Untitled" : item.title
        case .reminder(let reminder): reminder.title
        case .image: "Picture"
        }
    }

    private var subtitle: String {
        let when = due.map { " · \(Agenda.dueLabel($0))" } ?? ""
        switch content {
        case .project:
            let progress = Space.progress(of: model.items, in: space.id)
            return progress.total == 0 ? "Project" : "Project · \(progress.done) of \(progress.total) done"
        case .item: return "Task\(when)"
        case .reminder: return "Reminder\(when)"
        case .image: return ""
        }
    }

    private func cancel() {
        cancelled = true
        editing = nil
    }

    private func load() {
        cancelled = false
        switch content {
        case .project: title = space.title
        case .item(let item): (title, text) = (item.title, item.body)
        case .reminder(let reminder): title = reminder.title
        case .image: break
        }
    }

    private func commit() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch content {
        case .project, .image: break
        case .item(let item):
            var changed = model.items.first { $0.id == item.id } ?? item
            if !newTitle.isEmpty { changed.title = newTitle }
            if item.type == .note { changed.body = text }
            guard changed.title != item.title || changed.body != item.body else { return }
            model.edit(changed)
            Task { await model.save(changed.id) }
        case .reminder(let reminder):
            guard !newTitle.isEmpty, newTitle != reminder.title else { return }
            Task {
                await model.rename(reminder, to: newTitle)
                await model.loadReminders(for: space)
            }
        }
    }
}

/// A card being written: pick task, sticky or reminder, type, Return. Escape or an empty card throws it away.
private struct DraftCard: View {
    @Binding var draft: CardDraft?
    let commit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let kind = draft?.kind ?? .task
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach([SpaceNode.Kind.task, .note, .reminder], id: \.self) { option in
                    Button {
                        draft?.kind = option
                        focused = true
                    } label: {
                        Label(Self.name(option), systemImage: Self.symbol(option))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(kind == option ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(kind == option ? .isSelected : [])
                }
            }
            TextField(Self.placeholder(kind), text: Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout.weight(.semibold))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { draft = nil }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(.thickMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .onAppear { Task { focused = true } }
    }

    static func name(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "Task"
        case .note: "Sticky"
        case .reminder: "Reminder"
        case .project: "Project"
        case .image: "Picture"
        }
    }

    static func symbol(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .reminder: "bell"
        case .project: "folder"
        case .image: "photo"
        }
    }

    static func placeholder(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "New task, e.g. “Draft homepage friday”"
        case .note: "Sticky note"
        case .reminder: "Remind me, e.g. “Call the printer friday 10am”"
        case .project, .image: ""
        }
    }
}

// MARK: Floating title and progress

/// The Space's icon, name and goal, floating at the top left of the canvas; both are edited right here.
private struct SpaceTitleCard: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let customize: () -> Void
    let delete: () -> Void
    @State private var title = ""
    @State private var goal = ""
    @FocusState private var field: Field?
    private enum Field { case title, goal }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: space.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.system(space.color).gradient, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                TextField("Space name", text: $title)
                    .font(.headline)
                    .focused($field, equals: .title)
                    .accessibilityAddTraits(.isHeader)
                TextField("Add a goal", text: $goal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .focused($field, equals: .goal)
            }
            .textFieldStyle(.plain)
            .frame(width: 230)
            .onSubmit { field = nil }
            // Here, not in the window toolbar: items that come and go between pages crash AppKit's toolbar.
            Menu {
                Button("Customize…", action: customize)
                Divider()
                Button("Delete Space…", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Space options")
        }
        .padding(10)
        .padding(.trailing, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .onAppear { (title, goal) = (space.title, space.goal) }
        .onChange(of: space) { _, new in if field == nil { (title, goal) = (new.title, new.goal) } }
        .onChange(of: field) { _, now in if now == nil { save() } }
        .onDisappear { if field != nil { save() } }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        let aim = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { title = space.title; return }
        guard name != space.title || aim != space.goal else { return }
        var changed = space
        changed.title = name
        changed.goal = aim
        Task { await model.saveSpace(changed) }
    }
}

/// How far along the Space is, and its deadline, floating at the top right.
private struct SpaceProgressPill: View {
    @Environment(AppModel.self) private var model
    let space: Space

    var body: some View {
        let progress = Space.progress(of: model.items, in: space.id)
        HStack(spacing: 8) {
            Gauge(value: Double(progress.done), in: 0...Double(max(progress.total, 1))) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Color.system(space.color))
                .scaleEffect(0.42)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(progress.total == 0 ? "No tasks yet" : "\(progress.done) of \(progress.total) done")
            if let due = space.dueAt {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
                Text("·").foregroundStyle(.tertiary)
                Text(days >= 0 ? "\(days) days left" : "\(-days) days late").foregroundStyle(days < 0 ? .red : .secondary)
            }
        }
        .font(.callout.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Backdrop

/// The sheet behind the cards: near-black in dark mode with the Space's colour rising softly from the bottom edge.
private struct CanvasBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    let tint: Color

    var body: some View {
        (scheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
            .overlay(
                EllipticalGradient(colors: [tint.opacity(scheme == .dark ? 0.45 : 0.25), tint.opacity(0.08), .clear], center: .bottom,
                                   startRadiusFraction: 0, endRadiusFraction: 0.75)
            )
            .ignoresSafeArea()
    }
}

/// Faint dots, drawn once as one path.
/// Drawn behind the scrolling sheet and only as big as the view, so zooming never redraws thousands of dots.
private struct DotGrid: View {
    let spacing: Double
    /// Where one dot sits, in view points; the rest repeat from it.
    let origin: CGPoint

    var body: some View {
        Canvas { context, size in
            guard spacing > 3 else { return }
            var dots = Path()
            let first = CGPoint(x: origin.x - (origin.x / spacing).rounded(.down) * spacing,
                                y: origin.y - (origin.y / spacing).rounded(.down) * spacing)
            for x in stride(from: first.x, to: size.width, by: spacing) {
                for y in stride(from: first.y, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.35)))
        }
        .accessibilityHidden(true)
    }
}
#endif
