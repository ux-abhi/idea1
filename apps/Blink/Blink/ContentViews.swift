// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// Content (§36.4), in four tabs: Overview (how posts perform, connected accounts), Posts (a searchable list that
/// folds by status; a post opens in its own sheet), Plan (the next 7 days) and Ideas. New Post writes drafts.
struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, posts, plan, ideas
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("content.tab") private var tab: Tab = .posts
    @State private var composing = false
    @State private var clearingIdeas = false
    @State private var editingVoice = false
    @State private var opened: String?
    @State private var query = ""
    @State private var platform: ContentPiece.Platform?
    /// The day a new post is written for (from + on a plan day); nil from New Post.
    @State private var composeDay: String?

    var body: some View {
        let live = model.content.filter { $0.status != .archived }
        let ready = live.filter { $0.status == .approved }.count
        let drafts = live.filter { $0.status == .drafted }.count
        DashPage("Content", summary: "\(drafts) draft\(drafts == 1 ? "" : "s") · \(ready) ready to post") {
            HStack {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if tab == .posts { PageSearchField(prompt: "Search posts", text: $query) }
                // The window toolbar stays the same on every page: items that come and go between pages crash AppKit's toolbar.
                Button { editingVoice = true } label: { Label("Voice", systemImage: "person.wave.2") }
                    .help("How you write")
                Button { composeDay = nil; composing = true } label: { Label("New Post", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n")
                    .help("Write drafts from an idea (⌘N)")
            }
            if let problem = model.contentProblem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            switch tab {
            case .overview: ContentOverview(editVoice: { editingVoice = true })
            case .posts: posts(live)
            case .plan: plan(live)
            case .ideas: ideas
            }
        }
        .confirmationDialog("Clear all ideas?", isPresented: $clearingIdeas) {
            Button("Clear Ideas", role: .destructive) { Task { await model.clearIdeas() } }
        }
        .sheet(isPresented: $composing) {
            NewPostSheet(day: composeDay, written: { if composeDay == nil { tab = .posts } },
                         editVoice: { composing = false; editingVoice = true })
        }
        .sheet(isPresented: $editingVoice) { VoiceSheet() }
        .sheet(item: Binding(get: { opened.map(OpenedPiece.init) }, set: { opened = $0?.id })) { PieceSheet(id: $0.id) }
        .task {
            await model.loadContent()
            await model.loadContentStats()
        }
    }

    // MARK: Posts: one line each, folded by status, searchable

    @ViewBuilder
    private func posts(_ all: [ContentPiece]) -> some View {
        let live = all.filter { $0.status != .idea } // ideas live on the Plan
        let shown = live.filter(matches)
        HStack {
            Picker("Platform", selection: $platform) {
                Text("All platforms").tag(ContentPiece.Platform?.none)
                ForEach(ContentPiece.Platform.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
            }
            .fixedSize()
            Spacer()
        }
        if live.isEmpty && !model.drafting {
            EmptyCard(symbol: "megaphone", title: "No posts yet",
                      message: "Write an idea and Blink drafts an Instagram carousel or reel, a LinkedIn post and an X post, checks them, and you post them yourself.",
                      actionTitle: "New Post", action: { composing = true })
        } else if shown.isEmpty && !live.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if model.drafting {
            DashCard { HStack { ProgressView().controlSize(.small); Text("Writing drafts…").foregroundStyle(.secondary) } }
        }
        section("ready", "Ready to post", shown.filter { $0.status == .approved })
        section("drafts", "Drafts", shown.filter { $0.status == .drafted })
        section("posted", "Posted", shown.filter { $0.status == .published }, openByDefault: false)
    }

    private func matches(_ piece: ContentPiece) -> Bool {
        guard platform == nil || piece.platform == platform else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || [piece.hook, piece.body, piece.idea].contains { $0.localizedStandardContains(q) }
    }

    @ViewBuilder
    private func section(_ key: String, _ title: String, _ list: [ContentPiece], openByDefault: Bool = true) -> some View {
        if !list.isEmpty {
            FoldingCard(key: "content.\(key)", title: title, count: list.count, openByDefault: openByDefault) {
                CardRows(items: list) { piece in PostRow(piece: piece) { opened = piece.id } }
            }
        }
    }

    // MARK: Plan: a calendar of what goes out when

    private func plan(_ live: [ContentPiece]) -> some View {
        ContentPlan(live: live, open: { opened = $0 }, compose: { day in composeDay = day; composing = true })
    }

    // MARK: Ideas

    @ViewBuilder
    private var ideas: some View {
        DashCard("Ideas", trailing: model.ideas.isEmpty ? nil : "Clear…", action: { clearingIdeas = true }) {
            HStack {
                Button { Task { await model.suggestIdeas(theme: "", platforms: model.contentPlatforms) } } label: {
                    if model.thinkingOfIdeas { ProgressView().controlSize(.small) } else { Label("Give Me Ideas", systemImage: "lightbulb") }
                }
                .disabled(model.thinkingOfIdeas)
                Text("Six ideas built on what works on your page.").font(.caption).foregroundStyle(.secondary)
            }
            if model.ideas.isEmpty {
                Text("No ideas yet. Ask for some, or type /ideas in the notch.").foregroundStyle(.secondary)
            }
            CardRows(items: model.ideas) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.platform.name) · \(item.formatName)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(item.title).font(.headline)
                        Text("“\(item.hook)”").font(.callout)
                        Text(item.why).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Write This") { Task { await model.write(item); tab = .posts } }
                        .disabled(model.drafting)
                }
            }
        }
    }
}

