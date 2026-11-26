// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// A table block as a small database (ADR-0004): a name, saved views (Table or Board) as tabs, a toolbar with filter,
/// sort, search and New, and cards that open in a sheet. Every view shows the same rows; a view only changes how.
struct TableBlock: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let space: Space
    @Binding var importing: Bool
    @State private var name = ""
    @State private var search = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var filtering = false
    @State private var sorting = false
    @State private var choosingProperties = false
    @State private var askingAI = false
    @State private var pasting = false
    @State private var suggesting = false
    @State private var aiText = ""
    @State private var openRow: String?
    @State private var editingOptions: SpaceColumn?

    private var current: SpaceBlock { model.spaceBlocks[block.spaceID]?.first { $0.id == block.id } ?? block }
    private var columns: [SpaceColumn] { current.data.columns ?? [] }
    private var views: [SpaceTableView] { current.data.views?.isEmpty == false ? current.data.views! : [SpaceTableView(id: "table", name: "Table", kind: .table)] }
    private var active: SpaceTableView { views.first { $0.id == current.data.activeView } ?? views[0] }

    var body: some View {
        let rows = SpaceTable.apply(active, columns: columns, rows: model.tableRows[block.id] ?? [], search: search)
        VStack(alignment: .leading, spacing: 12) {
            TextField("Untitled", text: $name).textFieldStyle(.plain).font(.title2.bold())
                .onSubmit(saveName).onAppear { name = current.data.text ?? "" }.onDisappear(perform: saveName)
                .accessibilityLabel("Table name")
            toolbar
            Divider()
            let shown = columns.filter { !(active.hidden ?? []).contains($0.id) }
            switch active.kind {
            case .board:
                BoardView(block: current, columns: columns, shown: shown, view: active, rows: rows, open: { openRow = $0 }, update: update, editOptions: { editingOptions = $0 })
            case .calendar:
                CalendarBoard(block: current, columns: columns, view: active, rows: rows, open: { openRow = $0 }, update: update)
            case .table:
                GridView(block: current, columns: shown, view: active, rows: rows, open: { openRow = $0 }, editOptions: { editingOptions = $0 })
            }
        }
        .task(id: block.id) {
            await model.loadRows(block)
            // A new table starts like a spreadsheet: a Name, a Status and a few empty rows to type into.
            if block.data.columns == nil {
                await model.setColumns([SpaceColumn(name: "Name"), Self.statusColumn()], of: block)
                for _ in 0..<3 { await model.addRow(to: block) }
            }
        }
        .sheet(isPresented: Binding(get: { openRow != nil }, set: { if !$0 { openRow = nil } })) {
            if let openRow { CardSheet(block: current, rowID: openRow, editOptions: { editingOptions = $0 }) }
        }
        .sheet(item: $editingOptions) { column in OptionsEditor(block: current, column: column) }
        .sheet(isPresented: $askingAI) { AskTableSheet(columns: columns, initial: aiText, apply: apply) }
        .sheet(isPresented: $pasting) { PasteRowsSheet(block: current, columns: columns, initial: aiText) }
        .sheet(isPresented: $suggesting) { PasteRowsSheet(block: current, columns: columns, initial: aiText, ideas: true) }
        // From the page's AI bar, while this table is selected.
        .onChange(of: model.tableAIRequest) { _, request in
            guard let request, request.blockID == block.id else { return }
            aiText = request.text
            switch request.kind {
            case .paste: pasting = true
            case .ideas: suggesting = true
            case .change: askingAI = true
            }
            model.tableAIRequest = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            guard let file = try? result.get() else { return }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
            Task { await model.importCSV(String(text.prefix(4_000_000)), into: block) }
        }
    }

    /// View tabs on the left; filter, sort, search and New on the right.
    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(views) { view in
                Button { setActive(view.id) } label: {
                    Label(view.name, systemImage: Self.symbol(view.kind))
                        .font(.callout.weight(view.id == active.id ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(view.id == active.id ? Color.primary.opacity(0.08) : .clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(view.id == active.id ? .primary : .secondary)
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") { rename(view) }
                    if views.count > 1 { Button("Delete View", systemImage: "trash", role: .destructive) { deleteView(view) } }
                }
            }
            Menu {
                Button("Table", systemImage: "tablecells") { addView(.table) }
                Button("Board", systemImage: "rectangle.split.3x1") { addView(.board) }
                Button("Calendar", systemImage: "calendar") { addView(.calendar) }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Add a view").accessibilityLabel("Add a view")
            Spacer()
            if searching {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 160)
                    .focused($searchFocused).onAppear { searchFocused = true } // type straight away
                    .onExitCommand { search = ""; searching = false }
            }
            Group {
                Button { filtering = true } label: {
                    Image(systemName: active.filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .foregroundStyle(active.filters.isEmpty ? .secondary : Color.accentColor)
                .help(active.filters.isEmpty ? "Filter" : "\(active.filters.count) filters")
                .accessibilityLabel("Filter")
                .popover(isPresented: $filtering, arrowEdge: .bottom) { FilterEditor(columns: columns, view: active, update: update) }
                Button { sorting = true } label: { Image(systemName: "arrow.up.arrow.down") }
                    .foregroundStyle(active.sortColumn != nil ? Color.accentColor : .secondary)
                    .help(active.sortColumn.flatMap { id in columns.first { $0.id == id }?.name }.map { "Sorted by \($0)" } ?? "Sort")
                    .accessibilityLabel("Sort")
                    .popover(isPresented: $sorting, arrowEdge: .bottom) { SortEditor(columns: columns, view: active, update: update) }
                Button { searching.toggle(); if !searching { search = "" } } label: { Image(systemName: "magnifyingglass") }
                    .help("Search").accessibilityLabel("Search")
                if active.kind != .calendar { // a calendar shows only titles
                    Button { choosingProperties = true } label: { Image(systemName: "slider.horizontal.3") }
                        .help("Properties: choose what this view shows").accessibilityLabel("Properties")
                        .popover(isPresented: $choosingProperties, arrowEdge: .bottom) { PropertiesEditor(columns: columns, view: active, update: update) }
                }
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("New") { Task { openRow = await newRow(in: nil) } }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(columns.isEmpty)
        }
    }

    // MARK: Changes

    /// The AI's plan, after the owner pressed Apply: columns first, then the new view, shown at once.
    private func apply(_ plan: TablePlan) {
        Task {
            let changed = plan.applied(to: columns)
            if changed != columns { await model.setColumns(changed, of: current) }
            if let view = plan.view(in: changed) { save { data in data.views = (data.views ?? []) + [view]; data.activeView = view.id } }
        }
    }

    private func saveName() {
        let clean = String(name.trimmingCharacters(in: .whitespaces).prefix(120))
        guard clean != (current.data.text ?? "") else { return }
        var changed = current
        changed.data.text = clean.isEmpty ? nil : clean
        Task { await model.update(changed) }
    }

    private func save(_ edit: (inout SpaceBlock.Data) -> Void) {
        var changed = current
        if changed.data.views?.isEmpty != false { changed.data.views = views } // the default view becomes a saved one
        edit(&changed.data)
        Task { await model.update(changed) }
    }

    private func update(_ view: SpaceTableView) {
        save { data in
            if let i = data.views?.firstIndex(where: { $0.id == view.id }) { data.views?[i] = view }
        }
    }

    private func setActive(_ id: String) { save { $0.activeView = id } }

    private func addView(_ kind: SpaceTableView.Kind) {
        let view = SpaceTableView(name: kind.rawValue.capitalized, kind: kind,
                                  groupBy: columns.first { $0.kind == (kind == .calendar ? .date : .category) }?.id)
        save { data in data.views = (data.views ?? []) + [view]; data.activeView = view.id }
    }

    private func deleteView(_ view: SpaceTableView) {
        save { data in
            data.views?.removeAll { $0.id == view.id }
            if data.activeView == view.id { data.activeView = data.views?.first?.id }
        }
    }

    private func rename(_ view: SpaceTableView) {
        let alert = NSAlert()
        alert.messageText = "Rename View"
        let field = NSTextField(string: view.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let clean = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        var changed = view
        changed.name = String(clean.prefix(40))
        update(changed)
    }

    /// A new row (on a board, in the column it was added to); returns its id so it opens.
    private func newRow(in option: String?) async -> String? {
        let before = Set((model.tableRows[block.id] ?? []).map(\.id))
        await model.addRow(to: current)
        guard var row = (model.tableRows[block.id] ?? []).first(where: { !before.contains($0.id) }) else { return nil }
        if let option, let group = active.groupBy ?? columns.first(where: { $0.kind == .category })?.id {
            row.cells[group] = option
            await model.update(row)
        }
        return row.id
    }

    static func statusColumn() -> SpaceColumn {
        SpaceColumn(name: "Status", kind: .category, options: [SpaceOption(name: "Not started", color: "gray"),
                                                               SpaceOption(name: "In progress", color: "blue"),
                                                               SpaceOption(name: "Done", color: "green")])
    }

    static func symbol(_ kind: SpaceColumn.Kind) -> String {
        switch kind {
        case .text: "textformat"
        case .category: "chevron.down.circle"
        case .tags: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .email: "envelope"
        case .link: "link"
        case .file: "paperclip"
        }
    }

    static func symbol(_ kind: SpaceTableView.Kind) -> String {
        switch kind {
        case .table: "tablecells"
        case .board: "rectangle.split.3x1"
        case .calendar: "calendar"
        }
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

// MARK: Table view

/// Rows and columns, edited in place, with typed cells (checkboxes, category chips, dates).
private struct GridView: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let columns: [SpaceColumn]
    let view: SpaceTableView
    let rows: [SpaceRow]
    let open: (String) -> Void
    let editOptions: (SpaceColumn) -> Void
    private let height: CGFloat = 36

    var body: some View {
        let mailed = rows.contains { model.rowMailStatus[$0.id] != nil }
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: GridView.gutter, height: height)
                    ForEach(columns) { column in
                        ColumnHeader(block: block, column: column, editOptions: editOptions)
                            .frame(width: GridView.width(column), height: height).overlay(alignment: .leading) { GridLine() }
                    }
                    if mailed {
                        Label("Mail", systemImage: "envelope").font(.callout).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).frame(width: 110, height: height, alignment: .leading).overlay(alignment: .leading) { GridLine() }
                    }
                    Menu {
                        ForEach(SpaceColumn.Kind.allCases, id: \.self) { kind in
                            Button(kind.title, systemImage: TableBlock.symbol(kind)) { addProperty(kind) }
                        }
                    } label: { Image(systemName: "plus") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.horizontal, 12)
                        .frame(height: height).overlay(alignment: .leading) { GridLine() }
                        .disabled(columns.count >= SpaceTable.columnLimit)
                        .help("Add a property").accessibilityLabel("Add a property")
                }
                .background(Color.primary.opacity(0.04))
                Rectangle().fill(.quaternary).frame(height: 1)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        GridRow(block: block, row: row, columns: columns, mailed: mailed ? model.rowMailStatus[row.id].map(TableBlock.status) ?? "" : nil,
                                height: height, open: open, editOptions: editOptions)
                        Rectangle().fill(.quaternary).frame(height: 1)
                    }
                }
                Button { Task { await model.addRow(to: block) } } label: {
                    Label("New", systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).frame(height: height).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(columns.isEmpty)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .scrollIndicators(.never) // a wide table still scrolls sideways with a swipe
        // The border goes around what's visible, so the box is always closed, however wide the table.
        .frame(maxWidth: GridView.gutter + columns.reduce(0) { $0 + GridView.width($1) } + (mailed ? 110 : 0) + 44, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            if rows.isEmpty, !(model.tableRows[block.id] ?? []).isEmpty {
                Text("No rows match. Change the filter or search.").foregroundStyle(.secondary).padding(.top, 60)
            }
        }
    }

    static func width(_ column: SpaceColumn) -> CGFloat { CGFloat(column.width ?? 180) }
    /// The space left of each row for its Open button and ⋯ menu.
    static let gutter: CGFloat = 56

    private func addProperty(_ kind: SpaceColumn.Kind) {
        let all = block.data.columns ?? []
        let column = kind == .category ? SpaceColumn(name: "Category", kind: .category, options: [])
            : SpaceColumn(name: kind == .text ? "Column \(all.count + 1)" : kind.title, kind: kind)
        Task { await model.setColumns(all + [column], of: block) }
    }
}

/// The thin line between two columns.
private struct GridLine: View {
    var body: some View { Rectangle().fill(.quaternary).frame(width: 1) }
}

private struct GridRow: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let row: SpaceRow
    let columns: [SpaceColumn]
    let mailed: String?
    let height: CGFloat
    let open: (String) -> Void
    let editOptions: (SpaceColumn) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            // On hover: open the row as a card, or its menu (show on canvas, duplicate, delete).
            HStack(spacing: 2) {
                Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { open(row.id) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Open as a card")
                Menu { actions } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20).contentShape(.rect) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Row options").accessibilityLabel("Row options")
            }
            .foregroundStyle(.secondary)
            .frame(width: GridView.gutter, height: height).opacity(hovering ? 1 : 0)
            ForEach(columns) { column in
                CellEditor(row: row, column: column, editOptions: editOptions).padding(.horizontal, 10)
                    .frame(width: GridView.width(column), height: height, alignment: .leading).overlay(alignment: .leading) { GridLine() }
            }
            if let mailed {
                Text(mailed).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                    .frame(width: 110, height: height, alignment: .leading).overlay(alignment: .leading) { GridLine() }
            }
        }
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { open(row.id) }
        if let space = model.spaces.first(where: { $0.id == block.spaceID }) {
            Button("Show on Canvas", systemImage: "rectangle.on.rectangle") { Task { await model.showOnCanvas(block, row: row, in: space) } }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { Task { _ = await model.addRows([row.cells], to: block) } }
        Divider()
        Button("Delete Row", systemImage: "trash", role: .destructive) { Task { await model.delete(row) } }
    }
}

