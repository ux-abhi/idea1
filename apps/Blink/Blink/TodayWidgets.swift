// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Today's tiles: four quiet ones (Mail, Tasks, Money, Habits), plus Posts when something is ready. Each has one job,
/// a grey icon, one number and a short caption; colour only when something is wrong or done.
struct TodayWidgetGrid: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            MailWidget()
            TasksWidget(now: now)
            MoneyWidget(now: now)
            HabitsWidget()
            if model.showsContent && !model.readyToPost.isEmpty { PostsWidget() }
        }
    }
}

/// The frame every widget shares: icon and name on top, content below, one optional round action at the top right.
struct WidgetTile<Content: View>: View {
    let title: String
    let symbol: String
    var open: (() -> Void)?
    @ViewBuilder let content: Content
    @ScaledMetric private var badge = 24.0
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: badge, height: badge)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if open != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0).accessibilityHidden(true)
                }
            }
            content.frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 140)
        .cardSurface(radius: Tokens.Radius.tile)
        .background(Color.primary.opacity(hovering && open != nil ? 0.03 : 0), in: .rect(cornerRadius: Tokens.Radius.tile))
        .contentShape(.rect(cornerRadius: Tokens.Radius.tile))
        .onTapGesture { open?() }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(named: "Open \(title)") { open?() }
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
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(captionTint).lineLimit(2)
        }
    }
}

private struct MailWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let important = model.importantMail.filter { $0.status == .new }.count
        let waiting = model.awaitingReply.count
        WidgetTile(title: "Mail", symbol: "envelope", open: { model.go(to: "inbox") }) {
            BigValue(value: "\(important)", caption: important == 0 ? "Nothing important" : "important")
            if waiting > 0 { Text("\(waiting) to reply").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct TasksWidget: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let tasks = model.openTasks.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }.prefix(3)
        WidgetTile(title: "Tasks · \(model.openTasks.count)", symbol: "checklist", open: { model.go(to: "tasks") }) {
            if tasks.isEmpty {
                BigValue(value: "Clear", caption: "No open tasks")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tasks)) { task in
                        let overdue = (task.dueAt ?? .distantFuture) < now
                        HStack(spacing: 8) {
                            Button { Task { await model.toggle(task) } } label: {
                                Image(systemName: "circle").foregroundStyle(overdue ? Color.red : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark \(task.title) done")
                            Text(task.title).font(.callout).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(overdue ? "Overdue" : task.dueAt.map { when($0) } ?? "")
                                .font(.caption.weight(overdue ? .semibold : .regular))
                                .foregroundStyle(overdue ? .red : .secondary)
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
        WidgetTile(title: "Money", symbol: "creditcard", open: { model.go(to: "money") }) {
            HStack(alignment: .bottom) {
                BigValue(value: month.total.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))),
                         caption: left.flatMap { $0 < 0 ? "spent · \($0.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))) short at month end" : nil }
                            ?? "spent this month", captionTint: (left ?? 1) < 0 ? .red : .secondary)
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, value in
                        Capsule().fill(index == week.count - 1 ? Color.accentColor : Color.secondary.opacity(0.35))
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
        WidgetTile(title: "Habits", symbol: "flame", open: { model.go(to: "tasks") }) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    Circle().trim(from: 0, to: habits.isEmpty ? 0 : Double(done) / Double(habits.count))
                        .stroke(done == habits.count && !habits.isEmpty ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
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

private struct PostsWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ready = model.readyToPost.count
        WidgetTile(title: "Posts", symbol: "megaphone", open: { model.go(to: "content") }) {
            BigValue(value: "\(ready)", caption: "ready to post")
        }
    }
}
#endif
