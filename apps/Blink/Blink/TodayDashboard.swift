// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Today in the Look v3 style (DESIGN.md): soft canvas, an ink hero card with one big number, one warm card for
/// what's next, stat cards with bars, a properties list, then the day's lists on rounded cards.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    let showWaiting: () -> Void
    let showNotes: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        main(now: now).frame(minWidth: 420)
                        side(now: now).frame(width: 300)
                    }
                    VStack(spacing: 16) {
                        main(now: now)
                        side(now: now, inRow: true)
                    }
                }
                .padding(20)
            }
            .background(BlinkCanvas())
        }
    }

    // MARK: Columns

    private func main(now: Date) -> some View {
        VStack(spacing: 16) {
            HeroCard(now: now, showNotes: showNotes)
            if model.eveningDue {
                DashCard("Evening check-in") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tomorrow, \(model.tomorrow.formatted(.dateTime.weekday(.wide).day().month())): \(model.agenda.dayLine(for: model.tomorrow))")
                            .foregroundStyle(.secondary)
                        if let answer = model.chat.last(where: { $0.role == .assistant }), !model.chat.isEmpty {
                            Text(ChatPanel.markdown(answer.text))
                        }
                        if !model.quickReplies.isEmpty && !model.thinking {
                            HStack {
                                ForEach(model.quickReplies, id: \.self) { reply in
                                    Button(reply) { Task { await model.quickReply(reply) } }
                                }
                            }
                        }
                        HStack {
                            Button { Task { await model.planTomorrow() } } label: {
                                if model.thinking { ProgressView().controlSize(.small) } else { Label("Plan with Blink", systemImage: "moon.stars") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.thinking)
                            Button("All set") { model.finishEvening() }
                        }
                    }
                }
            }
            if let next = model.agenda.today(now: now).first {
                NextMeetingCard(event: next, now: now)
            }
            if let first = model.pending.first {
                DashCard("Waiting for you", trailing: model.pending.count > 1 ? "See all \(model.pending.count)" : nil,
                         action: showWaiting) {
                    CardView(action: first, count: model.pending.count, problem: model.actionProblem, app: model)
                }
            }
            let habits = model.habits.filter { model.isScheduledToday($0) }
            if !habits.isEmpty {
                DashCard("Habits") { CardRows(items: habits) { HabitRow(habit: $0) } }
            }
            let dueTasks = model.openTasks.filter { $0.isDue(by: now) }
            if !dueTasks.isEmpty {
                DashCard("Tasks due") { CardRows(items: dueTasks) { TaskRow(task: $0) } }
            }
            let meetings = Array(model.agenda.today(now: now).dropFirst())
            if !meetings.isEmpty {
                DashCard("Later today") { CardRows(items: meetings) { EventRow(event: $0, now: now) } }
            }
            if !model.agenda.reminders.isEmpty {
                DashCard("Reminders") { CardRows(items: model.agenda.reminders) { ReminderRow(reminder: $0) } }
            }
            if model.calendarAccess != .granted {
                DashCard("Calendar") { ConnectCalendarRow() }
            }
        }
    }

    /// The stat cards: a column beside the day, or one row under it when the window is narrow.
    private func side(now: Date, inRow: Bool = false) -> some View {
        let todays = model.agenda.events.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        let ended = todays.filter { $0.end <= now }.count
        let habits = model.habits.filter { model.isScheduledToday($0) }
        let done = habits.filter { model.answerToday($0) == .done }.count
        let due = model.openTasks.filter { $0.isDue(by: now) }
        let layout = inRow ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            Text("At a glance").font(.headline).padding(.horizontal, 4)
            layout {
            StatCard(title: "Meetings today", value: todays.isEmpty ? "None" : "\(todays.count - ended) left",
                     progress: todays.isEmpty ? nil : Double(ended) / Double(todays.count), tint: .mint)
            StatCard(title: "Habits today", value: habits.isEmpty ? "None yet" : "\(done) of \(habits.count)",
                     detail: bestStreak(),
                     progress: habits.isEmpty ? nil : Double(done) / Double(habits.count), tint: .green)
            StatCard(title: "Tasks due", value: due.isEmpty ? "None" : "\(due.count)", detail: nextDeadline(now),
                     progress: nil, tint: due.contains { ($0.dueAt ?? .distantFuture) < now } ? .orange : .accentColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextDeadline(_ now: Date) -> String? {
        guard let task = model.openTasks.filter({ ($0.dueAt ?? .distantPast) > now }).min(by: { $0.dueAt! < $1.dueAt! }),
              let due = task.dueAt else { return nil }
        return "Next: \(task.title) · \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    private func bestStreak() -> String? {
        guard let best = model.habits.map({ ($0, model.progress($0).streak) }).max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return nil
        }
        return "Best streak: \(best.0.name) · \(best.1 == 1 ? "1 day" : "\(best.1) days")"
    }
}

// MARK: Pieces

/// Ink hero card: one big number, pill actions with a round "+", a sync chip.
private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    let now: Date
    let showNotes: () -> Void
    @State private var adding = false
    @State private var newTask = ""

    var body: some View {
        let hero = model.agenda.hero(now: now, tasks: model.dueTasks)
        VStack(spacing: 12) {
            Text(now, format: .dateTime.weekday(.wide).day().month())
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text(hero.value)
                .font(.system(size: 52, weight: .semibold, design: .rounded)) // type.numbers
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(hero.caption)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            HStack(spacing: 10) {
                PillButton(title: "Note", symbol: "square.and.pencil") {
                    model.focusNoteID = model.create(.note, title: "").id
                    showNotes()
                }
                PillButton(title: "Task", symbol: "plus") { adding = true }
                    .popover(isPresented: $adding, arrowEdge: .bottom) { quickTask }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RadialGradient(colors: [Color.gray.opacity(0.35), .black], center: .top, startRadius: 0, endRadius: 360),
            in: .rect(cornerRadius: Tokens.Radius.notchOpen + 6, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(hero.value) \(hero.caption)")
    }

    private var quickTask: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("New task, e.g. \"Pay rent friday 9am\"", text: $newTask)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit {
                    let parsed = TaskInput.parse(newTask)
                    guard !parsed.title.isEmpty else { return }
                    model.create(.task, title: parsed.title, due: parsed.due)
                    newTask = ""
                    adding = false
                }
            if let due = TaskInput.parse(newTask).due {
                Label("Due \(due.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))",
                      systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
}

private struct PillButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// The one warm, rich card: the next meeting, with Join, and Blink watching it.
private struct NextMeetingCard: View {
    let event: AgendaEvent
    let now: Date

    var body: some View {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next meeting").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(event.title).font(.title3.weight(.semibold)).lineLimit(2)
                Text("\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))\(event.location.map { " · \($0)" } ?? "")")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let url = event.joinURL {
                    Link(destination: url) {
                        Text(minutes > 0 ? "Join in \(minutes) min" : "Join now")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.black, in: .capsule)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer()
            BlinkEyes(mood: minutes <= 10 ? .headsUp : .idle)
                .frame(width: 76, height: 44)
                .background(.black, in: .rect(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [.orange.opacity(0.22), .pink.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: Tokens.Radius.notchOpen, style: .continuous)
        )
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let progress: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if let progress {
                GeometryReader { geo in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // equal heights in a row
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
#endif