/// A column's name and type: click to rename, change the type, edit a Category's options, or delete it.
private struct ColumnHeader: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let column: SpaceColumn
    let editOptions: (SpaceColumn) -> Void
    @State private var name = ""

    var body: some View {
        HStack(spacing: 6) {
            Menu { actions } label: { Image(systemName: TableBlock.symbol(column.kind)).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("\(column.kind.title): click to change")
                .accessibilityLabel("\(column.name) property options")
            TextField("Property", text: $name).textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary)
                .onSubmit(save).onAppear { name = column.name }.accessibilityLabel("Property name")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu { actions } // right-click anywhere on the header, not only its small icon
    }

    @ViewBuilder
    private var actions: some View {
        Picker("Type", selection: Binding(get: { column.kind }, set: { kind in change { $0.kind = kind; if kind == .category, $0.options == nil { $0.options = [] } } })) {
            ForEach(SpaceColumn.Kind.allCases, id: \.self) { Label($0.title, systemImage: TableBlock.symbol($0)).tag($0) }
        }
        if column.kind == .category { Button("Edit Options…", systemImage: "list.bullet") { editOptions(column) } }
        Picker("Width", selection: Binding(get: { column.width ?? 180 }, set: { w in change { $0.width = w == 180 ? nil : w } })) {
            ForEach(SpaceColumn.widths, id: \.value) { Text($0.name).tag($0.value) }
        }
        Divider()
        Button("Delete Property “\(column.name)”", systemImage: "trash", role: .destructive) { deleteColumn() }
    }

    /// Removes the column; Undo puts it back with every cell's value (the cells stay in the rows until then).
    private func deleteColumn() {
        let before = block.data.columns ?? []
        Task {
            await model.setColumns(before.filter { $0.id != column.id }, of: block)
            model.offerUndo("Deleted “\(column.name)”") { [weak model] in
                guard let model, var current = model.spaceBlocks[block.spaceID]?.first(where: { $0.id == block.id }) else { return }
                current.data.columns = before
                await model.update(current)
            }
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

// MARK: Cells

/// One value, edited by its kind: text, a checkbox, a category chip, a date.
private struct CellEditor: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let column: SpaceColumn
    let editOptions: (SpaceColumn) -> Void
    var large = false

    var body: some View {
        switch column.kind {
        case .checkbox:
            Toggle(column.name, isOn: Binding(get: { row.cells[column.id] == "true" }, set: { set($0 ? "true" : nil) }))
                .toggleStyle(.checkbox).labelsHidden()
        case .category:
            Menu {
                ForEach(column.options ?? []) { option in
                    Button { set(option.id) } label: { Text(option.name) }
                }
                if row.cells[column.id] != nil { Button("Clear") { set(nil) } }
                Divider()
                Button("Edit Options…") { editOptions(column) }
            } label: {
                if let option = column.options?.first(where: { $0.id == row.cells[column.id] }) {
                    Chip(option: option)
                } else {
                    Text(large ? "Empty" : "—").foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading).contentShape(.rect)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden) // keeps the chip's colour
            .accessibilityLabel("\(column.name): \(SpaceTable.display(row, column))")
        case .date:
            DateCell(row: row, column: column)
        case .file:
            FileCell(row: row, column: column)
        default:
            TextCell(row: row, column: column, large: large)
        }
    }

    private func set(_ value: String?) {
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        changed.cells[column.id] = value
        Task { await model.update(changed) }
    }
}

private struct TextCell: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let column: SpaceColumn
    var large = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(large ? "Empty" : "", text: $text, axis: large ? .vertical : .horizontal).textFieldStyle(.plain).focused($focused)
                .onAppear { text = row.cells[column.id] ?? "" }
                .onChange(of: row.cells[column.id]) { _, now in if !focused { text = now ?? "" } }
                .onChange(of: focused) { _, now in if !now { save() } }
                .onSubmit(save).onDisappear(perform: save)
                .accessibilityLabel(column.name)
            if column.kind == .link, !text.isEmpty, let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)"), url.host() != nil {
                Button("Open", systemImage: "arrow.up.forward") { NSWorkspace.shared.open(url) }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
    }

    private func save() {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SpaceTable.cellLimit))
        guard clean != (row.cells[column.id] ?? "") else { return }
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        changed.cells[column.id] = clean.isEmpty ? nil : clean
        Task { await model.update(changed) }
    }
}

