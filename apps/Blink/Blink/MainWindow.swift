// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The Mac window: sidebar · content (ARCHITECTURE §5). Settings live in their own window (⌘,).
struct MainWindow: View {
    enum Section: String, CaseIterable, Identifiable {
        case today, calendar, notes, tasks, waiting, activity
        var id: Self { self }

        var title: String {
            switch self {
            case .today: "Today"
            case .calendar: "Calendar"
            case .notes: "Notes"
            case .tasks: "Tasks"
            case .waiting: "Waiting for you"
            case .activity: "Activity"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .calendar: "calendar"
            case .notes: "note.text"
            case .tasks: "checklist"
            case .waiting: "tray"
            case .activity: "clock.arrow.circlepath"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var section: Section? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                SwiftUI.Section {
                    row(.today)
                    row(.calendar)
                    row(.notes)
                    row(.tasks)
                }
                SwiftUI.Section {
                    row(.waiting)
                    row(.activity)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch section ?? .today {
            case .today: TodayView(showWaiting: { section = .waiting })
            case .calendar: CalendarListView()
            case .notes: NotesView()
            case .tasks: TasksView()
            case .waiting: WaitingView()
            case .activity: ActivityView()
            }
        }
        .navigationSubtitle(subtitle)
        .task {
            await model.refresh()
            await model.loadActivity()
        }
    }

    private func row(_ s: Section) -> some View {
        Label(s.title, systemImage: s.symbol)
            .badge(s == .waiting ? model.pending.count : 0)
            .tag(s)
    }

    /// "Last synced" in the toolbar (§36.2).
    private var subtitle: String {
        let host = model.server?.config.host ?? "your server"
        switch model.status {
        case .checking: return "Checking \(host)…"
        case .unreachable: return "Can't reach \(host)"
        case .connected:
            guard let lastSync = model.lastSync else { return "Connected to \(host)" }
            return "Connected to \(host) · Synced \(lastSync.formatted(.relative(presentation: .named)))"
        }
    }
}

// MARK: Today

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let showWaiting: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            Form {
                SwiftUI.Section {
                    Text(model.agenda.statusLine(now: now, tasks: model.dueTasks))
                        .font(.title2.weight(.semibold))
                    if model.calendarAccess == .granted {
                        Text(model.agenda.briefLine(now: now)).foregroundStyle(.secondary)
                    }
                }

                if let first = model.pending.first {
                    SwiftUI.Section {
                        CardView(action: first, count: model.pending.count, problem: model.actionProblem, app: model)
                        if model.pending.count > 1 {
                            Button("See all \(model.pending.count)", action: showWaiting)
                        }
                    } header: {
                        Text("Waiting for you")
                    }
                }

                SwiftUI.Section("Meetings") {
                    if model.calendarAccess != .granted {
                        ConnectCalendarRow()
                    } else if model.agenda.today(now: now).isEmpty {
                        Text("No more meetings today.").foregroundStyle(.secondary)
                    }
                    ForEach(model.agenda.today(now: now)) { EventRow(event: $0, now: now) }
                }

                let dueTasks = model.openTasks.filter { $0.isDue(by: now) }
                if !dueTasks.isEmpty {
                    SwiftUI.Section("Tasks due") {
                        ForEach(dueTasks) { TaskRow(task: $0) }
                    }
                }

                if !model.agenda.reminders.isEmpty {
                    SwiftUI.Section("Reminders") {
                        ForEach(model.agenda.reminders) { ReminderRow(reminder: $0) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle(greeting)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

struct EventRow: View {
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
                if let location = event.location, event.joinURL == nil {
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let url = event.joinURL {
                Link("Join", destination: url).buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
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
        let days = Dictionary(grouping: model.agenda.events) { Calendar.current.startOfDay(for: $0.start) }
        Group {
            if model.calendarAccess != .granted {
                Form { ConnectCalendarRow() }.formStyle(.grouped)
            } else if days.isEmpty {
                ContentUnavailableView("No meetings this week", systemImage: "calendar",
                                       description: Text("Timed events from the calendars on this Mac show here for the next 7 days. All-day events and ones you've declined are left out."))
            } else {
                List {
                    ForEach(days.keys.sorted(), id: \.self) { day in
                        SwiftUI.Section(day.formatted(.dateTime.weekday(.wide).day().month())) {
                            ForEach(days[day] ?? []) { EventRow(event: $0, now: .now) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendar")
    }
}

// MARK: Waiting for you

struct WaitingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.pending.isEmpty {
                ContentUnavailableView("Nothing waiting for you", systemImage: "tray",
                                       description: Text("When Blink prepares something that needs your OK, like adding a reminder, it waits here and in the notch."))
            } else {
                List(model.pending) { action in
                    CardView(action: action, count: 1, problem: action.id == model.pending.first?.id ? model.actionProblem : nil, app: model)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Waiting for you")
        .task { await model.loadActions() }
    }
}

// MARK: Activity

/// What Blink did, newest first. shortcut: no Undo yet; add it with the first undoable kinds (Phase 2 notes and tasks).
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Everything Blink does or you approve is listed here, for example a reminder it added."))
            } else {
                List(model.activity) { ActivityRow(action: $0) }
            }
        }
        .navigationTitle("Activity")
        .task { await model.loadActivity() }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).lineLimit(1)
                HStack(spacing: 4) {
                    Text(outcome.word)
                    if let at = action.decidedAt {
                        Text("·")
                        Text(at, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
