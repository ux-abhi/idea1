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
                    HeroCard(now: now, showNotes: showNotes, adding: $addingTask, newTask: $newTask)
                    TodayWidgetGrid(now: now)
                    // One getting-started card at a time: setup while something's left, then the tips.
                    let steps = model.setupSteps
                    if steps.contains(where: { !$0.done }) { SetupCard(steps: steps) }
                    else if !tourDone { TipsCard { tourDone = true } }
                    lists(now: now)
                }
                .padding(24)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .background(BlinkCanvas())
        }
    }

    // MARK: Visual summary

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
        if let first = model.pending.first {
            DashCard("Waiting for you", trailing: model.pending.count > 1 ? "See all \(model.pending.count)" : nil,
                     action: showWaiting) {
                CardView(action: first, count: model.pending.count, problem: model.actionProblem, app: model)
            }
        }
        DayTimelineCard(plan: DayPlan(events: model.agenda.events, tasks: model.dueTasks, reminders: model.agenda.reminders, now: now), now: now)
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
                    .font(.system(size: 48, weight: .semibold, design: .rounded)) // type.numbers
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(next.map { "\(hero.caption) · \($0.start.formatted(date: .omitted, time: .shortened))\($0.location.map { " · \($0)" } ?? "")" } ?? hero.caption)
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
        .background(
            RadialGradient(colors: [Color.gray.opacity(0.32), .black], center: .topLeading, startRadius: 0, endRadius: 520),
            in: .rect(cornerRadius: Tokens.Radius.card + 6, style: .continuous)
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
