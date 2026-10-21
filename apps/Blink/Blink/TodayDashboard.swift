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
    let showContent: () -> Void
    var showInbox: () -> Void = {}
    @AppStorage("tourDone") private var tourDone = false
    @State private var addingTask = false
    @State private var newTask = ""

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ScrollView {
                VStack(spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        // Side by side at the same height, so the top of Today reads as one row.
                        HStack(alignment: .top, spacing: 16) {
                            HeroCard(now: now, showNotes: showNotes, adding: $addingTask, newTask: $newTask)
                            DayRings(rings: rings(now)).frame(width: 300)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 16) {
                            HeroCard(now: now, showNotes: showNotes, adding: $addingTask, newTask: $newTask)
                            DayRings(rings: rings(now))
                        }
                    }
                    tiles(now)
                    // One getting-started card at a time: setup while something's left, then the tips.
                    let steps = model.setupSteps
                    if steps.contains(where: { !$0.done }) { SetupCard(steps: steps) }
                    else if !tourDone { TipsCard { tourDone = true } }
                    lists(now: now)
                }
                .padding(20)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .background(BlinkCanvas())
        }
    }

    // MARK: Visual summary

    private func rings(_ now: Date) -> [DayRings.Ring] {
        let cal = Calendar.current
        let meetings = model.agenda.events.filter { cal.isDate($0.start, inSameDayAs: now) }
        // shortcut: "done today" = finished tasks last changed today (no completion time is stored); add a completed_at
        // column if editing an old finished task ever inflates the ring.
        let tasksDone = model.doneTasks.filter { cal.isDate($0.updatedAt, inSameDayAs: now) }.count
        let tasksDue = model.openTasks.filter { $0.isDue(by: cal.startOfDay(for: now).addingTimeInterval(86_400)) }.count
        let habits = model.habits.filter { model.isScheduledToday($0) }
        return [
            .init(id: "Meetings", done: meetings.filter { $0.end <= now }.count, total: meetings.count, tint: .mint),
            .init(id: "Tasks", done: tasksDone, total: tasksDone + tasksDue, tint: .orange),
            .init(id: "Habits", done: habits.filter { model.answerToday($0) == .done }.count, total: habits.count, tint: .green),
        ]
    }

    /// Four numbers you can click through: tasks, mail, posts, money.
    private func tiles(_ now: Date) -> some View {
        let overdue = model.openTasks.filter { ($0.dueAt ?? .distantFuture) < now }.count
        let due = model.openTasks.filter { $0.isDue(by: now) }.count
        let mail = model.importantMail.filter { $0.status == .new }.count
        let ready = model.readyToPost.count
        let today = HabitDay.key(now)
        let month = MoneyMath.summary(model.spends, today: today)
        let money = model.accounts.isEmpty ? nil : MoneyMath.leftAtMonthEnd(total: MoneyMath.totalBalance(model.accounts), summary: month, today: today)
        return HStack(alignment: .top, spacing: 12) {
            tile("tasks", MetricTile(title: "Tasks due", text: "\(due)", detail: overdue > 0 ? "\(overdue) overdue" : nextDeadline(now) ?? "On track",
                                     detailColor: overdue > 0 ? .orange : .secondary))
            tile("inbox", MetricTile(title: "Important mail", text: "\(mail)", detail: mail == 0 ? "All caught up" : "New",
                                     detailColor: mail == 0 ? .green : .red))
            if model.showsContent { tile("content", MetricTile(title: "Posts ready", text: "\(ready)", detail: ready == 0 ? "None waiting" : "To post")) }
            tile("money", MetricTile(title: "Spent this month", value: month.total,
                                     detail: money.map { "\($0.formatted(.currency(code: MoneyMath.currency))) left at month end" } ?? "Add an account",
                                     detailColor: (money ?? 1) < 0 ? .red : .secondary))
        }
        .fixedSize(horizontal: false, vertical: true) // all four as tall as the tallest
    }

    private func tile(_ page: String, _ content: MetricTile) -> some View {
        Button { model.go(to: page) } label: { content }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(page.capitalized)")
    }

    private func nextDeadline(_ now: Date) -> String? {
        guard let task = model.openTasks.filter({ ($0.dueAt ?? .distantPast) > now }).min(by: { $0.dueAt! < $1.dueAt! }),
              let due = task.dueAt else { return nil }
        return "Next: \(task.title), \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    private func bestStreak() -> String? {
        guard let best = model.habits.map({ ($0, model.progress($0).streak) }).max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return "Best streak \(best.1) day\(best.1 == 1 ? "" : "s")"
    }

    private var weekCharts: some View {
        let days = WeekBars.lastWeek()
        // Habit days start at wake time, so their week ends on the habit day, not the calendar day.
        let habitDays = WeekBars.lastWeek(now: model.habitToday)
        let habitDone: [(day: String, value: Double)] = habitDays.map { day in
            (day, Double(model.habitAnswers.values.filter { $0[day] == .done }.count))
        }
        let spent: [(day: String, value: Double)] = days.map { day in
            (day, WeekBars.euros(model.spends.filter { $0.spentOn == day }.reduce(Decimal.zero) { $0 + $1.amount }))
        }
        return HStack(alignment: .top, spacing: 16) {
            WeekBars(title: "Habits this week", days: habitDone, tint: .green)
            WeekBars(title: "Spent this week", days: spent, tint: .accentColor,
                     format: { $0.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))) })
        }
    }

    // MARK: The day, then the lists

    @ViewBuilder
    private func lists(now: Date) -> some View {
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
        DayTimelineCard(plan: DayPlan(events: model.agenda.events, tasks: model.dueTasks, reminders: model.agenda.reminders, now: now), now: now)
        weekCharts
        let habits = model.habits.filter { model.isScheduledToday($0) }
        if !habits.isEmpty {
            DashCard("Habits", trailing: bestStreak()) { CardRows(items: habits) { HabitRow(habit: $0) } }
        }
        let mail = model.importantMail.filter { $0.status != .drafted }
        if !mail.isEmpty {
            DashCard("Important mail", trailing: "Inbox", action: showInbox) {
                CardRows(items: Array(mail.prefix(4))) { message in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(message.sender): \(message.subject)").lineLimit(1)
                            Text(message.reason.isEmpty ? message.summary : message.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        let posts = model.readyToPost + model.postsToday.filter { $0.status == .drafted }
        if !posts.isEmpty {
            DashCard("Posts for today", trailing: "Open Content", action: showContent) {
                CardRows(items: posts) { piece in
                    HStack(spacing: 10) {
                        Text(piece.platform.name).font(.caption.weight(.semibold)).frame(width: 70, alignment: .leading)
                        Text(piece.hook.isEmpty ? piece.body : piece.hook).lineLimit(1)
                        Spacer()
                        Text(piece.status == .approved ? "Ready" : "To review")
                            .font(.caption).foregroundStyle(piece.status == .approved ? .green : .orange)
                    }
                }
            }
        }
    }
}

// MARK: Pieces

/// Ink hero card: one big number, pill actions with a round "+", a sync chip.
private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    let now: Date
    let showNotes: () -> Void
    // Owned by Today, so a layout change (narrow ↔ wide) doesn't lose a half-typed task.
    @Binding var adding: Bool
    @Binding var newTask: String

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

    private func addTask() {
        let parsed = TaskInput.parse(newTask)
        guard !parsed.title.isEmpty else { return }
        model.create(.task, title: parsed.title, due: parsed.due)
        newTask = ""
        adding = false
    }

    private var quickTask: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("New task, e.g. \"Pay rent friday 9am\"", text: $newTask)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(addTask)
                Button("Add", action: addTask).disabled(TaskInput.parse(newTask).title.isEmpty)
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

/// First days: the few things worth knowing, until "Got it".
private struct TipsCard: View {
    let done: () -> Void

    var body: some View {
        DashCard("Get to know Blink", trailing: "Got it", action: done) {
            VStack(alignment: .leading, spacing: 8) {
                tip("Click", "Click the notch to see your day and ask Blink anything.")
                tip("Say it", "“Remind me to call Sam at 4pm”, “task send invoice friday”, “timer 10 min”: no / needed.")
                tip("⌃⌥Space", "Open the notch chat from anywhere.")
                tip("⌃⌥V", "Your clipboard history, with search. Drag items into any app.")
                tip("⌘K", "Search notes, tasks, posts and spaces.")
                tip("⌥⌘B", "The Blink panel on every page, with suggestions for that page.")
            }
        }
    }

    private func tip(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key).font(.callout.monospaced().weight(.semibold)).frame(width: 80, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today on one time axis: overdue first, then things with no time, then the day in order with a now line.
private struct DayTimelineCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let now: Date

    var body: some View {
        DashCard("Your day") {
            if !plan.isEmpty { DayStrip(plan: plan, now: now).padding(.bottom, 6) }
            if plan.isEmpty {
                Text("Nothing planned for the rest of today. Add a task above, or ask Blink to plan your day (⌃⌥Space).")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !plan.overdue.isEmpty {
                    group("Overdue")
                    ForEach(plan.overdue) { row($0, time: $0.start.formatted(.dateTime.weekday(.abbreviated)), late: true) }
                }
                if !plan.anytime.isEmpty {
                    group("Anytime today")
                    ForEach(plan.anytime) { row($0, time: "", late: false) }
                }
                if !plan.timed.isEmpty, !(plan.overdue.isEmpty && plan.anytime.isEmpty) { group("Timeline") }
                ForEach(Array(plan.timed.enumerated()), id: \.element.id) { index, entry in
                    if index == plan.nowIndex { nowLine }
                    row(entry, time: entry.start.formatted(.dateTime.hour().minute()),
                        late: entry.kind != .meeting && entry.start < now)
                }
                if !plan.timed.isEmpty && plan.nowIndex == plan.timed.count { nowLine }
            }
        }
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }

    private var nowLine: some View {
        HStack(spacing: 8) {
            Text(now, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 56, alignment: .trailing)
            Circle().frame(width: 7, height: 7)
            Rectangle().frame(height: 1.5)
        }
        .foregroundStyle(.red)
        .accessibilityElement()
        .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
    }

    private func row(_ entry: DayEntry, time: String, late: Bool) -> some View {
        let tint: Color = switch entry.kind {
        case .meeting: .blue
        case .task: .orange
        case .reminder: .purple
        }
        return HStack(spacing: 10) {
            Text(time)
                .font(.callout.monospacedDigit())
                .foregroundStyle(late ? .orange : .secondary)
                .frame(width: 56, alignment: .trailing)
            Capsule().fill(tint).frame(width: 4, height: entry.kind == .meeting ? 36 : 24)
            if entry.kind != .meeting {
                Button { Task { await model.complete(id: entry.id) } } label: {
                    Image(systemName: "circle").imageScale(.large).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(entry.title) as done")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                if let event = entry.event, let end = entry.end {
                    Text("\(event.start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))\(event.location.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(entry.kind == .task ? "Task" : "Reminder").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let url = entry.event?.joinURL {
                Link("Join", destination: url).buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}

#endif
