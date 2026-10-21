// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Today's widgets: small self-contained tiles, each with one job, an app-style icon, one big number or title, a short
/// caption and at most one round action, all the same height so the grid reads as one calm board.
struct TodayWidgetGrid: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            NextMeetingWidget(now: now)
            MailWidget()
            TasksWidget(now: now)
            WeekWidget(now: now)
            MoneyWidget(now: now)
            HabitsWidget()
            FocusWidget(now: now)
            if model.showsContent { PostsWidget() }
        }
    }
}

/// The frame every widget shares: icon and name on top, content below, one optional round action at the top right.
struct WidgetTile<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var open: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(height: 158)
        .cardSurface()
        .contentShape(.rect(cornerRadius: Tokens.Radius.card))
        .onTapGesture { open?() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A round action like the compose and join buttons in system widgets.
struct RoundAction: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// A big number with its small caption, the core of most widgets.
private struct BigValue: View {
    let value: String
    let caption: String
    var captionTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(captionTint).lineLimit(2)
        }
    }
}

private struct NextMeetingWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let next = model.agenda.today(now: now).first
        WidgetTile(title: "Next meeting", symbol: "calendar", tint: .red, open: { model.go(to: "calendar") }) {
            if let next {
                let minutes = Int((next.start.timeIntervalSince(now) / 60).rounded(.up))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.title).font(.headline).lineLimit(2)
                        Text("\(next.start.formatted(date: .omitted, time: .shortened))–\(next.end.formatted(date: .omitted, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Text(minutes <= 0 ? "Now" : minutes < 60 ? "In \(minutes) min" : next.location ?? "Later today")
                            .font(.caption.weight(.semibold)).foregroundStyle(minutes <= 10 ? .red : .secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let url = next.joinURL {
                        RoundAction(symbol: "video.fill", tint: .blue, label: "Join \(next.title)") { NSWorkspace.shared.open(url) }
                    }
                }
            } else {
                BigValue(value: "Free", caption: "No more meetings today")
            }
        }
    }
}

private struct MailWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let important = model.importantMail.filter { $0.status == .new }.count
        let waiting = model.awaitingReply.count
        WidgetTile(title: "Mail", symbol: "envelope.fill", tint: .blue, open: { model.go(to: "inbox") }) {
            HStack(alignment: .top) {
                BigValue(value: "\(important)", caption: important == 0 ? (waiting == 0 ? "Nothing needs you" : "\(waiting) waiting for your reply")
                         : "important · \(waiting) waiting for a reply", captionTint: important > 0 ? .red : .secondary)
                Spacer()
                RoundAction(symbol: "arrow.up.right", tint: .blue, label: "Open Inbox") { model.go(to: "inbox") }
            }
        }
    }
}