/// A day as "2026-11-21", or with a time as "2026-11-21 15:00" (then the notch reminds you); empty until set, with Clear.
private struct DateCell: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let column: SpaceColumn

    var body: some View {
        let value = SpaceTable.when(row.cells[column.id] ?? "")
        HStack(spacing: 4) {
            if let value {
                DatePicker(column.name, selection: Binding(get: { value.date }, set: { set(SpaceTable.dateCell($0, timed: value.timed)) }),
                           displayedComponents: value.timed ? [.date, .hourAndMinute] : .date)
                    .labelsHidden().datePickerStyle(.field)
                Button(value.timed ? "Remove Time" : "Add Time", systemImage: value.timed ? "clock.badge.xmark" : "clock") {
                    // A new time starts at the next whole hour, so it's in the future when today.
                    let hour = Calendar.current.component(.hour, from: .now) + 1
                    let at = Calendar.current.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: value.date) ?? value.date
                    set(SpaceTable.dateCell(value.timed ? value.date : at, timed: !value.timed))
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.tertiary)
                .help(value.timed ? "Remove the time" : "Add a time: Blink reminds you in the notch")
                Button("Clear", systemImage: "xmark.circle.fill") { set(nil) }.labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.tertiary)
            } else {
                Button("Add date") { set(HabitDay.key(.now)) }.buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
    }

    private func set(_ value: String?) {
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        changed.cells[column.id] = value
        Task { await model.update(changed) }
    }
}

/// A file kept with the card: its name opens it; Remove deletes it.
private struct FileCell: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let column: SpaceColumn
    @State private var picking = false
    @State private var uploading = false

    var body: some View {
        HStack(spacing: 4) {
            if let file = SpaceTable.fileParts(row.cells[column.id] ?? "") {
                Button { Task { await model.openFile(file.path, name: file.name) } } label: {
                    Label(file.name, systemImage: "doc").lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.borderless).help("Open “\(file.name)”")
                Button("Remove File", systemImage: "xmark.circle.fill") { Task { await model.removeFile(from: row, column: column.id) } }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.tertiary).help("Remove and delete this file")
            } else if uploading {
                ProgressView().controlSize(.small).accessibilityLabel("Uploading")
            } else {
                Button("Add file") { picking = true }.buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: MailAttachment.types.keys.compactMap { UTType(filenameExtension: $0) }) { result in
            guard let file = try? result.get() else { return }
            Task { uploading = true; await model.attachFile(file, to: row, column: column.id); uploading = false }
        }
    }
}

