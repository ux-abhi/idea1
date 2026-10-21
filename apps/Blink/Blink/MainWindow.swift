// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The Mac window: sidebar · content (ARCHITECTURE §5). Settings live in their own window (⌘,).
struct MainWindow: View {
    enum Section: String, CaseIterable, Identifiable {
        case today, inbox, calendar, notes, tasks, content, money, waiting, activity
        var id: Self { self }

        var title: String {
            switch self {
            case .today: "Today"
            case .inbox: "Inbox"
            case .calendar: "Calendar"
            case .notes: "Notes"
            case .tasks: "Tasks & Habits"
            case .content: "Content"
            case .money: "Money"
            case .waiting: "Needs You"
            case .activity: "Activity"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .inbox: "envelope"
            case .calendar: "calendar"
            case .notes: "note.text"
            case .tasks: "checklist"
            case .content: "megaphone"
            case .money: "eurosign.circle"
            case .waiting: "tray"
            case .activity: "clock.arrow.circlepath"
            }
        }
    }

    /// What the sidebar shows: a fixed page or one Space.
    enum Page: Hashable {
        case section(Section), space(String)

        /// Stored as "tasks" or "space:<id>" so the window reopens where you left it.
        var key: String {
            switch self {
            case .section(let s): s.rawValue
            case .space(let id): "space:\(id)"
            }
        }