private struct TasksWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let tasks = model.openTasks.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }.prefix(3)
        WidgetTile(title: "Tasks · \(model.openTasks.count)", symbol: "checklist", tint: .orange, open: { model.go(to: "tasks") }) {
            if tasks.isEmpty {
                BigValue(value: "Clear", caption: "No open tasks")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tasks)) { task in
                        let overdue = (task.dueAt ?? .distantFuture) < now
                        HStack(spacing: 8) {
                            Button { Task { await model.toggle(task) } } label: {
                                Image(systemName: "circle").foregroundStyle(overdue ? .orange : task.dueAt == nil ? .green : .blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark \(task.title) done")
                            Text(task.title).font(.callout).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(overdue ? "Overdue" : task.dueAt.map { when($0) } ?? "")
                                .font(.caption.weight(overdue ? .semibold : .regular))
                                .foregroundStyle(overdue ? .orange : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func when(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

private struct WeekWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        WidgetTile(title: now.formatted(.dateTime.month(.wide)), symbol: "calendar.day.timeline.left", tint: .red, open: { model.go(to: "calendar") }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let today = cal.isDate(day, inSameDayAs: now)
                        let busy = model.calendarEvents.contains { cal.isDate($0.start, inSameDayAs: day) }
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(today ? .white : .secondary)
                            Text(day.formatted(.dateTime.day())).font(.callout.weight(.semibold)).foregroundStyle(today ? .white : .primary)
                            Circle().fill(busy ? (today ? Color.white : Color.red) : .clear).frame(width: 4, height: 4)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(today ? Color.accentColor : .clear, in: .rect(cornerRadius: 10, style: .continuous))
                    }
                }
                let count = model.calendarEvents.filter { $0.start >= now && $0.start < (days.last ?? now).addingTimeInterval(86_400) }.count
                Text(count == 0 ? "A free week" : "\(count) meeting\(count == 1 ? "" : "s") this week").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MoneyWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let today = HabitDay.key(now)
        let month = MoneyMath.summary(model.spends, today: today)
        let left = model.accounts.isEmpty ? nil : MoneyMath.leftAtMonthEnd(total: MoneyMath.totalBalance(model.accounts), summary: month, today: today)
        let week = WeekBars.lastWeek(now: now).map { day in
            WeekBars.euros(model.spends.filter { $0.spentOn == day }.reduce(Decimal.zero) { $0 + $1.amount })
        }
        let top = max(week.max() ?? 0, 1)
        WidgetTile(title: "Money", symbol: "creditcard.fill", tint: .green, open: { model.go(to: "money") }) {
            HStack(alignment: .bottom) {
                BigValue(value: month.total.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))),
                         caption: left.map { "spent · \($0.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))) left at month end" }
                            ?? "spent this month", captionTint: (left ?? 1) < 0 ? .red : .secondary)
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, value in
                        Capsule().fill(index == week.count - 1 ? Color.green : Color.green.opacity(0.35))
                            .frame(width: 6, height: max(4, 46 * value / top))
                    }
                }
                .frame(height: 46, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct HabitsWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let habits = model.habits.filter { model.isScheduledToday($0) }
        let done = habits.filter { model.answerToday($0) == .done }.count
        let best = model.habits.map { model.progress($0).streak }.max() ?? 0
        WidgetTile(title: "Habits", symbol: "flame.fill", tint: .pink, open: { model.go(to: "tasks") }) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(Color.pink.opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: habits.isEmpty ? 0 : Double(done) / Double(habits.count))
                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(habits.isEmpty ? "–" : "\(done)/\(habits.count)").font(.callout.weight(.semibold)).monospacedDigit()
                }
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habits.isEmpty ? "No habits today" : done == habits.count ? "All done" : "\(habits.count - done) to go")
                        .font(.headline)
                    Text(best > 0 ? "Best streak \(best) day\(best == 1 ? "" : "s")" : "Start a streak today").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FocusWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        WidgetTile(title: "Focus", symbol: "timer", tint: .purple) {
            HStack(alignment: .top) {
                if let timer = model.timer {
                    let left = Int(timer.remaining(now: now) / 60)
                    BigValue(value: "\(left) min", caption: "\(timer.label) · left")
                } else {
                    BigValue(value: "25 min", caption: "A focus round, then a break")
                }
                Spacer()
                if model.timer == nil {
                    RoundAction(symbol: "play.fill", tint: .purple, label: "Start a focus round") { model.startFocus() }
                } else {
                    RoundAction(symbol: "stop.fill", tint: .gray, label: "Stop the timer") { model.stopTimer() }
                }
            }
        }
    }
}

private struct PostsWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ready = model.readyToPost.count
        WidgetTile(title: "Posts", symbol: "megaphone.fill", tint: .orange, open: { model.go(to: "content") }) {
            HStack(alignment: .top) {
                BigValue(value: "\(ready)", caption: ready == 0 ? "Nothing waiting to post" : "ready to post")
                Spacer()
                RoundAction(symbol: "square.and.pencil", tint: .orange, label: "Open Content") { model.go(to: "content") }
            }
        }
    }
}
#endif
