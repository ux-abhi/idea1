// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Calendar, laid out like a planner: a small month to pick a day and the day's to-dos on the left, the week (or one
/// day) as a time grid on the right, with meetings as blocks and a red line for now. Everything comes from the
/// calendars on this Mac; a click on a meeting shows it with Join.
struct CalendarListView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("calendar.mode") private var mode = Mode.week
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var events: [AgendaEvent] = []

    private var cal: Calendar { .current }

    /// The days the grid shows: the picked day, or its whole week.
    private var days: [Date] {
        guard mode == .week, let week = cal.dateInterval(of: .weekOfYear, for: day) else { return [day] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// What to read from the calendar: the picked day's month and the shown week, which can run into the next month.
    private var window: DateInterval {
        let month = cal.dateInterval(of: .month, for: day) ?? DateInterval(start: day, duration: 86_400)
        let first = min(month.start, days.first ?? day)
        let last = max(month.end, cal.date(byAdding: .day, value: 1, to: days.last ?? day) ?? month.end)
        return DateInterval(start: first, end: last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.calendarAccess != .granted {
                DashCard { ConnectCalendarRow() }
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        MiniMonth(day: $day, busy: Set(events.map { cal.startOfDay(for: $0.start) }))
                        DayToDos(day: day)
                    }
                    .frame(width: 270)
                    WeekGrid(days: days, events: events, picked: $day)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .background(BlinkCanvas())
        .task(id: window) { events = await model.events(in: window) }
        // A change on the Mac (or a meeting marked done) reloads what's shown.
        .onChange(of: model.calendarEvents) { Task { events = await model.events(in: window) } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar").font(.system(.largeTitle, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(title).foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(Mode.allCases) { option in
                FilterPill(title: option.rawValue, on: mode == option) { mode = option }
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            Button("Today") { day = cal.startOfDay(for: .now) }
                .keyboardShortcut("t", modifiers: .command)
                .help("Go to today (⌘T)")
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .accessibilityLabel(mode == .week ? "Previous week" : "Previous day")
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .accessibilityLabel(mode == .week ? "Next week" : "Next day")
        }
        .buttonStyle(.bordered)
    }

    /// "20 – 26 Oct 2026" for a week, "Thursday, 22 Oct" for a day.
    private var title: String {
        guard mode == .week, let first = days.first, let last = days.last else {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func move(_ step: Int) {
        day = cal.date(byAdding: .day, value: step * (mode == .week ? 7 : 1), to: day) ?? day
    }
}

// MARK: Month

/// A small month: pick a day; a dot under days with meetings; today circled, the picked day filled.
private struct MiniMonth: View {
    @Binding var day: Date
    let busy: Set<Date>
    @State private var shownMonth = Calendar.current.startOfDay(for: .now)

    private var cal: Calendar { .current }

    var body: some View {
        let month = cal.dateInterval(of: .month, for: shownMonth) ?? DateInterval(start: shownMonth, duration: 86_400)
        let lead = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: month.start) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.start.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(cal.veryShortStandaloneWeekdaySymbols[(i + cal.firstWeekday - 1) % 7])
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 30) }
                }
            }
        }
        .padding(16)
        .cardSurface(radius: Tokens.Radius.tile)
        .onChange(of: day, initial: true) { shownMonth = day }
    }

    private func dayCell(_ date: Date) -> some View {
        let picked = cal.isDate(date, inSameDayAs: day)
        let today = cal.isDateInToday(date)
        return Button { day = cal.startOfDay(for: date) } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day()))
                    .font(.callout.weight(picked || today ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(picked ? Color.white : today ? Color.accentColor : .primary)
                    .frame(width: 26, height: 26)
                    .background(picked ? Color.accentColor : .clear, in: .circle)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: today && !picked ? 1.5 : 0))
                Circle().fill(busy.contains(cal.startOfDay(for: date)) ? Color.secondary : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func shift(_ months: Int) {
        shownMonth = cal.date(byAdding: .month, value: months, to: shownMonth) ?? shownMonth
    }
}

// MARK: The day's to-dos

