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
    case post(ContentPiece)
    /// A heading or a section: its own text.
    case mark(String)
}

/// A card being written before it exists: where it goes, what kind, and what's typed so far.
private struct OpenedPost: Identifiable { let id: String }

private struct CardDraft: Equatable {
    var kind: SpaceNode.Kind
    var x: Double
    var y: Double
    var parentID: String?
    var text = ""
    /// For a post: the platforms to write for; none is picked for the owner.
    var platforms: Set<ContentPiece.Platform> = []
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
    /// A card being dragged; for a section, also the cards it carries along (worked out once, when the drag starts).
    @GestureState private var moving: (id: String, offset: CGSize, carried: Set<String>)?
    @GestureState private var linking: (from: String, end: CGPoint)?
    @GestureState private var resizing: (id: String, by: CGSize)?
    @State private var pickingImage = false
    /// A post opened to read or edit, right over the canvas.
    @State private var readingPost: String?
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

    /// Everything that belongs on this canvas, by id.
    private var spaceContents: [String] {
        model.items.filter { $0.spaceID == space.id && $0.status != .archived }.map(\.id)
            + model.content.filter { $0.spaceID == space.id && $0.status != .archived }.map(\.id)
            + (model.spaceReminders[space.id] ?? []).map(\.id)
    }

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
                // Sections sit behind the links and cards.
                ForEach(nodes.filter { $0.kind == .section }) { node in
                    card(node)
                        .position(x: point(node).x * scale, y: point(node).y * scale)
                }
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
                ForEach(nodes.filter { $0.kind != .section }) { node in
                    card(node)
                        .position(x: point(node).x * scale, y: point(node).y * scale)
                }
                if draft != nil {
                    DraftCard(draft: $draft, commit: finishDraft, ideas: postIdeas)
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
        // Something new in this Space (approved in chat, added on another page, drafts written): its card appears here.
        .onChange(of: spaceContents) { Task { await model.addMissingNodes(space) } }
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
            guard editing == nil, draft == nil, let node = nodes.first(where: { $0.id == selected }),
                  ![.project, .image].contains(node.kind) else { return .ignored }
            edit(node) // a post opens to read; the rest edit in place
            return .handled
        }
        .overlay {
            if nodes.isEmpty { ProgressView().controlSize(.small) }
        }
        .overlay(alignment: .topLeading) { SpaceTitleCard(space: space, customize: customize, delete: delete).padding(16) }
        .overlay(alignment: .topTrailing) { SpaceProgressPill(space: space).padding(16) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if model.drafting {
                    Label("Writing your post…", systemImage: "ellipsis").font(.callout).foregroundStyle(.secondary)
                } else if draft?.kind == .post, let problem = model.contentProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                } else if nodes.count <= 1 && draft == nil {
                    Text("Double-click anywhere to add a card. Drag a card's dot onto another to link them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                // The zoom bar sits on the right; an invisible twin on the left keeps the add bar centred. When the window is
                // narrow the add bar drops its words and keeps its icons, so the two never overlap.
                HStack(spacing: 0) {
                    zoomBar.hidden().disabled(true).accessibilityHidden(true) // disabled: its ⌘ shortcuts must not fire twice
                    Spacer(minLength: 12)
                    ViewThatFits(in: .horizontal) {
                        addBar(words: true)
                        addBar(words: false)
                    }
                    Spacer(minLength: 12)
                    zoomBar
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 18)
        }
        .sheet(item: Binding(get: { readingPost.map(OpenedPost.init) }, set: { readingPost = $0?.id })) { PieceSheet(id: $0.id) }
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
        case .post: model.content.first { $0.id == node.ref && $0.status != .archived }.map(CardContent.post)
        case .heading, .section: .mark(node.label ?? "")
        }
    }

    /// Where a node is drawn now, in sheet points: its spot plus any drag under way.
    private func point(_ node: SpaceNode) -> CGPoint {
        let offset = moving.map { $0.id == node.id || $0.carried.contains(node.id) ? $0.offset : .zero } ?? .zero
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
                if node.linkable { linkPort(node).opacity(active || linking?.from == node.id ? 1 : 0) }
            }
            .overlay(alignment: .bottomTrailing) {
                if node.resizable && !isEditing { resizeHandle(node).opacity(active || resizing?.id == node.id ? 1 : 0) }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected && !isEditing && node.kind != .image && node.kind != .heading { helper(node) }
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
        guard node.kind != .post else { readingPost = node.ref; return }
        if draft != nil { finishDraft() }
        selected = node.id
        editing = node.id
    }

    private func moveGesture(_ node: SpaceNode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .updating($moving) { drag, state, _ in
                let carried = state?.carried ?? Set(node.carried(in: nodes).map(\.id))
                state = (node.id, CGSize(width: drag.translation.width / scale, height: drag.translation.height / scale), carried)
            }
            .onChanged { _ in if selected != node.id { selected = node.id } }
            .onEnded { drag in
                let (dx, dy) = (drag.translation.width / scale, drag.translation.height / scale)
                if node.kind == .section {
                    model.moveSection(node, carrying: node.carried(in: nodes), by: dx, dy)
                } else {
                    model.moveNode(node, x: node.x + dx, y: node.y + dy)
                }
            }
    }

    /// Blink's help for the selected card, at its corner: a few things it can do with this card, answered in the panel
    /// (anything it proposes waits there as a card to approve).
    private func helper(_ node: SpaceNode) -> some View {
        Menu {
            ForEach(helps(for: node), id: \.title) { help in
                Button(help.title, systemImage: help.symbol) { askAbout(node, help.prompt) }
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.gradient, in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .offset(x: 10, y: -10)
        .scaleEffect(1 / scale, anchor: .bottomLeading) // same size at every zoom, still on the corner
        .disabled(model.thinking)
        .help("Ask Blink about this card")
        .accessibilityLabel("Ask Blink about \(name(of: node))")
    }

    private struct Help { let title: String; let symbol: String; let prompt: String }

    private func helps(for node: SpaceNode) -> [Help] {
        switch node.kind {
        case .project:
            [Help(title: "Suggest Next Tasks", symbol: "checklist", prompt: "Suggest the next 3 tasks this Space is missing, as tasks I can approve."),
             Help(title: "Post Ideas for This", symbol: "lightbulb", prompt: "Give me 5 specific post ideas about this Space's work. Ask which platform before proposing any.")]
        case .task, .reminder:
            [Help(title: "Break Into Steps", symbol: "list.bullet", prompt: "Break this into 3 to 5 small steps and propose them as tasks in this Space."),
             Help(title: "What's the Next Step?", symbol: "arrow.forward.circle", prompt: "What's the very next concrete step for this? One or two lines.")]
        case .note:
            [Help(title: "Turn Into Tasks", symbol: "checklist", prompt: "Turn this note into tasks and propose them in this Space."),
             Help(title: "Turn Into a Post", symbol: "megaphone", prompt: "Turn this note into a post idea. Ask me which platform first, then propose it.")]
        case .post:
            [Help(title: "Stronger Hooks", symbol: "text.quote", prompt: "Give me 5 stronger opening lines for this post, in my voice."),
             Help(title: "More Ideas Like This", symbol: "lightbulb", prompt: "Give me 5 more post ideas in the same direction as this one.")]
        case .section:
            [Help(title: "What's Left Here?", symbol: "checklist", prompt: "Look at the cards in this section. What's done, what's left, and what's at risk? A few short lines."),
             Help(title: "Suggest Next Tasks Here", symbol: "plus.circle", prompt: "Suggest the next 3 tasks for this section, as tasks I can approve in this Space.")]
        case .image, .heading:
            []
        }
    }

    /// Asks in the panel, with the card itself and the plan around it as context.
    private func askAbout(_ node: SpaceNode, _ prompt: String) {
        showPanel = true
        let card: String = switch content(of: node) {
        case .item(let item): "\(item.type == .note ? "Sticky note" : "Task"): \(item.title)\(item.body.isEmpty ? "" : " — \(item.body.prefix(600))")"
        case .reminder(let reminder): "Reminder: \(reminder.title)"
        case .post(let post): "Post (\(post.platform.name)): \(post.hook)\n\(post.body.prefix(600))"
        case .mark(let label) where node.kind == .section:
            "Section \"\(label)\" holding: \(node.carried(in: nodes).map(name(of:)).joined(separator: "; "))"
        default: "The Space itself"
        }
        Task { await model.ask(prompt, context: String("This card: \(card)\n\n\(planSummary())".prefix(3900)), space: space.id) }
    }

    /// From the post draft card: ideas for this Space, in the panel.
    private func postIdeas() {
        showPanel = true
        Task {
            await model.ask("Give me 5 specific post ideas for this Space, each with a one-line hook. Ask which platform before proposing any.",
                            context: planSummary(), space: space.id)
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
            .offset(x: 8, y: 12) // clear of the link dot on short cards
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
                        if let target = nodes.first(where: { $0.id != node.id && $0.linkable && $0.contains(x: end.x, y: end.y) }) {
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
        case .mark:
            Button("Rename") { edit(node) }
            if node.kind == .section {
                Menu("Colour") {
                    ForEach(["blue", "purple", "pink", "orange", "yellow", "green", "teal", "gray"], id: \.self) { name in
                        Button(name.capitalized) { model.recolor(node, to: name) }
                    }
                }
            } else {
                Picker("Text Size", selection: Binding(get: { node.textScale ?? 1 }, set: { model.setTextScale(node, to: $0) })) {
                    ForEach(CanvasCard.textScales, id: \.scale) { Text($0.name).tag($0.scale) }
                }
            }
        case .post(let post):
            Button("Open") { readingPost = post.id }
            Button("Show in Content") { model.openPage = "content" }
            Menu("Post On") {
                ForEach(0..<7, id: \.self) { ahead in
                    if let date = Calendar.current.date(byAdding: .day, value: ahead, to: .now) {
                        Button(HabitDay.label(HabitDay.key(date))) { Task { await model.setDay(HabitDay.key(date), of: post) } }
                    }
                }
                if post.plannedFor != nil {
                    Divider()
                    Button("No Day") { Task { await model.setDay(nil, of: post) } }
                }
            }
            Button("Copy Post") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(post.postText, forType: .string)
            }
        case nil:
            EmptyView()
        }
        if node.resizable && node.kind != .image && node.kind != .heading { sizeMenu(node) }
        let others = !node.linkable ? [] : nodes.filter { other in
            other.id != node.id && other.linkable && !edges.contains { ($0.from == node.id && $0.to == other.id) || ($0.from == other.id && $0.to == node.id) }
        }
        if !others.isEmpty {
            Menu("Link To") {
                ForEach(others) { other in
                    Button(name(of: other)) { Task { await model.connect(node, to: other, in: space) } }
                }
            }
        }
        if node.linkable {
            Button("Add Linked Task") { startDraft(.task, at: (node.x + node.size.width / 2 + 170, node.y), parent: node) }
        }
        let links = edges.filter { $0.from == node.id || $0.to == node.id }
        if !links.isEmpty {
            Button("Remove Links") { Task { for edge in links { await model.disconnect(edge) } } }
        }
        if case .item(let item) = content(of: node) {
            Divider()
            Button(item.type == .note ? "Delete Note" : "Delete Task", role: .destructive) { Task { await model.deleteWithUndo(item) } }
        } else if [.image, .heading, .section].contains(node.kind) {
            Divider()
            let what = node.kind == .image ? "Remove Picture" : node.kind == .heading ? "Delete Heading" : "Delete Section (Keeps Its Cards)"
            Button(what, role: .destructive) { Task { await model.removeNode(node) } }
        }
    }

    /// Sizes to pick for a sticky or picture, for when dragging its corner isn't handy (and for VoiceOver).
    private func sizeMenu(_ node: SpaceNode) -> some View {
        Menu("Size") {
            // Shrinks both sides by the same amount, so a picture keeps its shape at the smallest size.
            let smaller = max(0.75, 120 / node.size.width, 60 / node.size.height)
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
        case .post(let post): post.hook.isEmpty ? post.idea : post.hook
        case .mark(let label): label
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
        if done.kind == .post {
            // Blink writes one draft per platform picked; they land in Content and here, where the card was.
            let platforms = ContentPiece.Platform.allCases.filter(done.platforms.contains)
            // Keep what's typed until a platform is picked and no other post is being written.
            guard !platforms.isEmpty, !model.drafting else { draft = done; return }
            Task {
                if await model.draft(idea: text, platforms: platforms, space: space.id) {
                    await model.addMissingNodes(space, near: (done.x, done.y))
                } else if draft == nil {
                    draft = done // it didn't work: the text comes back, with the reason under the bar
                }
            }
            return
        }
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
        case .image, .mark:
            selected = nil
            Task { await model.removeNode(node) }
        default: break
        }
    }

    /// A heading or section in the middle of the view, named right away.
    private func addMark(_ kind: SpaceNode.Kind) {
        if draft != nil { finishDraft() }
        Task {
            let node = await model.addMark(kind, in: space, at: viewCentre)
            selected = node.id
            editing = node.id
        }
    }

    private func addImage(from file: URL, at spot: (x: Double, y: Double)) {
        Task { await model.addImage(from: file, in: space, at: spot) }
    }

    private func addBar(words: Bool) -> some View {
        HStack(spacing: 2) {
            barButton("Task", symbol: "checkmark.circle") { add(.task) }
            barButton("Sticky", symbol: "note.text") { add(.note) }
            barButton("Reminder", symbol: "bell") { add(.reminder) }
            barButton("Post", symbol: "megaphone") { add(.post) }
            barButton("Picture", symbol: "photo") { pickingImage = true }
            barButton("Heading", symbol: "textformat") { addMark(.heading) }
            barButton("Section", symbol: "rectangle.dashed") { addMark(.section) }
            Divider().frame(height: 18).padding(.horizontal, 6)
            barButton("Ask Blink", symbol: "sparkles", action: askBlink)
                .foregroundStyle(Color.accentColor)
                .disabled(model.thinking)
        }
        .environment(\.showsWords, words)
        .font(.callout.weight(.medium))
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }

    private func barButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconLabel(title: title, symbol: symbol).padding(.horizontal, 10).padding(.vertical, 7).contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(title == "Ask Blink" ? "Ask Blink to explain this plan and suggest what's missing"
              : title == "Picture" ? "Add a picture (or drop one onto the canvas)"
              : title == "Post" ? "Write a post for the platforms you pick; Blink drafts it into Content"
              : title == "Heading" ? "Add a heading to label part of the canvas"
              : title == "Section" ? "Add a section to group cards; drag its title to move it with everything inside"
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
            case .mark(let label):
                names[node.id] = label
                if node.kind == .section {
                    lines.append("Section \"\(label)\": \(node.carried(in: nodes).map(name(of:)).joined(separator: "; "))")
                } else {
                    lines.append("Heading: \(label)")
                }
            case .post(let post):
                names[node.id] = post.hook
                lines.append("Post (\(post.platform.name), \(post.status.rawValue)): \(post.hook)")
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
    private var growing: Bool { isEditing && node.kind != .note }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: node.kind == .note || node.kind == .heading ? 6 : node.kind == .section ? 22 : 16, style: .continuous)
    }
    /// Headings and sections lie flat on the sheet; cards float above it.
    private var flat: Bool { node.kind == .heading || node.kind == .section }

    var body: some View {
        Group {
            switch content {
            case .image(let path): picture(path)
            case .mark(let label): if node.kind == .section { section(label) } else { heading(label) }
            default: if node.kind == .note { sticky } else { row }
            }
        }
        // A task being edited grows downward to fit its whole title (its own height, not the board's); its spot and
        // centre stay put, so links and the line being typed don't move.
        .frame(width: node.size.width, height: growing ? nil : node.size.height)
        .frame(minHeight: node.size.height)
        .fixedSize(horizontal: false, vertical: growing)
        .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0).allowsHitTesting(false))
        .shadow(color: .black.opacity(flat ? 0 : 0.18), radius: 10, y: 4)
        .frame(height: node.size.height, alignment: .top)
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
                    TextField("Title", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1...8)
                        .focused($field, equals: .title)
                        .onSubmit { editing = nil }
                        .onExitCommand(perform: cancel)
                } else {
                    // As many lines as the card has room for (drag its corner to see more); the rest on hover.
                    Text(displayTitle)
                        .font(.callout.weight(.semibold))
                        .help(displayTitle)
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
        case .image, .mark:
            EmptyView()
        case .post(let post):
            Text(post.platform.short)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint.gradient, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
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

    /// A heading: big text straight on the sheet, at the size picked for it (Text Size in its menu).
    @ViewBuilder
    private func heading(_ label: String) -> some View {
        let font = Font.system(size: 22 * (node.textScale ?? 1), weight: .bold)
        Group {
            if isEditing {
                TextField("Heading", text: $title)
                    .textFieldStyle(.plain)
                    .focused($field, equals: .title)
                    .onSubmit { editing = nil }
                    .onExitCommand(perform: cancel)
            } else {
                Text(label.isEmpty ? "Heading" : label).lineLimit(2).minimumScaleFactor(0.6)
            }
        }
        .font(font)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityAddTraits(.isHeader)
    }

    /// A section: a soft tinted area behind its cards, with its title in a chip at the top. Only the chip takes clicks
    /// (drag it to move the section with everything inside, double-click to rename), so clicks inside reach the sheet.
    private func section(_ label: String) -> some View {
        let tint = Color.system(node.color)
        return ZStack(alignment: .topLeading) {
            shape.fill(tint.opacity(0.08))
                .overlay(shape.strokeBorder(tint.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
                .allowsHitTesting(false)
            Group {
                if isEditing {
                    TextField("Section", text: $title)
                        .textFieldStyle(.plain)
                        .focused($field, equals: .title)
                        .onSubmit { editing = nil }
                        .onExitCommand(perform: cancel)
                        .frame(width: 200)
                } else {
                    Text(label.isEmpty ? "Section" : label).lineLimit(1)
                }
            }
            .font(.headline)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(tint.opacity(0.22), in: .capsule)
            .contentShape(.capsule)
            .padding(12)
            .accessibilityAddTraits(.isHeader)
            .help("Drag to move the section with its cards; double-click to rename")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .image, .post, .mark: nil
        }
    }

    private var isOverdue: Bool { !isDone && (due ?? .distantFuture) < .now }

    private var displayTitle: String {
        switch content {
        case .project: space.title
        case .item(let item): item.title.isEmpty ? "Untitled" : item.title
        case .reminder(let reminder): reminder.title
        case .image: "Picture"
        case .post(let post): post.hook.isEmpty ? post.idea : post.hook
        case .mark(let label): label
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
        case .image, .mark: return ""
        case .post(let post):
            return "\(post.platform.name) · \(StatusChip.name(post.status))\(post.plannedFor.map { " · \(HabitDay.label($0))" } ?? "")"
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
        case .image, .post: break
        case .mark(let label): title = label
        }
    }

    private func commit() {
        let newTitle = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        switch content {
        case .project, .image, .post: break
        case .mark(let label):
            if !newTitle.isEmpty, newTitle != label { model.relabel(node, to: newTitle) }
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
    let ideas: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let kind = draft?.kind ?? .task
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                // The picked kind shows its name; the others only their icon, so the card stays calm.
                ForEach([SpaceNode.Kind.task, .note, .reminder, .post], id: \.self) { option in
                    Button {
                        draft?.kind = option
                        focused = true
                    } label: {
                        IconLabel(title: Self.name(option), symbol: Self.symbol(option))
                            .environment(\.showsWords, kind == option)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(kind == option ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05), in: .capsule)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .help(Self.name(option))
                    .accessibilityAddTraits(kind == option ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if kind == .post {
                    Button("Ideas", systemImage: "sparkles", action: ideas)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .help("Ask Blink for post ideas for this Space")
                }
            }
            TextField(Self.placeholder(kind), text: Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout.weight(.semibold))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { draft = nil }
            if kind == .post {
                HStack(spacing: 4) {
                    ForEach(ContentPiece.Platform.allCases, id: \.self) { platform in
                        let on = draft?.platforms.contains(platform) == true
                        Button {
                            if on { draft?.platforms.remove(platform) } else { draft?.platforms.insert(platform) }
                        } label: {
                            Label(platform.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(on ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05), in: .capsule)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                if draft?.platforms.isEmpty == true {
                    Text("Pick a platform, then press Return.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
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
        case .post: "Post"
        case .heading: "Heading"
        case .section: "Section"
        }
    }

    static func symbol(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .reminder: "bell"
        case .project: "folder"
        case .image: "photo"
        case .post: "megaphone"
        case .heading: "textformat"
        case .section: "rectangle.dashed"
        }
    }

    static func placeholder(_ kind: SpaceNode.Kind) -> String {
        switch kind {
        case .task: "New task, e.g. “Draft homepage friday”"
        case .note: "Sticky note"
        case .reminder: "Remind me, e.g. “Call the printer friday 10am”"
        case .project, .image, .heading, .section: ""
        case .post: "What's the post about?"
        }
    }
}

/// An icon with its name, or only the icon when there's no room (the name is still read by VoiceOver).
private struct IconLabel: View {
    @Environment(\.showsWords) private var showsWords
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if showsWords { Text(title) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

extension EnvironmentValues {
    @Entry var showsWords = true
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