/// A category option as a coloured chip.
private struct Chip: View {
    let option: SpaceOption

    var body: some View {
        let color = Color.system(option.color)
        Text(option.name).font(.callout.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2), in: .rect(cornerRadius: 6))
            .foregroundStyle(color.mix(with: .primary, by: 0.45)) // the option's colour, deep enough to read in light and dark
    }
}

// MARK: Board view

/// Cards in columns, one per option of a Category: drag a card to another column to change it.
private struct BoardView: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let columns: [SpaceColumn]
    /// What the cards show (the view's visible properties).
    let shown: [SpaceColumn]
    let view: SpaceTableView
    let rows: [SpaceRow]
    let open: (String) -> Void
    let update: (SpaceTableView) -> Void
    let editOptions: (SpaceColumn) -> Void

    var body: some View {
        let categories = columns.filter { $0.kind == .category }
        if let group = categories.first(where: { $0.id == view.groupBy }) ?? categories.first {
            VStack(alignment: .leading, spacing: 8) {
                if categories.count > 1 {
                    Picker("Group by", selection: Binding(get: { group.id }, set: { var v = view; v.groupBy = $0; update(v) })) {
                        ForEach(categories) { Text($0.name).tag($0.id) }
                    }
                    .fixedSize()
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        let lanes = SpaceTable.groups(rows, by: group)
                        ForEach(lanes, id: \.option?.id) { lane in
                            let hidden = lane.option.map { (view.hiddenGroups ?? []).contains($0.id) } ?? false
                            if !hidden, lane.option != nil || !lane.rows.isEmpty, !(view.hideEmpty == true && lane.rows.isEmpty) {
                                Lane(block: block, columns: shown, group: group, option: lane.option, rows: lane.rows, view: view,
                                     open: open, update: update)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Button { editOptions(group) } label: { Label("Add a column", systemImage: "plus").foregroundStyle(.secondary) }
                                .buttonStyle(.borderless)
                            // Hidden columns, to bring back.
                            ForEach(lanes.compactMap(\.option).filter { (view.hiddenGroups ?? []).contains($0.id) }) { option in
                                Button { var v = view; v.hiddenGroups?.removeAll { $0 == option.id }; update(v) } label: {
                                    HStack(spacing: 6) { Chip(option: option); Image(systemName: "eye").foregroundStyle(.secondary) }
                                }
                                .buttonStyle(.plain).help("Show “\(option.name)” again")
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("A board groups cards by a Category, like Status or Stage.").foregroundStyle(.secondary)
                Button("Add a Status Category") {
                    let status = TableBlock.statusColumn()
                    Task {
                        await model.setColumns(columns + [status], of: block)
                        var v = view; v.groupBy = status.id; update(v)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 20)
        }
    }
}

/// One board column: its option as a chip with the count, its cards, and New.
private struct Lane: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let columns: [SpaceColumn]
    let group: SpaceColumn
    let option: SpaceOption?
    let rows: [SpaceRow]
    let view: SpaceTableView
    let open: (String) -> Void
    let update: (SpaceTableView) -> Void
    @State private var targeted = false

    private var tint: Color { option.map { Color.system($0.color) } ?? .gray }
    private var colored: Bool { view.colorColumns ?? true }
    private var width: CGFloat { ["small": 220, "large": 330][view.cardSize ?? ""] ?? 270 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let option {
                    Menu {
                        Button("Rename…", systemImage: "pencil") { rename(option) }
                        Menu("Colour") {
                            ForEach(SpaceOption.colors, id: \.self) { color in Button(color.capitalized) { change(option) { $0.color = color } } }
                        }
                        Button("Move Left", systemImage: "arrow.left") { move(option, by: -1) }
                        Button("Move Right", systemImage: "arrow.right") { move(option, by: 1) }
                        Button("Hide Column", systemImage: "eye.slash") { var v = view; v.hiddenGroups = (v.hiddenGroups ?? []) + [option.id]; update(v) }
                        Divider()
                        Button("Delete “\(option.name)”", systemImage: "trash", role: .destructive) { delete(option) }
                    } label: { Chip(option: option) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize() // keeps the chip's colour
                        .help("Rename, recolour, move, hide or delete this column")
                } else {
                    Text("No \(group.name)").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
                Text("\(rows.count)").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(rows) { row in
                CardTile(row: row, columns: columns, group: group, tint: colored ? tint : .gray, size: view.cardSize ?? "medium",
                         showNote: view.showNotes ?? true)
                    .onTapGesture { open(row.id) }
                    .accessibilityAction { open(row.id) } // Space / VoiceOver open it too
                    .draggable(row.id)
                    .contextMenu {
                        if let space = model.spaces.first(where: { $0.id == block.spaceID }) {
                            Button("Show on Canvas", systemImage: "rectangle.on.rectangle") { Task { await model.showOnCanvas(block, row: row, in: space) } }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete(row) } }
                    }
            }
            Button {
                Task {
                    await model.addRow(to: block)
                    if let option, var row = model.tableRows[block.id]?.last { row.cells[group.id] = option.id; await model.update(row); open(row.id) }
                    else if let row = model.tableRows[block.id]?.last { open(row.id) }
                }
            } label: {
                Label("New", systemImage: "plus").font(.callout).foregroundStyle(tint)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.3)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: width, alignment: .top)
        .background((colored ? tint : Color.primary).opacity(targeted ? 0.16 : colored ? 0.07 : 0.03), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? tint.opacity(0.6) : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in
            // Dropping a card here gives it this column's option (or none, in the last column).
            for id in ids {
                guard var row = model.tableRows[block.id]?.first(where: { $0.id == id }) else { continue }
                row.cells[group.id] = option?.id
                Task { await model.update(row) }
            }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

extension Lane {
    /// Changes one option of the board's Category (its name or colour); every card in it follows.
    func change(_ option: SpaceOption, _ edit: (inout SpaceOption) -> Void) {
        var all = block.data.columns ?? []
        guard let c = all.firstIndex(where: { $0.id == group.id }), let o = all[c].options?.firstIndex(where: { $0.id == option.id }) else { return }
        edit(&all[c].options![o])
        Task { await model.setColumns(all, of: block) }
    }

    func rename(_ option: SpaceOption) {
        let alert = NSAlert()
        alert.messageText = "Rename “\(option.name)”"
        let field = NSTextField(string: option.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let clean = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { change(option) { $0.name = String(clean.prefix(40)) } }
    }

    /// Moves a board column left or right (the Category's option order).
    func move(_ option: SpaceOption, by step: Int) {
        var all = block.data.columns ?? []
        guard let c = all.firstIndex(where: { $0.id == group.id }), var options = all[c].options,
              let i = options.firstIndex(where: { $0.id == option.id }), options.indices.contains(i + step) else { return }
        options.swapAt(i, i + step)
        all[c].options = options
        Task { await model.setColumns(all, of: block) }
    }

    /// Removes the option; its cards move to "No …" (nothing is deleted with it).
    func delete(_ option: SpaceOption) {
        var all = block.data.columns ?? []
        guard let c = all.firstIndex(where: { $0.id == group.id }) else { return }
        let before = block.data.columns ?? []
        all[c].options?.removeAll { $0.id == option.id }
        Task {
            await model.setColumns(all, of: block)
            // The cards keep their value, so Undo brings the column and its cards back.
            model.offerUndo("Deleted “\(option.name)”") { [weak model] in
                guard let model, var current = model.spaceBlocks[block.spaceID]?.first(where: { $0.id == block.id }) else { return }
                current.data.columns = before
                await model.update(current)
            }
        }
    }
}

/// A card on the board: its title, then its other filled properties.
private struct CardTile: View {
    let row: SpaceRow
    let columns: [SpaceColumn]
    let group: SpaceColumn
    let tint: Color
    var size = "medium"
    var showNote = true

    var body: some View {
        let title = columns.first { $0.kind == .text }
        let small = size == "small"
        VStack(alignment: .leading, spacing: small ? 4 : 6) {
            Text(title.map { SpaceTable.display(row, $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled")
                .font(small ? .callout.weight(.semibold) : .headline).lineLimit(2)
            if showNote, !small, let note = row.cells[SpaceTable.noteKey], !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(size == "large" ? 6 : 3)
            }
            ForEach(columns.filter { $0.id != title?.id && $0.id != group.id && !SpaceTable.display(row, $0).isEmpty }.prefix(small ? 2 : 5)) { column in
                switch column.kind {
                case .category: if let option = column.options?.first(where: { $0.id == row.cells[column.id] }) { Chip(option: option) }
                case .checkbox: Label(column.name, systemImage: "checkmark.square.fill").font(.callout).foregroundStyle(.secondary)
                default: Text(SpaceTable.display(row, column)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(small ? 9 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 10))
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.3)))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Calendar

/// A month of cards placed by a Date property: drag a card to another day, + on a day adds one there.
private struct CalendarBoard: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let columns: [SpaceColumn]
    let view: SpaceTableView
    let rows: [SpaceRow]
    let open: (String) -> Void
    let update: (SpaceTableView) -> Void
    @State private var month = Date.now

    var body: some View {
        let dates = columns.filter { $0.kind == .date }
        if let date = dates.first(where: { $0.id == view.groupBy }) ?? dates.first {
            let calendar = Calendar.current
            let placed = SpaceTable.byDay(rows, column: date.id)
            let undated = rows.filter { SpaceTable.when($0.cells[date.id] ?? "") == nil }.count // empty, or text that isn't a day
            let weekdays = Array(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1)...] + calendar.shortWeekdaySymbols[..<(calendar.firstWeekday - 1)])
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                    if dates.count > 1 {
                        Picker("Dates from", selection: Binding(get: { date.id }, set: { var v = view; v.groupBy = $0; update(v) })) {
                            ForEach(dates) { Text($0.name).tag($0.id) }
                        }
                        .fixedSize()
                    }
                    Spacer()
                    if undated > 0 { Text("\(undated) without a date").font(.callout).foregroundStyle(.secondary) }
                    Button("Previous Month", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly)
                    Button("Today") { month = .now }
                    Button("Next Month", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    SwiftUI.GridRow {
                        ForEach(weekdays, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    }
                    let days = SpaceTable.monthDays(containing: month)
                    ForEach(0..<(days.count / 7), id: \.self) { week in
                        SwiftUI.GridRow {
                            ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                                DayCell(block: block, columns: columns, date: date, day: day,
                                        inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                        rows: placed[HabitDay.key(day)] ?? [], open: open)
                            }
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
                .clipShape(.rect(cornerRadius: 10))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("A calendar places cards by a Date, like Due or Publish on.").foregroundStyle(.secondary)
                Button("Add a Date Property") {
                    let due = SpaceColumn(name: "Date", kind: .date)
                    Task {
                        await model.setColumns(columns + [due], of: block)
                        var v = view; v.groupBy = due.id; update(v)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 20)
        }
    }

    private func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }
}

/// One day: its number, up to three cards, and the rest behind "N more".
private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let block: SpaceBlock
    let columns: [SpaceColumn]
    let date: SpaceColumn
    let day: Date
    let inMonth: Bool
    let rows: [SpaceRow]
    let open: (String) -> Void
    @State private var hovering = false
    @State private var targeted = false
    @State private var showingAll = false

    var body: some View {
        let today = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(today ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(today ? AnyShapeStyle(.white) : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(today ? Color.accentColor : .clear, in: .circle)
                Spacer()
                if hovering {
                    Button("New card on \(day.formatted(date: .abbreviated, time: .omitted))", systemImage: "plus", action: add)
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            ForEach(rows.prefix(3)) { row in pill(row) }
            if rows.count > 3 {
                Button("\(rows.count - 3) more") { showingAll = true }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                    .popover(isPresented: $showingAll, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.formatted(date: .complete, time: .omitted)).font(.headline).padding(.bottom, 4)
                            ForEach(rows) { row in pill(row) }
                        }
                        .padding(12).frame(width: 240)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(targeted ? Color.accentColor.opacity(0.12) : inMonth ? .clear : Color.primary.opacity(0.03))
        .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .dropDestination(for: String.self) { ids, _ in
            let moved = ids.compactMap { id in model.tableRows[block.id]?.first { $0.id == id } } // only this table's cards
            for var row in moved {
                let raw = row.cells[date.id] ?? ""
                row.cells[date.id] = HabitDay.key(day) + (SpaceTable.when(raw)?.timed == true ? String(raw.dropFirst(10)) : "") // keeps its time
                Task { await model.update(row) }
            }
            return !moved.isEmpty
        } isTargeted: { targeted = $0 }
    }

    /// A card as one line, tinted by its first Category (its status, usually).
    private func pill(_ row: SpaceRow) -> some View {
        let title = columns.first { $0.kind == .text }.map { SpaceTable.display(row, $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        let option = columns.first { $0.kind == .category }.flatMap { c in c.options?.first { $0.id == row.cells[c.id] } }
        let tint = option.map { Color.system($0.color) } ?? .gray
        let at = SpaceTable.when(row.cells[date.id] ?? "")
        return Text(at?.timed == true ? "\(at!.date.formatted(date: .omitted, time: .shortened)) \(title)" : title).font(.caption).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.16), in: .rect(cornerRadius: 5))
            .contentShape(.rect)
            .onTapGesture { open(row.id) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel([title, option?.name].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(row.id) }
            .draggable(row.id)
    }

    private func add() {
        Task {
            let before = Set((model.tableRows[block.id] ?? []).map(\.id))
            await model.addRow(to: block)
            guard var row = model.tableRows[block.id]?.first(where: { !before.contains($0.id) }) else { return }
            row.cells[date.id] = HabitDay.key(day)
            await model.update(row)
            open(row.id)
        }
    }
}

// MARK: Card

/// A row opened as a card: every property, edited in place.
struct CardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: SpaceBlock
    let rowID: String
    let editOptions: (SpaceColumn) -> Void

    var body: some View {
        let columns = block.data.columns ?? []
        VStack(alignment: .leading, spacing: 0) {
            if let row = model.tableRows[block.id]?.first(where: { $0.id == rowID }) {
                let title = columns.first { $0.kind == .text }
                if let title {
                    TextCell(row: row, column: title).font(.title.bold()).padding([.horizontal, .top], 24).padding(.bottom, 12)
                }
                Form {
                    Section {
                        ForEach(columns.filter { $0.id != title?.id }) { column in
                            LabeledContent {
                                CellEditor(row: row, column: column, editOptions: editOptions, large: true)
                            } label: {
                                Label(column.name, systemImage: TableBlock.symbol(column.kind))
                            }
                        }
                        Menu {
                            ForEach(SpaceColumn.Kind.allCases, id: \.self) { kind in
                                Button(kind.title, systemImage: TableBlock.symbol(kind)) {
                                    let column = kind == .category ? SpaceColumn(name: "Category", kind: .category, options: [])
                                        : SpaceColumn(name: kind == .link ? "Link" : kind.title, kind: kind)
                                    Task { await model.setColumns(columns + [column], of: block) }
                                }
                            }
                        } label: { Label("Add a property", systemImage: "plus") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .help("A link, a date, a checkbox or anything else, for every card in this table")
                    }
                    if columns.contains(where: { $0.kind == .date }) {
                        Section {
                            Picker(selection: Binding(get: { row.cells[SpaceTable.repeatKey] ?? "" }, set: { setRepeat($0, on: row) })) {
                                Text("Never").tag("")
                                ForEach(SpaceTable.Repeat.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                            } label: { Label("Repeat", systemImage: "repeat") }
                        } footer: {
                            if row.cells[SpaceTable.repeatKey] != nil {
                                Text("Ticking it off on Today, the Calendar or in the notch moves its date to the next time.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Note") { CardNoteEditor(row: row, columns: columns) }
                }
                .formStyle(.grouped)
                HStack {
                    Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete(row) }; dismiss() }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(20)
            } else {
                ContentUnavailableView("This card is gone", systemImage: "rectangle.slash")
            }
        }
        .frame(width: 520, height: 560)
        .onExitCommand { dismiss() }
    }

    private func setRepeat(_ value: String, on row: SpaceRow) {
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        changed.cells[SpaceTable.repeatKey] = value.isEmpty ? nil : value
        Task { await model.update(changed) }
    }
}

/// A card's own note: a few lines about it, saved when you click away. AI can write it from the card or rework it,
/// straight in place (the card is already a sheet), with Undo.
private struct CardNoteEditor: View {
    @Environment(AppModel.self) private var model
    let row: SpaceRow
    let columns: [SpaceColumn]
    @State private var text = ""
    @State private var working = false
    @State private var undoText: String?
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text).font(.body).frame(minHeight: 100).focused($focused)
                .scrollContentBackground(.hidden)
                .disabled(working) // typing during the AI call would be replaced by its reply
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text("Add a note, a link, the next step…").foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false) }
                }
                .accessibilityLabel("Note")
            HStack(spacing: 10) {
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Menu {
                    Button(BlinkServer.TextTask.write.title) { run(.write) }
                    Divider()
                    ForEach(BlinkServer.TextTask.edits + [.friendlier, .formal], id: \.self) { task in
                        Button(task.title) { run(task) }.disabled(empty)
                    }
                } label: { Label("AI", systemImage: "sparkles") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(working)
                    .help("Write this note from the card, or shorten, fix or change its tone")
                if working { ProgressView().controlSize(.small) }
                if let undoText {
                    Button("Undo") { text = undoText; self.undoText = nil; save() }
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            }
        }
        .onAppear { text = row.cells[SpaceTable.noteKey] ?? "" }
        .onChange(of: focused) { _, now in if !now { save() } }
        .onDisappear(perform: save)
    }

    /// The card as "Name: value" lines for Write It; files stay out (AI never sees them).
    private var cardText: String {
        let current = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        var lines = columns.filter { $0.kind != .file }.compactMap { column -> String? in
            let value = SpaceTable.display(current, column)
            return value.isEmpty ? nil : "\(column.name): \(value)"
        }
        if !text.isEmpty { lines.append("Note so far: \(text)") }
        return lines.joined(separator: "\n")
    }

    private func run(_ task: BlinkServer.TextTask) {
        guard let server = model.server else { problem = "Connect your server in Settings first."; return }
        let input = task == .write ? cardText : text
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { problem = "Give the card a title first."; return }
        working = true
        problem = nil
        let before = text
        Task {
            defer { working = false }
            do {
                let after = try await server.edit(input, task: task)
                undoText = before
                text = String(after.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SpaceTable.noteLimit))
                save()
            } catch let error as BlinkServer.ChatProblem {
                problem = error.message
            } catch {
                problem = "Couldn't reach your server. Try again in a moment."
            }
        }
    }

    private func save() {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SpaceTable.noteLimit))
        var changed = model.tableRows[row.blockID]?.first { $0.id == row.id } ?? row
        guard clean != (changed.cells[SpaceTable.noteKey] ?? "") else { return }
        changed.cells[SpaceTable.noteKey] = clean.isEmpty ? nil : clean
        Task { await model.update(changed) }
    }
}

/// Which properties a view shows; hidden ones stay on the card and in other views.
private struct PropertiesEditor: View {
    let columns: [SpaceColumn]
    let view: SpaceTableView
    let update: (SpaceTableView) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if view.kind == .board {
                Text("Board").font(.headline)
                Picker("Card size", selection: Binding(get: { view.cardSize ?? "medium" }, set: { v in var x = view; x.cardSize = v; update(x) })) {
                    Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large")
                }
                .pickerStyle(.segmented)
                Toggle("Coloured columns", isOn: Binding(get: { view.colorColumns ?? true }, set: { v in var x = view; x.colorColumns = v; update(x) }))
                Toggle("Show notes on cards", isOn: Binding(get: { view.showNotes ?? true }, set: { v in var x = view; x.showNotes = v; update(x) }))
                Toggle("Hide empty columns", isOn: Binding(get: { view.hideEmpty ?? false }, set: { v in var x = view; x.hideEmpty = v; update(x) }))
                Divider()
            }
            Text(view.kind == .board ? "Show on cards" : "Show in this view").font(.headline)
            ForEach(columns) { column in
                Toggle(isOn: Binding(get: { !(view.hidden ?? []).contains(column.id) }, set: { on in
                    var v = view
                    v.hidden = on ? (v.hidden ?? []).filter { $0 != column.id } : (v.hidden ?? []) + [column.id]
                    update(v)
                })) { Label(column.name, systemImage: TableBlock.symbol(column.kind)) }
            }
        }
        .padding(16)
        .frame(minWidth: 240)
    }
}

// MARK: AI

/// "Make this a content calendar": the AI proposes columns, options and a view; the owner reads it, then applies it.
private struct AskTableSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let columns: [SpaceColumn]
    var initial = ""
    let apply: (TablePlan) -> Void
    @State private var ask = ""
    @State private var plan: TablePlan?
    @State private var working = false
    @State private var problem: String?
    private let examples = ["Make this a content calendar", "Turn this into a hiring pipeline board", "Add a priority and a due date", "Group by status on a board"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ask AI to change this table", systemImage: "wand.and.stars").font(.title3.bold())
            TextField("What should this table become?", text: $ask, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
                .onSubmit(suggest)
            if plan == nil {
                FlowChips(items: examples) { ask = $0; suggest() }
            }
            if let plan {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.summary).font(.headline)
                    ForEach(plan.renames, id: \.from) { Label("Rename “\($0.from)” to “\($0.to)”", systemImage: "pencil") }
                    ForEach(plan.addColumns, id: \.name) { c in
                        Label("Add \(c.name) (\(SpaceColumn.Kind(rawValue: c.kind)?.title ?? "Text"))\(c.options.isEmpty ? "" : ": " + c.options.joined(separator: ", "))", systemImage: "plus.circle")
                    }
                    ForEach(plan.addOptions, id: \.column) { Label("Add to \($0.column): \($0.options.joined(separator: ", "))", systemImage: "chevron.down.circle") }
                    if let view = plan.view {
                        Label("New \(view.kind == "board" ? "board" : "table") view “\(view.name)”\(view.groupBy.map { ", grouped by \($0)" } ?? "")\(view.filters.isEmpty ? "" : ", \(view.filters.count) filter\(view.filters.count == 1 ? "" : "s")")",
                              systemImage: view.kind == "board" ? "rectangle.split.3x1" : "tablecells")
                    }
                    Text("Nothing is removed. You can change or undo any of it by hand.").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                if let plan {
                    Button("Try Again") { self.plan = nil; suggest() }.disabled(working)
                    Button("Apply") { apply(plan); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button { suggest() } label: { if working { ProgressView().controlSize(.small) } else { Text("Suggest") } }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(working || ask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { if !initial.isEmpty { ask = initial; suggest() } }
    }

    private func suggest() {
        guard let server = model.server else { problem = "Connect your server in Settings first."; return }
        guard !ask.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        problem = nil
        Task {
            defer { working = false }
            do { plan = try await server.planTable(ask, columns: columns) } catch { problem = error.localizedDescription }
        }
    }
}

/// "Turn into Cards" on a mail or a note: pick one of your Space tables, and the AI turns the text into its cards,
/// shown before they're added (the same sheet as pasting text into a table).
struct TurnIntoCardsMenu: View {
    @Environment(AppModel.self) private var model
    /// A note Blink wrote from a meeting: its next steps become the cards on the Mac.
    var meeting = false
    /// When the text was written, for "tomorrow" in a meeting's next steps.
    var written = Date.now
    /// The text at the moment a table is picked (a mail's body may still be loading when the view appears).
    let text: () -> String
    @State private var target: SpaceBlock?
    @State private var loading = false
    @State private var problem: String?

    var body: some View {
        let live = Set(model.spaces.map(\.id))
        let tables = model.liveTables.filter { live.contains($0.spaceID) && !($0.data.columns ?? []).isEmpty }
        Menu {
            if tables.isEmpty {
                Text("No tables yet. Add a table to a Space's page first.")
            }
            ForEach(model.spaces.filter { space in tables.contains { $0.spaceID == space.id } }) { space in
                Section(space.title) {
                    ForEach(tables.filter { $0.spaceID == space.id }) { table in
                        Button(table.data.text?.isEmpty == false ? table.data.text! : "Table") { pick(table, in: space) }
                    }
                }
            }
        } label: {
            if loading { ProgressView().controlSize(.small) } else { Label("Turn into Cards", systemImage: "rectangle.stack.badge.plus") }
        }
        .menuIndicator(.hidden).fixedSize()
        .disabled(loading)
        .help("Turn this into cards in one of your Space tables; you see them before they're added")
        .sheet(item: $target) { block in
            PasteRowsSheet(block: block, columns: block.data.columns ?? [], initial: String(text().prefix(20_000)),
                           meeting: meeting, written: written)
        }
        .alert("Couldn't open that table", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: { Text(problem ?? "") }
    }

    /// Loads the Space's blocks and the table's rows first, so new options are saved and new cards go after the old ones.
    private func pick(_ table: SpaceBlock, in space: Space) {
        loading = true
        Task {
            defer { loading = false }
            if model.spaceBlocks[space.id] == nil { await model.loadBlocks(space) }
            guard let block = model.spaceBlocks[space.id]?.first(where: { $0.id == table.id }) else {
                problem = "Check your connection and try again."; return
            }
            if model.tableRows[block.id] == nil { await model.loadRows(block) }
            target = block
        }
    }
}

/// Paste a list, an email or notes; the AI turns it into rows for this table, shown before they're added.
struct PasteRowsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: SpaceBlock
    let columns: [SpaceColumn]
    var initial = ""
    /// Suggest new cards (what's typed is the ask) instead of reading pasted text.
    var ideas = false
    var meeting = false
    var written = Date.now
    @State private var text = ""
    @State private var rows: [[String: String]]?
    @State private var fromMeeting = false
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ideas ? "Suggest cards" : "Paste text as rows", systemImage: ideas ? "lightbulb" : "text.badge.plus").font(.title3.bold())
            if let rows {
                Text("\(rows.count) \(rows.count == 1 ? (ideas ? "card" : "row") : (ideas ? "cards" : "rows")) \(ideas ? "suggested" : "found")").font(.headline)
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        SwiftUI.GridRow { ForEach(columns) { Text($0.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary) } }
                        Divider()
                        ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { _, row in
                            SwiftUI.GridRow {
                                ForEach(columns) { column in
                                    Text(row.first { $0.key.caseInsensitiveCompare(column.name) == .orderedSame }?.value ?? "").lineLimit(1).frame(maxWidth: 200, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: 260)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
                if rows.count > 30 { Text("and \(rows.count - 30) more").font(.caption).foregroundStyle(.secondary) }
                if fromMeeting { Text("The meeting's next steps, read on this Mac.").font(.caption).foregroundStyle(.secondary) }
            } else if ideas {
                Text("What kind of cards? Leave it empty and the AI suggests what fits this table. It won't repeat cards you have.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("For example: 10 post ideas about pricing", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                    .lineLimit(1...3).onSubmit(read)
            } else {
                Text("A list of founders from Claude, an email, meeting notes: anything with people, companies or items in it.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.body).frame(height: 240).scrollContentBackground(.hidden).padding(6)
                    .background(.background.secondary, in: .rect(cornerRadius: 8)).accessibilityLabel("Text to turn into rows")
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                if let rows {
                    Button("Back") { self.rows = nil; fromMeeting = false }
                    Button("Add \(rows.count) \(rows.count == 1 ? "Row" : "Rows")") { add(rows) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working)
                } else {
                    Button { read() } label: { if working { ProgressView().controlSize(.small) } else { Text(ideas ? "Suggest" : "Turn into Rows") } }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(working || (!ideas && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || columns.isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 640)
        .onAppear {
            guard !initial.isEmpty else { return }
            text = initial
            // Meeting notes: their next steps become the cards on this Mac, so the transcript never leaves it.
            let steps = meeting ? MeetingNotes.nextSteps(in: initial) : []
            if steps.isEmpty { read() } else { rows = MeetingNotes.cards(steps, columns: columns, now: written); fromMeeting = true }
        }
    }

    private func read() {
        guard let server = model.server else { problem = "Connect your server in Settings first."; return }
        guard !working else { return }
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                if ideas {
                    let name = columns.first { $0.kind == .text }
                    let existing = name.map { n in (model.tableRows[block.id] ?? []).map { SpaceTable.display($0, n) }.filter { !$0.isEmpty } } ?? []
                    rows = try await server.ideas(text, existing: existing, columns: columns)
                } else {
                    rows = try await server.rows(fromText: text, columns: columns)
                }
            } catch { problem = error.localizedDescription }
        }
    }

    private func add(_ rows: [[String: String]]) {
        working = true
        Task {
            defer { working = false }
            let (cells, changed) = SpaceTable.cells(from: rows, columns: columns)
            if changed != columns { await model.setColumns(changed, of: block) } // new Category options it found
            if await model.addRows(cells, to: block) { dismiss() }
        }
    }
}

/// Example asks as small buttons that wrap onto lines.
private struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { pick(item) } label: {
                    Text(item).font(.callout).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Editors

private struct FilterEditor: View {
    let columns: [SpaceColumn]
    let view: SpaceTableView
    let update: (SpaceTableView) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filters").font(.headline)
            if view.filters.isEmpty { Text("Show only the rows you want, like Status is Done.").font(.callout).foregroundStyle(.secondary) }
            ForEach(view.filters) { filter in
                FilterRow(columns: columns, filter: filter, change: { change(filter.id, to: $0) }, remove: { remove(filter.id) })
            }
            Button("Add Filter", systemImage: "plus") { add() }.disabled(columns.isEmpty)
        }
        .padding(16)
        .frame(minWidth: 380)
    }

    private func add() {
        guard let column = columns.first else { return }
        var changed = view
        changed.filters.append(RowFilter(column: column.id, op: RowFilter.Op.choices(for: column.kind)[0]))
        update(changed)
    }

    private func change(_ id: String, to filter: RowFilter) {
        var changed = view
        guard let i = changed.filters.firstIndex(where: { $0.id == id }) else { return }
        changed.filters[i] = filter
        update(changed)
    }

    private func remove(_ id: String) {
        var changed = view
        changed.filters.removeAll { $0.id == id }
        update(changed)
    }
}

/// One filter line: property, how to compare, and the value.
private struct FilterRow: View {
    let columns: [SpaceColumn]
    let filter: RowFilter
    let change: (RowFilter) -> Void
    let remove: () -> Void

    private var column: SpaceColumn? { columns.first { $0.id == filter.column } }

    var body: some View {
        HStack {
            Picker("Property", selection: Binding(get: { filter.column }, set: pickColumn)) {
                ForEach(columns) { column in Text(column.name).tag(column.id) }
            }
            .labelsHidden().frame(width: 130)
            Picker("How", selection: Binding(get: { filter.op }, set: { op in var f = filter; f.op = op; change(f) })) {
                ForEach(RowFilter.Op.choices(for: column?.kind ?? .text), id: \.self) { op in Text(op.title).tag(op) }
            }
            .labelsHidden().frame(width: 120)
            if filter.op.needsValue { valueField }
            Button("Remove", systemImage: "xmark", action: remove).labelStyle(.iconOnly).buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var valueField: some View {
        if let column, column.kind == .category {
            Picker("Value", selection: Binding(get: { filter.value }, set: { value in var f = filter; f.value = value; change(f) })) {
                Text("Choose…").tag("")
                ForEach(column.options ?? []) { option in Text(option.name).tag(option.id) }
            }
            .labelsHidden().frame(width: 130)
        } else {
            FilterValue(value: filter.value) { value in var f = filter; f.value = value; change(f) }.frame(width: 130)
        }
    }

    private func pickColumn(_ id: String) {
        var f = filter
        f.column = id
        f.op = RowFilter.Op.choices(for: columns.first { $0.id == id }?.kind ?? .text)[0]
        f.value = ""
        change(f)
    }
}

/// The text a filter looks for, saved when you press Return or leave the field (not on every key).
private struct FilterValue: View {
    let value: String
    let save: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("Value", text: $text).textFieldStyle(.roundedBorder)
            .onAppear { text = value }.onSubmit { save(text) }.onDisappear { if text != value { save(text) } }
    }
}

private struct SortEditor: View {
    let columns: [SpaceColumn]
    let view: SpaceTableView
    let update: (SpaceTableView) -> Void

    var body: some View {
        Form {
            Picker("Sort by", selection: Binding(get: { view.sortColumn ?? "" }, set: { id in var v = view; v.sortColumn = id.isEmpty ? nil : id; update(v) })) {
                Text("As added").tag("")
                ForEach(columns) { Text($0.name).tag($0.id) }
            }
            Picker("Order", selection: Binding(get: { view.sortAscending }, set: { up in var v = view; v.sortAscending = up; update(v) })) {
                Text("A to Z, first to last").tag(true)
                Text("Z to A, last to first").tag(false)
            }
            .disabled(view.sortColumn == nil)
        }
        .padding(12)
        .frame(width: 320)
    }
}

/// A Category's options: rename, recolour, reorder, add, delete. Cards keep their option through renames.
private struct OptionsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: SpaceBlock
    let column: SpaceColumn
    @State private var options: [SpaceOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(column.name) options").font(.headline)
            List {
                ForEach($options) { $option in
                    HStack {
                        Menu {
                            ForEach(SpaceOption.colors, id: \.self) { color in
                                Button(color.capitalized) { option.color = color }
                            }
                        } label: { Circle().fill(Color.system(option.color)).frame(width: 14, height: 14) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Colour")
                        TextField("Option", text: $option.name).textFieldStyle(.plain)
                        Button("Delete", systemImage: "trash") { options.removeAll { $0.id == option.id } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .onMove { options.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 200)
            HStack {
                Button("Add Option", systemImage: "plus") {
                    options.append(SpaceOption(name: "Option \(options.count + 1)", color: SpaceOption.colors[options.count % SpaceOption.colors.count]))
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save(); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 380)
        .onAppear { options = column.options ?? [] }
    }

    private func save() {
        var columns = block.data.columns ?? []
        guard let i = columns.firstIndex(where: { $0.id == column.id }) else { return }
        columns[i].options = options.map { var o = $0; o.name = String(o.name.trimmingCharacters(in: .whitespaces).prefix(40)); return o }
            .filter { !$0.name.isEmpty }
        Task { await model.setColumns(columns, of: block) }
    }
}
#endif
