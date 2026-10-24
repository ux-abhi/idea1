// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Today, in order of urgency: the ink hero with the one number that matters, then anything that needs you, then the
/// rest of the day as one list, then four quiet tiles, and setup or tips last.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    let showWaiting: () -> Void
    let showNotes: () -> Void
    @AppStorage("blinkPanel") private var showPanel = true
    @State private var addingTask = false
    @State private var newTask = ""

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            ScrollView {
                VStack(spacing: 16) {
                    HeroCard(now: now, showNotes: showNotes, adding: $addingTask, newTask: $newTask)
                    actionCards
                    DayTimelineCard(plan: DayPlan(events: model.agenda.events, tasks: model.dueTasks, reminders: model.agenda.reminders, now: now),
                                    now: now, planDay: planDay)
                    TodayWidgetGrid(now: now)
                    // Setup while something's left (the first-run tour teaches the rest).
                    let steps = model.setupSteps
                    if steps.contains(where: { !$0.done }) { SetupCard(steps: steps) }
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(BlinkCanvas())
        }
    }

    private func planDay() {
        showPanel = true
        Task { await model.ask("Plan the rest of my day around my calendar and open tasks, with realistic times, and propose them.") }
    }

    /// What's waiting on the owner: the evening plan and the first approval.
    @ViewBuilder
    private var actionCards: some View {
        if model.serverBehind {
            DashCard("Update your server") {
                Text("This version of Blink needs the matching update on your server. Sign in with Supabase once; your notes, mail and money stay as they are.")
                    .foregroundStyle(.secondary)
                UpdateServerButton()
            }
        }
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
        if let first = model.pending.first {
            DashCard("Needs you", trailing: model.pending.count > 1 ? "See all \(model.pending.count)" : nil,
                     action: showWaiting) {
                CardView(action: first, count: 1, problem: model.actionProblem, app: model)
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
        let next = model.agenda.today(now: now).first
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(now, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Text(hero.value)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold)) // type.numbers
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(next.flatMap(\.location).map { "\(hero.caption) · \($0)" } ?? hero.caption)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let next, next.joinable(at: now), let url = next.joinURL {
                        Link(destination: url) {
                            Label("Join", systemImage: "video.fill").font(.callout.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.white, in: .capsule).foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                    PillButton(title: "Note", symbol: "square.and.pencil") {
                        model.focusNoteID = model.create(.note, title: "").id
                        showNotes()
                    }
                    PillButton(title: "Task", symbol: "plus") { adding = true }
                        .popover(isPresented: $adding, arrowEdge: .bottom) { quickTask }
                    if model.timer == nil {
                        PillButton(title: "Focus", symbol: "timer") { model.startFocus() }
                    } else {
                        PillButton(title: "Stop Timer", symbol: "stop.fill") { model.stopTimer() }
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            BlinkEyes(mood: next.map { $0.start.timeIntervalSince(now) < 600 ? .headsUp : .idle } ?? .idle)
                .frame(width: 96, height: 54)
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HorizonGlow().clipShape(.rect(cornerRadius: Tokens.Radius.notchOpen, style: .continuous)) }
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

/// Today on one time axis: overdue first, then things with no time, then the day in order with a now line.
private struct DayTimelineCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let now: Date
    let planDay: () -> Void

    var body: some View {
        DashCard("Your day") {
            if plan.isEmpty {
                HStack {
                    Text("Nothing else today.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Plan with Blink", systemImage: "sparkles", action: planDay).disabled(model.thinking)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !plan.overdue.isEmpty {
                    group("Overdue")
                    ForEach(plan.overdue) { row($0, time: $0.start.formatted(.dateTime.weekday(.abbreviated)), late: true) }
                }
                if !plan.anytime.isEmpty {
                    group("Today")
                    ForEach(plan.anytime) { row($0, time: "", late: false) }
                }
                if !plan.timed.isEmpty, !(plan.overdue.isEmpty && plan.anytime.isEmpty) { group("Later") }
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
        case .meeting: .teal
        case .task: Color.accentColor
        case .reminder: Color.secondary
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
                Link("Join", destination: url).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

#endif
