// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// Page mode (ADR-0002): a Space as a page of blocks, top to bottom, Notion-like. Type "/" on the last line, or open the
/// side panel, to add a block. Task lists and content boards show the Space's real tasks and posts (never copies), so
/// the page and the canvas always agree.
struct SpacePageView: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let openNote: (String) -> Void
    @State private var showPanel = false
    @State private var openPost: String?

    var body: some View {
        let blocks = model.spaceBlocks[space.id] ?? []
        let current = model.spaces.first { $0.id == space.id } ?? space
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageCover(space: current)
                VStack(alignment: .leading, spacing: 14) {
                    // The icon sits over the cover's lower edge, then the title big, like a document's first page.
                    Image(systemName: current.icon)
                        .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Color.system(current.color).gradient, in: .rect(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(nsColor: .textBackgroundColor), lineWidth: 4))
                        .padding(.top, -38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(current.title).font(.system(size: 40, weight: .bold)).textSelection(.enabled)
                        if !current.goal.isEmpty { Text(current.goal).font(.title3).foregroundStyle(.secondary) }
                    }
                    .padding(.bottom, 18)
                    if blocks.isEmpty {
                        Text("Empty page. Type / below for a heading, a table or board, a task list, a file and more.")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(blocks) { block in
                        BlockRow(block: block, space: current, openNote: openNote, openPost: { openPost = $0 })
                    }
                    AddBlockLine(space: current, after: blocks.last)
                    Spacer(minLength: 140)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 56)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topTrailing) {
            Button("Blocks", systemImage: showPanel ? "sidebar.right" : "plus") { showPanel.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.primary)
                .frame(width: 30, height: 30).background(.regularMaterial, in: .circle)
                .help(showPanel ? "Hide the blocks panel" : "Add a block")
                .padding(14)
        }
        .inspector(isPresented: $showPanel) {
            BlockPanel { kind in Task { await model.addBlock(kind, in: current) } }
                .inspectorColumnWidth(min: 220, ideal: 240, max: 300)
        }
        .task(id: space.id) { await model.loadBlocks(space) }
        .sheet(isPresented: Binding(get: { openPost != nil }, set: { if !$0 { openPost = nil } })) {
            if let openPost { PieceSheet(id: openPost) }
        }
    }
}

/// The page's cover: the Space's gradient, edge to edge. Hovering offers the other gradients.
private struct PageCover: View {
    @Environment(AppModel.self) private var model
    let space: Space
    @State private var hovering = false

