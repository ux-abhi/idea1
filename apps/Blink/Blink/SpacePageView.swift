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
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: current.icon)
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.system(current.color).gradient, in: .rect(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title).font(.largeTitle.bold())
                        if !current.goal.isEmpty { Text(current.goal).foregroundStyle(.secondary) }
                    }
                }
                .padding(.bottom, 8)
                if blocks.isEmpty {
                    Text("This page is empty. Type / below to add a heading, a task list, a content board, a link, a timer and more.")
                        .foregroundStyle(.secondary)
                }
                ForEach(blocks) { block in
                    BlockRow(block: block, space: current, openNote: openNote, openPost: { openPost = $0 })
                }
                AddBlockLine(space: current, after: blocks.last)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 76)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topTrailing) {
            Button("Blocks", systemImage: showPanel ? "sidebar.right" : "plus") { showPanel.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
                .help(showPanel ? "Hide the blocks panel" : "Add a block")
                .padding(16)
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

/// The side panel: every block, to add at the end of the page.
private struct BlockPanel: View {
    let add: (SpaceBlock.Kind) -> Void

    var body: some View {
        List {
            Section("Add a block") {
                ForEach(SpaceBlock.Kind.allCases, id: \.self) { kind in
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
        return SpaceBlock.Kind.allCases.filter { query.isEmpty || $0.title.lowercased().contains(query) || $0.rawValue.contains(query) }
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

/// One block with its ⋯ menu (move, delete) on the left, shown on hover.
private struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    let openNote: (String) -> Void
    let openPost: (String) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Menu {
                Button("Move Up", systemImage: "arrow.up") { Task { await model.move(block, by: -1) } }
                Button("Move Down", systemImage: "arrow.down") { Task { await model.move(block, by: 1) } }
                Divider()
                Button("Delete \(block.kind.title)", systemImage: "trash", role: .destructive) { Task { await model.delete(block) } }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovering ? 1 : 0.25)
                .padding(.top, block.kind == .heading ? 8 : 3)
                .help("Block options")
                .accessibilityLabel("\(block.kind.title) options")
            Group {
                switch block.kind {
                case .heading: TextBlock(block: block, heading: true)
                case .text: TextBlock(block: block, heading: false)
                case .tasks: TasksBlock(space: space)
                case .content: ContentBoardBlock(space: space, open: openPost)
                case .note: NoteBlock(block: block, space: space, open: openNote)
                case .link: LinkBlock(block: block)
                case .image: ImageBlock(block: block, space: space)
                case .timer: TimerBlock(block: block)
                case .stopwatch: StopwatchBlock()
                case .table: TableBlock(block: block, space: space)
                case .file: FileBlock(block: block, space: space)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering = $0 }
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

/// This Space's posts by stage: Ideas, Drafts, Ready, Posted. Click one to open it; add a post written by hand.
private struct ContentBoardBlock: View {
    @Environment(AppModel.self) private var model
    let space: Space
    let open: (String) -> Void
    @State private var newPost = ""
    @AppStorage("contentBoard.platform") private var platform = ContentPiece.Platform.linkedin.rawValue

    private static let stages: [(String, [ContentPiece.Status])] = [("Ideas", [.idea]), ("Drafts", [.drafted]), ("Ready", [.approved]), ("Posted", [.published])]

    var body: some View {
        let posts = model.content.filter { $0.spaceID == space.id && $0.status != .archived }
        BlockCard(title: "Content", symbol: "square.grid.3x2") {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Self.stages, id: \.0) { stage in
                    let column = posts.filter { stage.1.contains($0.status) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(stage.0) · \(column.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(column) { post in
                            Button { open(post.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(post.platform.short).font(.caption2.weight(.bold)).foregroundStyle(.purple)
                                    Text(post.hook.isEmpty ? post.idea : post.hook).font(.callout).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(Color.purple.opacity(0.08), in: .rect(cornerRadius: 8))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            HStack {
                AddField(placeholder: "New post, written by you: type it, Return saves", text: $newPost) {
                    let text = newPost.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, let chosen = ContentPiece.Platform(rawValue: platform) else { return }
                    newPost = ""
                    Task { _ = await model.writePost(text, platforms: [chosen], space: space.id) }
                }
                Picker("Platform", selection: $platform) {
                    ForEach(ContentPiece.Platform.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
            }
        }
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

/// A table: typed columns, rows edited in place, CSV in and out, and "Bulk Mail…" for a table with an email column.
/// Rows that went out in a bulk mail show its status in a last, read-only column.
private struct TableBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    @State private var importing = false
    @State private var mailing = false
    private static let width: CGFloat = 170

    var body: some View {
        let columns = block.data.columns ?? []
        let rows = model.tableRows[block.id] ?? []
        let mailed = rows.contains { model.rowMailStatus[$0.id] != nil }
        VStack(alignment: .leading, spacing: 8) {
            if columns.isEmpty {
                HStack {
                    Button("Start with Name and Email") {
                        Task { await model.setColumns([SpaceColumn(name: "Name"), SpaceColumn(name: "Email", kind: .email), SpaceColumn(name: "Tags", kind: .tags)], of: block) }
                    }
                    Button("Import CSV…") { importing = true }
                }
            } else {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(columns) { column in ColumnHeader(column: column, block: block, width: Self.width) }
                            if mailed { Text("Mail").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading).padding(.horizontal, 6) }
                            Button("Add Column", systemImage: "plus") {
                                Task { await model.setColumns(columns + [SpaceColumn(name: "Column \(columns.count + 1)")], of: block) }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).padding(.horizontal, 6)
                            .disabled(columns.count >= SpaceTable.columnLimit)
                        }
                        .padding(.vertical, 6)
                        Divider()
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                HStack(spacing: 0) {
                                    ForEach(columns) { column in CellField(row: row, column: column).frame(width: Self.width) }
                                    if mailed {
                                        Text(model.rowMailStatus[row.id].map(Self.status) ?? "").font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 90, alignment: .leading).padding(.horizontal, 6)
                                    }
                                }
                                .contextMenu { Button("Delete Row", systemImage: "trash", role: .destructive) { Task { await model.delete(row) } } }
                                Divider()
                            }
                        }
                    }
                }
                HStack {
                    Button("New Row", systemImage: "plus") { Task { await model.addRow(to: block) } }
                    Button("Import CSV…") { importing = true }
                    Button("Copy as CSV") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpaceTable.csv(columns: columns, rows: rows), forType: .string)
                    }
                    Spacer()
                    if columns.contains(where: { $0.kind == .email }) {
                        Button("Bulk Mail…", systemImage: "envelope.stack") { mailing = true }
                            .help("A personal mail to the people in this table, or the ones with a tag")
                    }
                }
                .buttonStyle(.borderless)
                Text("Right-click a row to delete it. \(rows.count) of \(SpaceTable.rowLimit) rows.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .task(id: block.id) { await model.loadRows(block) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            guard let file = try? result.get() else { return }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
            Task { await model.importCSV(String(text.prefix(4_000_000)), into: block) }
        }
        .sheet(isPresented: $mailing) { NewCampaignSheet(space: space, table: block) { _ in } }
    }

    static func status(_ status: MailRecipient.Status) -> String {
        switch status {
        case .new, .written, .skipped: "Not sent"
        case .approved: "Approved"
        case .inDrafts: "In Drafts"
        case .sent: "Sent"
        case .failed: "Failed"
        case .bounced: "Bounced"
        case .replied: "Replied"
        }
    }
}

/// A column's name (edited in place) and a menu for its type and removal.
private struct ColumnHeader: View {
    @Environment(AppModel.self) private var model
    let column: SpaceColumn
    let block: SpaceBlock
    let width: CGFloat
    @State private var name = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("Column", text: $name).textFieldStyle(.plain).font(.caption.weight(.semibold))
                .onSubmit(save).onAppear { name = column.name }
                .accessibilityLabel("Column name")
            Menu {
                Picker("Type", selection: Binding(get: { column.kind }, set: { kind in change { $0.kind = kind } })) {
                    ForEach(SpaceColumn.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
                Button("Delete Column", systemImage: "trash", role: .destructive) {
                    Task { await model.setColumns((block.data.columns ?? []).filter { $0.id != column.id }, of: block) }
                }
            } label: { Image(systemName: Self.symbol(column.kind)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("\(column.kind.title) column")
                .accessibilityLabel("\(column.name) column options")
        }
        .padding(.horizontal, 6)
        .frame(width: width, alignment: .leading)
    }

    static func symbol(_ kind: SpaceColumn.Kind) -> String {
        switch kind {
        case .text: "textformat"
        case .email: "envelope"
        case .link: "link"
        case .tags: "number"
        }
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != column.name else { name = column.name; return }
        change { $0.name = String(clean.prefix(60)) }
    }

    private func change(_ edit: (inout SpaceColumn) -> Void) {
        var columns = block.data.columns ?? []
        guard let i = columns.firstIndex(where: { $0.id == column.id }) else { return }
        edit(&columns[i])
        Task { await model.setColumns(columns, of: block) }
    }
}

/// One cell, edited in place; saved on Return, when you click away, or when it leaves the screen.
private struct CellField: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let column: SpaceColumn
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text).textFieldStyle(.plain).focused($focused)
                .onAppear { text = row.cells[column.id] ?? "" }
                .onChange(of: row.cells[column.id]) { _, now in if !focused { text = now ?? "" } }
                .onChange(of: focused) { _, now in if !now { save() } }
                .onSubmit(save)
                .onDisappear(perform: save)
                .accessibilityLabel(column.name)
            if column.kind == .link, let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)"), !text.isEmpty, url.host() != nil {
                Button("Open", systemImage: "arrow.up.forward") { NSWorkspace.shared.open(url) }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
    }

    private func save() {
        let clean = String(text.trimmingCharacters(in: .whitespaces).prefix(SpaceTable.cellLimit))
        guard clean != (row.cells[column.id] ?? "") else { return }
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        changed.cells[column.id] = clean.isEmpty ? nil : clean
        Task { await model.update(changed) }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}
#endif