/// Tasks and reminders due on the picked day, ticked off right here.
private struct DayToDos: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let cal = Calendar.current
        let tasks = model.openTasks.filter { $0.dueAt.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        let reminders = model.allReminders.filter { $0.due.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        VStack(alignment: .leading, spacing: 10) {
            Text(cal.isDateInToday(day) ? "Due today" : "Due \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                .font(.headline)
            if tasks.isEmpty && reminders.isEmpty {
                Text("Nothing due.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                row(task.title, symbol: "circle", tint: .secondary, tag: Tag(text: "Task", tint: .blue)) { Task { await model.toggle(task) } }
            }
            ForEach(reminders) { reminder in
                row(reminder.title, symbol: "circle", tint: .orange, tag: Tag(text: "Reminder", tint: .orange)) {
                    Task { await model.complete(reminder) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Tokens.Radius.tile)
    }

    private func row(_ title: String, symbol: String, tint: Color, tag: Tag, done: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: done) { Image(systemName: symbol).foregroundStyle(tint) }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(title) done")
            Text(title).font(.callout).lineLimit(1)
            Spacer(minLength: 4)
            tag
        }
    }
}

// MARK: The time grid

/// Days across, hours down; meetings as blocks (side by side when they overlap), a red line for now. Opens scrolled
/// to the morning.
private struct WeekGrid: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let events: [AgendaEvent]
    @Binding var picked: Date
    @ScaledMetric private var hour = 56.0
    private let gutter = 52.0

    private var cal: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.everyMinute) { context in
                        GeometryReader { geo in
                            let column = (geo.size.width - gutter) / Double(max(days.count, 1))
                            ZStack(alignment: .topLeading) {
                                hourLines(width: geo.size.width)
                                ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                                    let x = gutter + Double(index) * column
                                    if cal.isDate(date, inSameDayAs: picked) && days.count > 1 {
                                        Rectangle().fill(Color.accentColor.opacity(0.04)).frame(width: column, height: hour * 24).offset(x: x)
                                    }
                                    ForEach(EventLane.layout(events.filter { cal.isDate($0.start, inSameDayAs: date) }), id: \.event.id) { lane in
                                        block(lane, day: date, x: x, column: column)
                                    }
                                }
                                nowLine(context.date, width: geo.size.width, column: column)
                            }
                        }
                        .frame(height: hour * 24)
                    }
                }
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
        .cardSurface(radius: Tokens.Radius.tile)
        .clipShape(.rect(cornerRadius: Tokens.Radius.tile, style: .continuous))
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { date in
                let today = cal.isDateInToday(date)
                Button { picked = date } label: {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(today ? Color.white : .primary)
                            .frame(width: 34, height: 34)
                            .background(today ? Color.accentColor : .clear, in: .circle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            }
        }
    }

    private func hourLines(width: Double) -> some View {
        ForEach(0..<24, id: \.self) { h in
            HStack(alignment: .top, spacing: 6) {
                Text(cal.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now, format: .dateTime.hour())
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    .frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: -6)
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            }
            .frame(width: width, alignment: .leading)
            .offset(y: Double(h) * hour)
            .id(h)
        }
    }

    private func y(_ date: Date, on day: Date) -> Double {
        date.timeIntervalSince(cal.startOfDay(for: day)) / 3600 * hour
    }

    private func block(_ lane: EventLane, day: Date, x: Double, column: Double) -> some View {
        let event = lane.event
        let top = max(y(event.start, on: day), 0)
        let height = max(min(y(event.end, on: day), hour * 24) - top, 22)
        let width = column / Double(lane.of)
        return EventBlock(event: event, done: model.doneMeetings.contains(event.id))
            .frame(width: width - 4, height: height - 2)
            .offset(x: x + width * Double(lane.lane) + 2, y: top + 1)
    }

    @ViewBuilder
    private func nowLine(_ now: Date, width: Double, column: Double) -> some View {
        if let index = days.firstIndex(where: { cal.isDate($0, inSameDayAs: now) }) {
            let top = y(now, on: now)
            Rectangle().fill(Color.red.opacity(0.35)).frame(width: width - gutter, height: 1).offset(x: gutter, y: top)
            Rectangle().fill(Color.red).frame(width: column, height: 2).offset(x: gutter + Double(index) * column, y: top - 0.5)
            Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: gutter + Double(index) * column - 4.5, y: top - 4)
                .accessibilityLabel("Now")
        }
    }
}

/// One meeting in the grid; a click shows when, where and Join.
private struct EventBlock: View {
    @Environment(AppModel.self) private var model
    let event: AgendaEvent
    let done: Bool
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 0) {
                Rectangle().fill(Color.accentColor).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.caption.weight(.semibold)).lineLimit(2)
                    Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.18))
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .opacity(done ? 0.5 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) { details }
        .contextMenu {
            if let url = event.joinURL { Button("Join") { NSWorkspace.shared.open(url) } }
            if done { Button("Mark Not Done") { model.reopenMeeting(event) } } else { Button("Mark Done") { model.finishMeeting(event) } }
        }
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened))\(done ? ", done" : "")")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title).font(.headline)
            Label("\(event.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute())) – \(event.end.formatted(date: .omitted, time: .shortened))",
                  systemImage: "clock")
            if let location = event.location, !location.isEmpty, event.joinURL?.absoluteString != location {
                Label(location, systemImage: "mappin.and.ellipse").lineLimit(2)
            }
            HStack {
                if let url = event.joinURL {
                    Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent)
                }
                Button(done ? "Mark Not Done" : "Mark Done") { done ? model.reopenMeeting(event) : model.finishMeeting(event); showing = false }
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}
#endif