    var body: some View {
        Rectangle().fill(Self.gradient(space.cover))
            .frame(height: 190)
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    ForEach(Space.covers, id: \.self) { name in
                        Button(name.capitalized) { var changed = space; changed.cover = name; Task { await model.saveSpace(changed) } }
                    }
                } label: { Label("Change Cover", systemImage: "photo.on.rectangle") }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: .capsule)
                    .padding(14)
                    .opacity(hovering ? 1 : 0)
            }
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cover")
    }

    /// The named covers, in Apple's system colours.
    static func gradient(_ name: String) -> LinearGradient {
        let colors: [Color] = switch name {
        case "ocean": [.blue, .cyan]
        case "sunset": [.orange, .pink]
        case "forest": [.green, .mint]
        case "dusk": [.indigo, .blue.opacity(0.6)]
        case "rose": [.pink, .red.opacity(0.75)]
        case "mono": [.gray.opacity(0.55), .gray.opacity(0.25)]
        default: [.teal, .blue, .indigo] // aurora
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The side panel: every block, to add at the end of the page.
private struct BlockPanel: View {
    let add: (SpaceBlock.Kind) -> Void

    var body: some View {
        List {
            Section("Add a block") {
                ForEach(SpaceBlock.Kind.addable, id: \.self) { kind in
                    Button { add(kind) } label: {
                        Label { VStack(alignment: .leading, spacing: 1) { Text(kind.title); Text(BlockText.hint(kind)).font(.caption).foregroundStyle(.secondary) } }
                        icon: { Image(systemName: kind.symbol) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

enum BlockText {
    static func hint(_ kind: SpaceBlock.Kind) -> String {
        switch kind {
        case .heading: "A title for a part of the page"
        case .text: "Words, ideas, plans"
        case .tasks: "This Space's tasks, tick them here"
        case .content: "This Space's posts, by stage"
        case .note: "One of your notes"
        case .link: "A web page, with its title"
        case .image: "A picture"
        case .timer: "Count down a few minutes"
        case .stopwatch: "Time something"
        case .table: "Rows and columns: a contact list, leads, anything"
        case .file: "A PDF, deck or picture the Space can use"
        }
    }
}

/// The last line: type to write, or "/" to pick a block.
private struct AddBlockLine: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let after: SpaceBlock?
    @State private var text = ""
    @FocusState private var focused: Bool

    private var matches: [SpaceBlock.Kind] {
        guard text.hasPrefix("/") else { return [] }
        let query = text.dropFirst().lowercased().trimmingCharacters(in: .whitespaces)
        return SpaceBlock.Kind.addable.filter { query.isEmpty || $0.title.lowercased().contains(query) || $0.rawValue.contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Type / to add a block, or just write", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand { text = "" }
                .accessibilityLabel("New block")
                .accessibilityHint("Type a slash to choose a block, or write text")
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches, id: \.self) { kind in
                        Button { add(kind) } label: {
                            Label(kind.title, systemImage: kind.symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(maxWidth: 280, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
        }
    }

    private func submit() {
        if let first = matches.first { add(first); return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        text = ""
        Task { await model.addBlock(.text, in: space, after: after, data: .init(text: words)); focused = true }
    }

    private func add(_ kind: SpaceBlock.Kind) {
        text = ""
        Task { await model.addBlock(kind, in: space, after: after); focused = true }
    }
}

/// One block. Its options (move, delete, and a table's CSV) are a ⋯ in the right margin on hover, and on right-click
/// for blocks that aren't text (text keeps the usual Cut, Copy and Paste).
private struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    let openNote: (String) -> Void
    let openPost: (String) -> Void
    @State private var hovering = false
    @State private var importing = false

    var body: some View {
        let content = Group {
            switch block.kind {
            case .heading: TextBlock(block: block, heading: true)
            case .text: TextBlock(block: block, heading: false)
            case .tasks: TasksBlock(space: space)
            case .content: RetiredBlock(text: "Content boards are gone. Your posts are in Tasks (Content filter) and on the canvas.", block: block)
            case .note: NoteBlock(block: block, space: space, open: openNote)
            case .link: LinkBlock(block: block)
            case .image: ImageBlock(block: block, space: space)
            case .timer: TimerBlock(block: block)
            case .stopwatch: StopwatchBlock()
            case .table: TableBlock(block: block, space: space, importing: $importing)
            case .file: FileBlock(block: block, space: space)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if block.kind == .heading || block.kind == .text { content } else { content.contextMenu { options } }
        }
        .overlay(alignment: .topTrailing) {
            Menu { options } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .offset(x: 34, y: block.kind == .heading ? 10 : 4)
                .opacity(hovering ? 1 : 0)
                .help("Block options")
                .accessibilityLabel("\(block.kind.title) options")
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var options: some View {
        if block.kind == .table {
            Button("Import CSV…", systemImage: "square.and.arrow.down") { importing = true }
            Button("Copy as CSV", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(SpaceTable.csv(columns: block.data.columns ?? [], rows: model.tableRows[block.id] ?? []), forType: .string)
            }
            Divider()
        }
        Button("Move Up", systemImage: "arrow.up") { Task { await model.move(block, by: -1) } }
        Button("Move Down", systemImage: "arrow.down") { Task { await model.move(block, by: 1) } }
        Divider()
        Button("Delete \(block.kind.title)", systemImage: "trash", role: .destructive) { Task { await model.delete(block) } }
    }
}

/// A heading or a paragraph, edited in place; saved when you press Return or click away.
private struct TextBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let heading: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(heading ? "Heading" : "Write something", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(heading ? .title2.bold() : .body)
            .padding(.top, heading ? 8 : 0)
            .focused($focused)
            .onAppear { text = block.data.text ?? "" }
            .onChange(of: focused) { _, now in if !now { save() } }
            .onSubmit(save)
            .onDisappear(perform: save) // switching to Canvas doesn't take focus, so save on the way out too
    }

    private func save() {
        var changed = block
        changed.data.text = String(String.UnicodeScalarView(text.unicodeScalars.prefix(10_000)))
        Task { await model.update(changed) }
    }
}

/// This Space's tasks, open first; tick or add them here, the same tasks as everywhere else.
private struct TasksBlock: View {
    @Environment(AppModel.self) private var model
    let space: Space
    @State private var newTask = ""

    var body: some View {
        let tasks = model.items.filter { $0.type == .task && $0.spaceID == space.id && $0.status != .archived }
            .sorted { ($0.status == .done ? 1 : 0, $0.dueAt ?? .distantFuture) < ($1.status == .done ? 1 : 0, $1.dueAt ?? .distantFuture) }
        BlockCard(title: "Tasks", symbol: "checklist") {
            if tasks.isEmpty { Text("No tasks in this Space yet.").foregroundStyle(.secondary) }
            ForEach(tasks) { TaskRow(task: $0, showsSpace: false) }
            AddField(placeholder: "Add a task", text: $newTask) {
                let title = newTask.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return }
                newTask = ""
                _ = model.create(.task, title: title, space: space.id)
            }
        }
    }
}

/// A block kind Blink no longer offers: a short note and a way to clear it off the page.
private struct RetiredBlock: View {
    @Environment(AppModel.self) private var model
    let text: String
    let block: SpaceBlock

    var body: some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Remove") { Task { await model.delete(block) } }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 8))
    }
}

/// One of the owner's notes, shown here; open it in Notes to edit.
private struct NoteBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    let open: (String) -> Void

    var body: some View {
        if let id = block.data.ref, let note = model.notes.first(where: { $0.id == id }) {
            Button { open(note.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(note.title.isEmpty ? "Untitled note" : note.title, systemImage: "note.text").font(.headline)
                    if !note.body.isEmpty { Text(note.body).lineLimit(6).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Open in Notes")
        } else {
            let here = model.notes.filter { $0.spaceID == space.id }, others = model.notes.filter { $0.spaceID != space.id }
            Menu("Choose a Note") {
                if !here.isEmpty { Section("In this Space") { ForEach(here) { pick($0) } } }
                if !others.isEmpty { Section("Other notes") { ForEach(others.prefix(30)) { pick($0) } } }
            }
            .fixedSize()
        }
    }

    private func pick(_ note: BlinkItem) -> some View {
        Button(note.title.isEmpty ? "Untitled note" : note.title) {
            var changed = block
            changed.data.ref = note.id
            Task { await model.update(changed) }
        }
    }
}

/// A web page: paste its address; the title is read from the page. Click to open it.
private struct LinkBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    @State private var typed = ""
    @State private var problem: String?

    var body: some View {
        if let address = block.data.url, let url = URL(string: address) {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Color.accentColor).frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 7)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.data.text ?? address).lineLimit(1)
                        Text(url.host()?.replacingOccurrences(of: "www.", with: "") ?? address).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(address)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Paste a link, e.g. blinkk.app", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private func save() {
        guard let address = SpaceNode.webAddress(typed) else {
            problem = "That isn't a web address."
            return
        }
        problem = nil
        Task {
            var changed = block
            changed.data.url = address
            changed.data.text = await AppModel.pageTitle(address).map { String($0.prefix(200)) }
            await model.update(changed)
        }
    }
}

/// A picture, stored on the owner's server like canvas pictures.
private struct ImageBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    @State private var picking = false

    var body: some View {
        Group {
            if let path = block.data.ref {
                if let image = model.canvasImages[path] {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 460, alignment: .leading)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityLabel("Picture")
                } else {
                    ProgressView().controlSize(.small).task { await model.loadCanvasImage(path) }
                }
            } else {
                Button("Choose Picture…", systemImage: "photo") { picking = true }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
            guard let file = try? result.get() else { return }
            Task {
                guard let path = await model.uploadBlockImage(from: file, in: space) else { return }
                var changed = block
                changed.data.ref = path
                await model.update(changed)
            }
        }
    }
}

/// Counts down from a few minutes; a sound when it's done. Runs while the page is open.
private struct TimerBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    @State private var endsAt: Date?
    @State private var leftWhenPaused: TimeInterval?

    var body: some View {
        let minutes = block.data.minutes ?? 25
        BlockCard(title: "Timer", symbol: "timer") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = endsAt.map { max(0, $0.timeIntervalSince(context.date)) } ?? leftWhenPaused ?? Double(minutes * 60)
                HStack(spacing: 14) {
                    Text(Self.clock(left)).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("\(Int(left) / 60) minutes \(Int(left) % 60) seconds left")
                    Spacer()
                    if endsAt == nil {
                        Stepper("\(minutes) min", value: Binding(get: { minutes }, set: { new in
                            var changed = block
                            changed.data.minutes = min(max(new, 1), 180)
                            leftWhenPaused = nil
                            Task { await model.update(changed) }
                        }), in: 1...180).fixedSize()
                        Button(leftWhenPaused == nil ? "Start" : "Resume") { endsAt = .now.addingTimeInterval(leftWhenPaused ?? Double(minutes * 60)) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pause") { leftWhenPaused = left; endsAt = nil }
                    }
                    Button("Reset") { endsAt = nil; leftWhenPaused = nil }.disabled(endsAt == nil && leftWhenPaused == nil)
                }
                .onChange(of: left <= 0) { _, done in
                    if done, endsAt != nil { endsAt = nil; leftWhenPaused = nil; NSSound(named: "Glass")?.play() }
                }
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Times something: start, stop, carry on, reset. Runs while the page is open.
private struct StopwatchBlock: View {
    @State private var startedAt: Date?
    @State private var banked: TimeInterval = 0

    var body: some View {
        BlockCard(title: "Stopwatch", symbol: "stopwatch") {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let total = banked + (startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
                HStack(spacing: 14) {
                    Text(Self.clock(total)).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    Spacer()
                    if startedAt == nil {
                        Button(banked == 0 ? "Start" : "Carry On") { startedAt = .now }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Stop") { banked = total; startedAt = nil }
                    }
                    Button("Reset") { startedAt = nil; banked = 0 }.disabled(startedAt == nil && banked == 0)
                }
            }
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let tenths = Int(t * 10)
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}

/// A document or picture kept in the Space. Its text (PDFs, Word) feeds bulk mails made here, and it can be attached.
private struct FileBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    @State private var picking = false

    var body: some View {
        Group {
            if block.data.ref != nil {
                HStack(spacing: 10) {
                    Image(systemName: (block.data.type ?? "").hasPrefix("image/") ? "photo" : "doc.richtext").font(.title2)
                        .foregroundStyle(Color.accentColor).frame(width: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.data.text ?? "File").lineLimit(1)
                        Text([block.data.size.map { $0.formatted(.byteCount(style: .file)) }, block.data.body == nil ? nil : "text read"].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let body = block.data.body { Text(body).font(.caption).foregroundStyle(.tertiary).lineLimit(2) }
                    }
                    Spacer()
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
            } else {
                Button("Choose File…", systemImage: "doc.badge.plus") { picking = true }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: MailAttachment.types.keys.compactMap { UTType(filenameExtension: $0) }) { result in
            guard let file = try? result.get() else { return }
            Task { await model.addFile(file, to: space, into: block) }
        }
    }
}

/// The frame shared by blocks that show a list or a tool: a small title, then the content.
private struct BlockCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
