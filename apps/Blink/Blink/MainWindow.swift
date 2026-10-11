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
            case .tasks: "Tasks & Habits"
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
            case .today: TodayView(showWaiting: { section = .waiting }, showNotes: { section = .notes })
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
        let count = model.agenda.events.count
        DashPage("Calendar", summary: count == 0 ? "Next 7 days" : "\(count == 1 ? "1 meeting" : "\(count) meetings") in the next 7 days") {
            if model.calendarAccess != .granted {
                DashCard { ConnectCalendarRow() }
            } else if days.isEmpty {
                EmptyCard(symbol: "calendar", title: "No meetings this week",
                          message: "Timed events from the calendars on this Mac show here for the next 7 days. All-day events and ones you've declined are left out.")
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

/// What Blink did, newest first, by day. shortcut: no Undo yet; add it with the first undoable kinds (Phase 2 notes and tasks).
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
                DashCard(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month())) {
                    CardRows(items: days[day] ?? []) { ActivityRow(action: $0) }
                }
            }
        }
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