        init(key: String) {
            if key.hasPrefix("space:") { self = .space(String(key.dropFirst(6))) }
            else { self = .section(Section(rawValue: key) ?? .today) }
        }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("page") private var savedPage = "today"
    @State private var page: Page?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var newSpace = false
    @AppStorage("blinkPanel") private var showPanel = true
    @State private var searching = false
    // Sidebar groups fold; each remembers whether it's open.
    @AppStorage("sidebar.open.main") private var mainOpen = true
    @AppStorage("sidebar.open.spaces") private var spacesOpen = true
    @AppStorage("sidebar.open.review") private var reviewOpen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Blink's own sidebar button: the automatic one is re-inserted as a duplicate when this view is rebuilt in the
        // same window (after onboarding or signing back in), which crashes AppKit's toolbar.
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $page) {
                SwiftUI.Section("Blink", isExpanded: $mainOpen) {
                    row(.today)
                    row(.inbox)
                    row(.calendar)
                    row(.notes)
                    row(.tasks)
                    if model.showsContent { row(.content) }
                    row(.money)
                }
                spacesSection
                SwiftUI.Section("Review", isExpanded: $reviewOpen) {
                    row(.waiting)
                    row(.activity)
                }
            }
            .sheet(isPresented: $searching) {
                SearchSheet { target, note in
                    if let note { model.focusNoteID = note }
                    page = target
                }
            }
            .sheet(isPresented: $newSpace) {
                NewSpaceSheet { page = .space($0) }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .toolbar(removing: .sidebarToggle)
            // Settings in plain sight, not only behind ⌘,.
            .safeAreaInset(edge: .bottom) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .help("Settings (⌘,)")
            }

        } detail: {
            detail
                .inspector(isPresented: $showPanel) { BlinkPanel(page: page ?? .section(.today)) }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { columns = columns == .detailOnly ? .all : .detailOnly } label: {
                            Label("Sidebar", systemImage: "sidebar.left")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                        .help("Show or hide the sidebar (⌃⌘S)")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                    // Sync now: check in, then reload calendar, cards, notes, tasks, spaces, habits and posts.
                    Button {
                        Task {
                            await model.refresh()
                            await model.loadActivity()
                            await model.syncMail()
                        }
                    } label: {
                        if model.status == .checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }
                    }
                    .keyboardShortcut("r")
                    .disabled(model.status == .checking)
                    .help("Sync now (⌘R)")
                    Button { searching = true } label: { Label("Search", systemImage: "magnifyingglass") }
                        .keyboardShortcut("k")
                        .help("Search notes, tasks, posts and spaces (⌘K)")
                    Button { showPanel.toggle() } label: { Label("Blink", systemImage: "sidebar.right") }
                        .keyboardShortcut("b", modifiers: [.command, .option])
                        .help("Show or hide the Blink panel (⌥⌘B)")
                    }
                }
        }
        .overlay(alignment: .bottom) { UndoToast() }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Tokens.Motion.content.animation, value: model.undoChip?.id)
        // One title per page: the big heading in the page; the toolbar carries the app name and sync state.
        .navigationTitle("Blink")
        .navigationSubtitle(subtitle)
        .onAppear { page = Page(key: model.openPage ?? savedPage); model.openPage = nil }
        .onChange(of: model.openPage) {
            if let key = model.openPage { page = Page(key: key); model.openPage = nil }
        }
        .onChange(of: page) { if let page { savedPage = page.key } }
        .task {
            // Onboarding's last step has just synced in this launch: don't fetch everything twice in a row.
            // (lastSync survives a relaunch, so it alone can't tell; status is .checking until this launch syncs.)
            if model.status != .connected || model.lastSync.map({ Date.now.timeIntervalSince($0) > 30 }) ?? true { await model.refresh() }
            await model.loadActivity()
        }
    }

    @ViewBuilder private var detail: some View {
            switch page ?? .section(.today) {
        case .section(.today): TodayView(showWaiting: { page = .section(.waiting) }, showNotes: { page = .section(.notes) },
                                         showContent: { page = .section(.content) }, showInbox: { page = .section(.inbox) })
        case .section(.inbox): InboxView()
        case .section(.calendar): CalendarListView()
        case .section(.notes): NotesView()
        case .section(.tasks): TasksView()
        case .section(.content): ContentView()
        case .section(.money): MoneyView()
        case .section(.waiting): WaitingView()
        case .section(.activity): ActivityView()
        case .space(let id):
            if let space = model.spaces.first(where: { $0.id == id }) {
                SpaceView(space: space, openNote: { note in
                    model.focusNoteID = note
                    // Notes opens filtered to this Space, so its other notes stay in view.
                    UserDefaults.standard.set(space.id, forKey: "notes.space")
                    page = .section(.notes)
                })
                .id(id)
            } else {
                TodayView(showWaiting: { page = .section(.waiting) }, showNotes: { page = .section(.notes) },
                          showContent: { page = .section(.content) })
            }
        }
            }

    private var spacesSection: some View {
        SwiftUI.Section("Spaces", isExpanded: $spacesOpen) {
            ForEach(model.spaces) { space in spaceRow(space) }
            Button { newSpace = true } label: { Label("New Space", systemImage: "plus") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func spaceRow(_ space: Space) -> some View {
        let progress = Space.progress(of: model.items, in: space.id)
        return Label {
            Text(space.title)
        } icon: {
            Image(systemName: space.icon).foregroundStyle(Color.system(space.color))
        }
        .badge(progress.total - progress.done)
        .tag(Page.space(space.id))
    }

    private func row(_ s: Section) -> some View {
        Label(s.title, systemImage: s.symbol)
            .badge(s == .waiting ? model.pending.count : s == .inbox ? model.importantMail.filter { $0.status == .new }.count : 0)
            .tag(Page.section(s))
    }

    /// "Last synced" in the toolbar (§36.2); the server's address only when it can't be reached (it's in Settings).
    private var subtitle: String {
        switch model.status {
        case .checking: return "Syncing…"
        case .unreachable: return model.pausedProject != nil ? "Your free server is asleep: Settings › Server"
                                                              : "Can't reach \(model.server?.config.host ?? "your server")"
        case .connected:
            guard let lastSync = model.lastSync else { return "Synced" }
            return "Synced \(lastSync.formatted(.relative(presentation: .named)))"
        }
    }
}

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: AgendaEvent
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing) {
                Text(event.start, format: .dateTime.hour().minute())
                Text(event.end, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
            }
            .font(.callout.monospacedDigit())
            .frame(minWidth: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).lineLimit(1)
                if let location = event.location, event.joinURL?.absoluteString != location.trimmingCharacters(in: .whitespaces) {
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if model.doneMeetings.contains(event.id) {
                Button("Mark Not Done") { model.reopenMeeting(event) }.buttonStyle(.bordered)
            }
            if let url = event.joinURL {
                Link("Join", destination: url).buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ConnectCalendarRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your meetings and reminders show here once Calendar is connected.")
                .foregroundStyle(.secondary)
            if model.calendarAccess == .notAsked {
                Button("Connect Calendar") { Task { await model.connectCalendar() } }
            } else {
                Text("Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars and Reminders.")
                    .font(.caption)
            }
        }
    }
}

// MARK: Calendar

struct CalendarListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Every meeting, done ones too (with "Not done"), so a wrong tap on Done can always be put right here.
        let days = Dictionary(grouping: model.calendarEvents) { Calendar.current.startOfDay(for: $0.start) }
        let count = model.calendarEvents.count
        DashPage("Calendar", summary: count == 0 ? "Next 14 days" : "\(count == 1 ? "1 meeting" : "\(count) meetings") in the next 14 days") {
            if model.calendarAccess != .granted {
                DashCard { ConnectCalendarRow() }
            } else if days.isEmpty {
                EmptyCard(symbol: "calendar", title: "No meetings in the next 14 days",
                          message: "Timed events from the calendars on this Mac show here for the next 14 days. All-day events and ones you've declined are left out.")
            } else {
                ForEach(days.keys.sorted(), id: \.self) { day in
                    DashCard(dayTitle(day)) {
                        CardRows(items: days[day] ?? []) { EventRow(event: $0, now: .now) }
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }
}

// MARK: Waiting for you

struct WaitingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashPage("Waiting for you", summary: model.pending.isEmpty ? "Nothing needs you" : "\(model.pending.count) need\(model.pending.count == 1 ? "s" : "") your OK") {
            if model.pending.isEmpty {
                EmptyCard(symbol: "tray", title: "Nothing waiting for you",
                          message: "When Blink prepares something that needs your OK, like adding a reminder, it waits here and in the notch.")
            }
            ForEach(model.pending) { action in
                DashCard {
                    CardView(action: action, count: 1, problem: action.id == model.pending.first?.id ? model.actionProblem : nil, app: model)
                }
            }
        }
        .task { await model.loadActions() }
    }
}

// MARK: Activity

/// What Blink did, newest first, by day. shortcut: no Undo for Blink's own actions here (ticking off has its chip); add it when an executor can reverse, e.g. task.add → delete.
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = Dictionary(grouping: model.activity) { Calendar.current.startOfDay(for: $0.decidedAt ?? .distantPast) }
        DashPage("Activity", summary: model.activity.isEmpty ? "What Blink did" : "Last \(model.activity.count) decisions") {
            if model.activity.isEmpty {
                EmptyCard(symbol: "clock.arrow.circlepath", title: "No activity yet",
                          message: "Everything Blink does or you approve is listed here, for example a reminder it added.")
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                DashCard(activityDayTitle(day)) {
                    CardRows(items: days[day] ?? []) { ActivityRow(action: $0) }
                }
            }
        }
        .task { await model.loadActivity() }
    }

    /// Decisions without a time (made outside Blink) go under "Earlier".
    private func activityDayTitle(_ day: Date) -> String {
        if day < Date(timeIntervalSince1970: 0) { return "Earlier" }
        return Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month())
    }
}

struct ActivityRow: View {
    let action: BlinkAction

    private var outcome: (word: String, symbol: String, tint: Color) {
        switch action.status {
        case "done": ("Done", "checkmark.circle.fill", .green)
        case "approved": ("Approved", "checkmark.circle", .green)
        case "declined": ("Dismissed", "xmark.circle", .secondary)
        case "failed": ("Didn't work", "exclamationmark.triangle", .orange)
        case "expired": ("Expired", "clock", .secondary)
        case "undone": ("Undone", "arrow.uturn.backward.circle", .secondary)
        default: (action.status?.capitalized ?? "", "circle", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: outcome.symbol).foregroundStyle(outcome.tint)
                .accessibilityLabel(outcome.word)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.historyTitle).lineLimit(1)
                if let at = action.decidedAt {
                    Text(at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