/// The sheet's item: just the piece's id, so the sheet always shows the latest copy from the model.
private struct OpenedPiece: Identifiable { let id: String }

/// One post in a list: platform, hook, day and state. Click to open it.
private struct PostRow: View {
    @Environment(AppModel.self) private var model
    let piece: ContentPiece
    var compact = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Text(piece.platform.short).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.hook.isEmpty ? piece.body : piece.hook).lineLimit(1)
                    if !compact { Text(piece.idea).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if model.questions[piece.idea]?.isEmpty == false && piece.status == .drafted {
                    Image(systemName: "questionmark.bubble").foregroundStyle(.orange).help("Blink has questions to make it stronger")
                }
                if !compact, let day = piece.plannedFor {
                    Text(HabitDay.label(day)).font(.caption).foregroundStyle(day == HabitDay.key(.now) ? .orange : .secondary)
                }
                if let at = piece.publishedAt {
                    Text(at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                } else {
                    StatusChip(status: piece.status)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .draggable(piece.id) // onto a day of the plan
        .accessibilityLabel("\(piece.platform.name): \(piece.hook.isEmpty ? piece.body : piece.hook), \(StatusChip.name(piece.status))")
    }
}

/// The day a post goes out: "Add day", or the day; click to pick another or take it off the plan.
struct DayChip: View {
    @Binding var day: String?
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Label(day.map { HabitDay.label($0) } ?? "Add Day", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(day == HabitDay.key(.now) ? Color.orange : day == nil ? .secondary : .primary)
        }
        .buttonStyle(.borderless)
        .help("The day it goes out")
        .popover(isPresented: $picking) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("Post on", selection: Binding(
                    get: { day.flatMap { HabitDay.date(fromKey: $0) } ?? .now },
                    set: { day = HabitDay.key($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                if day != nil {
                    Button("Remove Day", role: .destructive) { day = nil; picking = false }
                }
            }
            .padding(12)
        }
    }
}

/// Where a post is: Idea → Draft → Ready → Posted.
struct StatusChip: View {
    let status: ContentPiece.Status

    static func name(_ status: ContentPiece.Status) -> String {
        switch status {
        case .idea: "Idea"
        case .drafted: "Draft"
        case .approved: "Ready"
        case .published: "Posted"
        case .archived: "Archived"
        }
    }

    var body: some View {
        let tint: Color = switch status {
        case .idea: .purple
        case .approved: .green
        case .published: .blue
        default: .secondary
        }
        Text(Self.name(status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// The plan as a calendar: a week (or a month) of days, each with what goes out that day. Drag a post onto a day to
/// move it, + on a day to write one for it, and the posts with no day wait at the bottom.
private struct ContentPlan: View {
    @Environment(AppModel.self) private var model
    let live: [ContentPiece]
    let open: (String) -> Void
    let compose: (String) -> Void
    @AppStorage("content.planMonth") private var month = false
    /// Weeks (or months) away from now.
    @State private var offset = 0
    @State private var target: String?
    @State private var removingIdeas = false

    private var calendar: Calendar { .current }

    /// The days on screen: one week from its first weekday, or the whole month in whole weeks.
    private var days: [Date] {
        let now = Date.now
        if month {
            guard let anchor = calendar.date(byAdding: .month, value: offset, to: now),
                  let range = calendar.dateInterval(of: .month, for: anchor),
                  let first = calendar.dateInterval(of: .weekOfYear, for: range.start)?.start else { return [] }
            let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            let end = calendar.dateInterval(of: .weekOfYear, for: last)?.end ?? range.end
            return stride(from: 0, to: 42, by: 1).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }.filter { $0 < end }
        }
        guard let anchor = calendar.date(byAdding: .weekOfYear, value: offset, to: now),
              let first = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        if month, let anchor = calendar.date(byAdding: .month, value: offset, to: .now) {
            return anchor.formatted(.dateTime.month(.wide).year())
        }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        let today = HabitDay.key(.now)
        let ideas = model.plannedIdeas
        DashCard {
            HStack(spacing: 8) {
                Button("Previous", systemImage: "chevron.left") { offset -= 1 }.labelStyle(.iconOnly)
                Text(title).font(.headline).monospacedDigit().frame(minWidth: 130)
                Button("Next", systemImage: "chevron.right") { offset += 1 }.labelStyle(.iconOnly)
                if offset != 0 { Button("Today") { offset = 0 } }
                Picker("View", selection: $month) {
                    Text("Week").tag(false)
                    Text("Month").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .onChange(of: month) { offset = 0 }
                Spacer()
                Button { Task { await model.planWeek(theme: "", platforms: model.contentPlatforms) } } label: {
                    if model.thinkingOfIdeas { ProgressView().controlSize(.small) } else { Label("Plan My Week", systemImage: "sparkles") }
                }
                .disabled(model.thinkingOfIdeas)
                .help("Blink puts post ideas on the next 7 days; write each when you're ready")
                if !ideas.isEmpty {
                    Menu("\(ideas.count) Idea\(ideas.count == 1 ? "" : "s")") {
                        Button("Write All \(ideas.count)") { Task { await model.writeAll(ideas) } }.disabled(model.drafting)
                        Button("Remove All Ideas…", role: .destructive) { removingIdeas = true }
                    }
                    .fixedSize()
                    .confirmationDialog("Remove all \(ideas.count) ideas from the plan?", isPresented: $removingIdeas) {
                        Button("Remove Ideas", role: .destructive) { Task { await model.clearPlannedIdeas() } }
                    } message: { Text("Posts you've already written stay.") }
                }
            }
            if model.drafting {
                HStack { ProgressView().controlSize(.small); Text("Writing drafts…").foregroundStyle(.secondary) }
            }
            if month { monthGrid(today: today) } else { weekList(today: today) }
        }
        let unscheduled = live.filter { $0.plannedFor == nil && ($0.status == .drafted || $0.status == .approved || $0.status == .idea) }
        if !unscheduled.isEmpty {
            DashCard("Not scheduled") {
                Text("Drag a post onto a day to plan it.").font(.caption).foregroundStyle(.secondary)
                CardRows(items: unscheduled) { piece in PostRow(piece: piece) { open(piece.id) } }
            }
            .dropDestination(for: String.self) { ids, _ in move(ids, to: nil) }
        }
    }

    private func pieces(on key: String) -> [ContentPiece] {
        live.filter { $0.plannedFor == key && $0.status != .archived }
    }

    private func weekList(today: String) -> some View {
        VStack(spacing: 0) {
            ForEach(days, id: \.self) { date in
                let key = HabitDay.key(date)
                let list = pieces(on: key)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day())).font(.title3.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(key == today ? Color.accentColor : .primary)
                    }
                    .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if list.isEmpty { Text("Nothing planned").font(.callout).foregroundStyle(.tertiary) }
                        ForEach(list) { piece in row(piece) }
                    }
                    Spacer(minLength: 0)
                    addButton(key, past: key < today)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(target == key ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
                .dropDestination(for: String.self) { ids, _ in move(ids, to: key) } isTargeted: { target = $0 ? key : (target == key ? nil : target) }
                if date != days.last { Divider() }
            }
        }
    }

    /// A planned post, or an idea with Write (and a menu to take it off the plan).
    @ViewBuilder
    private func row(_ piece: ContentPiece) -> some View {
        if piece.status == .idea {
            HStack {
                Image(systemName: "lightbulb").foregroundStyle(.purple).accessibilityHidden(true)
                Text("\(piece.platform.name) · \(piece.idea)").lineLimit(1)
                Spacer()
                Button("Write") { Task { await model.write(piece) } }.controlSize(.small).disabled(model.drafting)
                Menu {
                    Button("Remove From Plan", role: .destructive) { Task { await model.setStatus(.archived, of: piece) } }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("More for \(piece.idea)")
            }
            .help(piece.body) // why it works
            .draggable(piece.id)
        } else {
            PostRow(piece: piece, compact: true) { open(piece.id) }
        }
    }

    private func addButton(_ key: String, past: Bool) -> some View {
        Button("Add a post on this day", systemImage: "plus") { compose(key) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(past)
            .help("Write a post for this day")
    }

    private func monthGrid(today: String) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let shownMonth = calendar.date(byAdding: .month, value: offset, to: .now).map { calendar.component(.month, from: $0) }
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days.prefix(7), id: \.self) { date in
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { date in monthCell(date, today: today, month: shownMonth) }
        }
    }

    private func monthCell(_ date: Date, today: String, month shownMonth: Int?) -> some View {
        let key = HabitDay.key(date)
        let list = pieces(on: key)
        let inMonth = calendar.component(.month, from: date) == shownMonth
        let dayColor: Color = key == today ? .accentColor : inMonth ? .primary : .secondary
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(date.formatted(.dateTime.day())).font(.callout.weight(key == today ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(dayColor)
                Spacer()
                addButton(key, past: key < today).controlSize(.small)
            }
            ForEach(list.prefix(3)) { piece in monthChip(piece) }
            if list.count > 3 { Text("+\(list.count - 3) more").font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(minHeight: 86, alignment: .top)
        .background(target == key ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .dropDestination(for: String.self) { ids, _ in move(ids, to: key) } isTargeted: { target = $0 ? key : (target == key ? nil : target) }
    }

    private func monthChip(_ piece: ContentPiece) -> some View {
        let isIdea = piece.status == .idea
        let tint: Color = isIdea ? .purple : .accentColor
        return Button { if !isIdea { open(piece.id) } } label: {
            Text("\(piece.platform.short) \(isIdea ? piece.idea : piece.hook)")
                .font(.caption).lineLimit(1)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .draggable(piece.id)
        .help(isIdea ? "Idea: write it from the week view, or drag it to another day" : piece.hook)
    }

    /// Posts dropped on a day (or on Not scheduled) move there.
    private func move(_ ids: [String], to day: String?) -> Bool {
        let moving = ids.compactMap { id in model.content.first { $0.id == id } }
        Task { for piece in moving { await model.setDay(day, of: piece) } }
        return !moving.isEmpty
    }
}

/// One post, opened: the full editor, and Blink's questions for its idea.
/// Also opened from a Space's canvas, so a post can be read and edited without leaving the Space.
struct PieceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.content.first { $0.id == id }?.idea ?? "Post").font(.headline).lineLimit(1)
                Spacer()
                // Esc, not Return: Return belongs to the slide fields.
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                if let piece = model.content.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let asked = model.questions[piece.idea], !asked.isEmpty, piece.status == .drafted {
                            QuestionsBox(idea: piece.idea, questions: asked,
                                         platforms: Array(Set(model.content.filter { $0.idea == piece.idea }.map(\.platform))))
                        }
                        PieceEditor(piece: piece)
                    }
                    .padding(16)
                } else {
                    ContentUnavailableView("This post is gone", systemImage: "trash")
                }
            }
        }
        .frame(width: 640, height: 640)
        // Edits save a second after typing stops; closing sooner must not lose them.
        .onDisappear { Task { await model.saveContent(id) } }
    }
}

/// New Post: an idea → drafts for the chosen platforms.
private struct NewPostSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("contentPlatforms") private var picked = "instagram,linkedin,x"
    @State private var idea = ""
    /// The day it goes out; nil leaves it unscheduled.
    @State private var postOn: String?
    /// The plan day it was opened from, if any.
    let day: String?
    let written: () -> Void
    let editVoice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Post").font(.title3.weight(.semibold))
            TextField("What's the idea? e.g. \"3 checkout mistakes that lose users\"", text: $idea, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: Tokens.Radius.tile, style: .continuous))
            HStack(spacing: 8) {
                ForEach(ContentPiece.Platform.allCases, id: \.self) { platform in
                    Toggle(platform.name, isOn: Binding(get: { platforms.contains(platform) }, set: { _ in toggle(platform) }))
                        .toggleStyle(.button)
                }
                Spacer()
                DayChip(day: $postOn)
                ModelMenu(feature: "content", compact: true).menuStyle(.borderlessButton).controlSize(.small)
            }
            if let problem = model.contentProblem { Text(problem).font(.callout).foregroundStyle(.orange) }
            else if !model.voice.isSetUp {
                Button("Set up your voice…", action: editVoice)
                    .buttonStyle(.link)
            }
            HStack {
                // The idea doubles as a theme for a week plan or a set of ideas.
                Menu("More") {
                    Button("Plan My Week on This") { Task { await model.planWeek(theme: idea, platforms: platforms); written(); dismiss() } }
                    Button("Give Me Ideas on This") { Task { await model.suggestIdeas(theme: idea, platforms: platforms); dismiss() } }
                }
                .fixedSize()
                .disabled(platforms.isEmpty || model.thinkingOfIdeas)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        if await model.draft(idea: idea, platforms: platforms, plannedFor: postOn) { written(); dismiss() }
                    }
                } label: {
                    if model.drafting { ProgressView().controlSize(.small) } else { Label("Write Drafts", systemImage: "sparkles") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || platforms.isEmpty || model.drafting)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { postOn = day }
    }

    private var platforms: [ContentPiece.Platform] {
        picked.split(separator: ",").compactMap { ContentPiece.Platform(rawValue: String($0)) }
    }

    private func toggle(_ platform: ContentPiece.Platform) {
        var set = Set(platforms)
        if set.contains(platform) { set.remove(platform) } else { set.insert(platform) }
        picked = ContentPiece.Platform.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// One draft: the text (and its slides, posts or shots), the writing check, and Approve → Copy & Open.
private struct PieceEditor: View {
    @Environment(AppModel.self) private var model
    let piece: ContentPiece

    var body: some View {
        let check = ContentLint.check(piece, neverSay: model.voice.neverSay)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(piece.platform.name).font(.headline)
                Text(formatName).font(.caption).foregroundStyle(.secondary)
                DayChip(day: Binding(get: { piece.plannedFor }, set: { day in Task { await model.setDay(day, of: piece) } }))
                Spacer()
                ScoreBadge(score: check.score)
                Menu {
                    Button("Archive", role: .destructive) { Task { await model.setStatus(.archived, of: piece) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More")
            }

            if !piece.parts.isEmpty {
                ForEach(piece.parts.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(partLabel(index)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        TextField("", text: partBinding(index), axis: .vertical).textFieldStyle(.plain)
                        if piece.platform == .x {
                            Text("\(280 - piece.parts[index].count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(piece.parts[index].count > 280 ? .red : .secondary)
                        }
                    }
                }
                Text(piece.platform == .instagram ? "Caption" : "Post").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if piece.platform != .x || piece.parts.isEmpty {
                TextEditor(text: bodyBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 260)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10, style: .continuous))
            }
            if !piece.hashtags.isEmpty {
                Text(piece.hashtags.map { "#\($0)" }.joined(separator: " ")).font(.callout).foregroundStyle(.secondary)
            }

            PieceMedia(piece: piece, handle: model.voice.page)

            ForEach(check.issues, id: \.message) { issue in
                Label(issue.message, systemImage: issue.blocks ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(issue.blocks ? .red : .orange)
            }

            HStack {
                switch piece.status {
                case .drafted:
                    Button("Approve") { Task { await model.setStatus(.approved, of: piece) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(check.issues.contains { $0.blocks })
                        .help(check.issues.contains { $0.blocks } ? "Fix the red items first" : "Mark ready to post")
                case .approved:
                    Button { model.copyAndOpen(piece) } label: { Label("Copy & Open \(piece.platform.name)", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(.borderedProminent)
                    Button("Back to Draft") { Task { await model.setStatus(.drafted, of: piece) } }
                case .idea:
                    Button("Write") { Task { await model.write(piece) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.drafting)
                case .published, .archived:
                    EmptyView()
                }
                Spacer()
            }
        }
        // Saves after a pause in typing.
        .task(id: piece.body + piece.parts.joined()) {
            try? await Task.sleep(for: .seconds(1))
            await model.saveContent(piece.id)
        }
    }

    private var formatName: String {
        switch piece.format {
        case "carousel": "Carousel · \(piece.parts.count) slides"
        case "reel_script": "Reel script · \(piece.parts.count) shots"
        case "thread": "Thread · \(piece.parts.count) posts"
        default: "Post"
        }
    }

    private func partLabel(_ index: Int) -> String {
        switch piece.format {
        case "carousel": "Slide \(index + 1)"
        case "reel_script": "Shot \(index + 1)"
        default: "\(index + 1)/\(piece.parts.count)"
        }
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { piece.body }, set: { text in
            var changed = piece
            changed.body = text
            model.edit(changed)
        })
    }

    private func partBinding(_ index: Int) -> Binding<String> {
        Binding(get: { index < piece.parts.count ? piece.parts[index] : "" }, set: { text in
            guard index < piece.parts.count else { return }
            var changed = piece
            changed.parts[index] = text
            model.edit(changed)
        })
    }
}

/// What the model asked to know for a stronger post; the owner's answers redraft the idea with those facts.
private struct QuestionsBox: View {
    @Environment(AppModel.self) private var model
    let idea: String
    let questions: [String]
    let platforms: [ContentPiece.Platform]
    @State private var answers = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Blink needs a few facts to make this stronger", systemImage: "questionmark.bubble")
                .font(.callout.weight(.semibold))
            ForEach(questions, id: \.self) { Text("• \($0)").font(.callout) }
            TextField("Your answers, e.g. \"my app had 140 users; I paused features in June\"", text: $answers, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            HStack {
                Button("Redraft with Answers") { Task { await model.redraft(idea: idea, answers: answers, platforms: platforms) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(answers.trimmingCharacters(in: .whitespaces).isEmpty || model.drafting)
                Button("Keep as Is") { model.dismissQuestions(for: idea) }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

extension AppModel {
    /// Puts the post on the clipboard and opens the platform's composer (pre-filled where it allows), then marks it posted.
    func copyAndOpen(_ piece: ContentPiece) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(piece.postText, forType: .string)
        var url: URL?
        switch piece.platform {
        case .x:
            var c = URLComponents(string: "https://x.com/intent/post")
            // One post fills the composer; a thread is on the clipboard to paste post by post.
            if piece.parts.count <= 1 { c?.queryItems = [URLQueryItem(name: "text", value: piece.postText)] }
            url = c?.url
        case .linkedin:
            var c = URLComponents(string: "https://www.linkedin.com/feed/")
            c?.queryItems = [URLQueryItem(name: "shareActive", value: "true"), URLQueryItem(name: "text", value: piece.postText)]
            url = c?.url
        case .instagram:
            url = URL(string: "https://www.instagram.com/") // no web composer: the caption is on the clipboard
        }
        if let url { NSWorkspace.shared.open(url) }
        Task { await setStatus(.published, of: piece) }
    }
}

/// A draft's picture, only once the owner asks for it: carousel slides drawn on the Mac (over one FLUX background, if
/// made), or a cover image. Slides drag into any app; Export… writes PNGs to a folder you pick.
private struct PieceMedia: View {
    @Environment(AppModel.self) private var model
    let piece: ContentPiece
    let handle: String
    /// Decoded once per draft and new image, off the main thread, not on every keystroke in the draft.
    @State private var image: NSImage?

    var body: some View {
        let carousel = piece.format == "carousel" && !piece.parts.isEmpty
        let asked = model.designed.contains(piece.id)
        VStack(alignment: .leading, spacing: 8) {
                if carousel && asked {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(piece.parts.indices, id: \.self) { index in
                                slide(index, background: image)
                                    .frame(width: 1080, height: 1350)
                                    .scaleEffect(0.12, anchor: .topLeading)
                                    .frame(width: 130, height: 162, alignment: .topLeading)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .onDrag { provider(for: render(slide(index, background: image)), name: "slide-\(index + 1)") }
                                    .accessibilityLabel("Slide \(index + 1): \(piece.parts[index])")
                            }
                        }
                    }
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 200, height: 200).clipShape(.rect(cornerRadius: 10))
                        .onDrag { NSItemProvider(contentsOf: PostMedia.url(for: piece.id)) ?? NSItemProvider() }
                        .accessibilityLabel("Cover image")
                }
                HStack(spacing: 8) {
                    if carousel && !asked {
                        Button { model.design(piece) } label: { Label("Design Slides", systemImage: "square.stack") }
                            .help("Draw this carousel's slides with your text (free, on your Mac)")
                    }
                    if !carousel || asked {
                    Button {
                        Task { await model.makeImage(for: piece) }
                    } label: {
                        if model.makingImage.contains(piece.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(image == nil ? (carousel ? "Make Background" : "Make Image") : "New Image", systemImage: "photo.badge.plus")
                        }
                    }
                    .disabled(model.makingImage.contains(piece.id))
                    .help("A free image made for this post; the text is drawn on your Mac")
                    }
                    if (carousel && asked) || image != nil {
                        Button("Export…") { export(carousel: carousel, background: image) }
                    }
                }
                .controlSize(.small)
        }
        .task(id: "\(piece.id)-\(model.mediaVersion)") { // reload after a new image
            let url = PostMedia.url(for: piece.id)
            image = await Task.detached { FileManager.default.fileExists(atPath: url.path) ? NSImage(contentsOf: url) : nil }.value
        }
    }

    private func slide(_ index: Int, background: NSImage?) -> some View {
        SlideView(text: piece.parts[index], index: index, total: piece.parts.count,
                  handle: handle.split(separator: " ").first.map(String.init) ?? "", background: background)
    }

    private func render(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: 1080, height: 1350))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func provider(for data: Data?, name: String) -> NSItemProvider {
        let provider = NSItemProvider()
        if let data {
            provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { done in
                done(data, nil)
                return nil
            }
        }
        provider.suggestedName = name
        return provider
    }

    /// Writes slide-01.png… (or cover.jpg) into a folder the owner picks, then shows them in Finder.
    private func export(carousel: Bool, background: NSImage?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for this post's images"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var written: [URL] = []
        if carousel {
            for index in piece.parts.indices {
                let file = folder.appending(path: String(format: "slide-%02d.png", index + 1))
                if let data = render(slide(index, background: background)), (try? data.write(to: file)) != nil { written.append(file) }
            }
        } else if let data = try? Data(contentsOf: PostMedia.url(for: piece.id)) {
            let file = folder.appending(path: "cover.jpg")
            if (try? data.write(to: file)) != nil { written.append(file) }
        }
        if !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) }
    }
}

/// One 1080 × 1350 carousel slide: the first over the background image, the rest on a dimmed version of it; big, crisp text.
struct SlideView: View {
    let text: String
    let index: Int
    let total: Int
    let handle: String
    let background: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let background {
                    Image(nsImage: background).resizable().scaledToFill()
                        .blur(radius: index == 0 ? 0 : 30)
                } else {
                    LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 1080, height: 1350)
            .clipped()
            LinearGradient(colors: [.black.opacity(index == 0 ? 0.2 : 0.55), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(text)
                    .font(.system(size: index == 0 ? 92 : 68, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.5)
                Spacer()
                HStack {
                    Text(handle).font(.system(size: 34, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(index + 1)/\(total)").font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(90)
        }
        .frame(width: 1080, height: 1350)
    }
}

/// The writing check's score, coloured so a glance is enough.
private struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((score >= 80 ? Color.green : score >= 50 ? .orange : .red).opacity(0.2), in: .capsule)
            .foregroundStyle(score >= 80 ? Color.green : score >= 50 ? .orange : .red)
            .help("Writing check: 100 means no AI-sounding phrases and within the platform's limits")
            .accessibilityLabel("Writing check \(score) out of 100")
    }
}

/// Who you are online and how you write: drafts and ideas follow it, and the writing check flags words you never use.
private struct VoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = ""
    @State private var audience = ""
    @State private var topics = ""
    @State private var notes = ""
    @State private var neverSay = ""
    @State private var brief = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $brief)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 140)
                HStack {
                    Button("Import File…", action: importBrief)
                    if !brief.isEmpty { Button("Clear", role: .destructive) { brief = "" } }
                    Spacer()
                    Text("\(brief.count.formatted()) of \(VoiceProfile.briefLimit.formatted()) characters")
                        .font(.caption).foregroundStyle(brief.count > VoiceProfile.briefLimit ? .red : .secondary)
                }
            } header: {
                Text("Creator brief")
            } footer: {
                Text("Your story, projects, numbers, content pillars and rules, e.g. a Markdown file. Drafts, ideas and your week plan use only its facts, and its writing rules come first. Kept on your server.")
            }
            Section {
                TextField("Your page", text: $page, prompt: Text("e.g. @yourname on Instagram: UX tips and design breakdowns"))
                TextField("Who it's for", text: $audience, prompt: Text("e.g. junior designers and devs who want better UX"), axis: .vertical)
                    .lineLimit(1...3)
                TextField("Your topics", text: $topics, prompt: Text("e.g. UX mistakes, app teardowns, design tools, building Blink"), axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Your page")
            } footer: {
                Text("Ideas and drafts use this to be specific to your field instead of generic.")
            }
            Section {
                TextField("How you sound", text: $notes,
                          prompt: Text("e.g. Short sentences, friendly, a bit dry. I show real screens, not theory."),
                          axis: .vertical)
                    .lineLimit(2...6)
                TextField("Words you never say", text: $neverSay, prompt: Text("e.g. hustle, synergy, crushing it"))
            } header: {
                Text("Your voice")
            } footer: {
                Text("Words separated by commas. Drafts avoid them and the writing check flags them. Blink never invents facts about you.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let words = neverSay.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    Task {
                        await model.saveVoice(VoiceProfile(page: trim(page), audience: trim(audience), topics: trim(topics),
                                                           notes: trim(notes), neverSay: words, brief: trim(brief)))
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            page = model.voice.page
            audience = model.voice.audience
            topics = model.voice.topics
            notes = model.voice.notes
            neverSay = model.voice.neverSay.joined(separator: ", ")
            brief = model.voice.brief
        }
    }

    /// A Markdown or text file the owner picks (user-selected read access only).
    private func importBrief() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md") ?? .plainText]
        panel.message = "Choose your creator brief (a Markdown or text file)"
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        brief = String(text.prefix(VoiceProfile.briefLimit))
    }
}
#endif
