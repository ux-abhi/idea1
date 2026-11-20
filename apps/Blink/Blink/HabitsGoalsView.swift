// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Habits & Goals (ADR-0002 §8): the month's pixel board on top, one row per habit in its own color to compare at a
/// glance; a few numbers; then this week's goals, each ticked by hand. "Plan my week" turns what the owner wants done
/// into the week's goals.
struct HabitsGoalsView: View {
    @Environment(AppModel.self) private var model
    @State private var newHabit = ""

    var body: some View {
        @Bindable var model = model
        let goals = model.weeklyGoals.sorted { $0.position < $1.position }
        DashPage("Habits & Goals", summary: model.habitToday.formatted(.dateTime.month(.wide).year())) {
            DashCard("This month") {
                if model.habits.isEmpty {
                    Text("Small things you do most days: read, stretch, walk. Each gets its own color and a square a day.")
                        .foregroundStyle(.secondary)
                } else {
                    HabitBoard()
                }
                AddField(placeholder: "Add a habit, e.g. \"Read 20 pages\"", text: $newHabit) {
                    let name = newHabit.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    newHabit = ""
                    Task { await model.addHabit(name) }
                }
            }
            if !model.habits.isEmpty || !goals.isEmpty { StatChips(goals: goals) }
            DashCard("This week", trailing: "Plan My Week", action: { model.planningWeek = true }) {
                if goals.isEmpty {
                    Text("What do you want to get done this week? Plan your week and tick each goal off here.")
                        .foregroundStyle(.secondary)
                }
                CardRows(items: goals) { GoalRow(goal: $0) }
                if WeekLookBack.isShowing(now: .now), goals.contains(where: { !$0.isDone }) {
                    Divider()
                    HStack {
                        Text("Week's nearly over. Move what's left to next week?").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Move to Next Week") { Task { await model.carryOverGoals() } }
                    }
                }
            }
            if let problem = model.saveProblem { Text(problem).foregroundStyle(.orange) }
        }
        .sheet(isPresented: $model.planningWeek) { PlanWeekSheet() }
    }
}

/// The colors habits and goals take, in order: Apple's system colors (purple is Content's, so it's left out).
enum PixelPalette {
    static let colors: [Color] = [.green, .blue, .orange, .pink, .teal, .yellow, .mint, .red, .cyan, .indigo, .brown]
    static func color(_ index: Int) -> Color { colors[index % colors.count] }
}

/// The month as pixels: one row per habit, one square per day, lit in the habit's color when done. Future days are
/// faint outlines, today's column is marked, and each row ends with its streak. Click a square to mark that day. The
/// habit rules apply (§36.2): a missed day is just a dim square, never a red one.
struct HabitBoard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = Calendar.current
        let today = model.habitToday
        let month = cal.dateInterval(of: .month, for: today)!
        let days = cal.range(of: .day, in: .month, for: today)!.count
        let todayIndex = cal.component(.day, from: today) - 1
        GeometryReader { geo in
            let nameWidth: CGFloat = 130, streakWidth: CGFloat = 52, gap: CGFloat = 3
            let square = max(8, min(18, (geo.size.width - nameWidth - streakWidth - gap * CGFloat(days)) / CGFloat(days)))
            VStack(alignment: .leading, spacing: 6) {
                // Day numbers: the 1st, every fifth, and the last.
                HStack(spacing: gap) {
                    Color.clear.frame(width: nameWidth, height: 1)
                    ForEach(0..<days, id: \.self) { i in
                        Text(i == 0 || (i + 1) % 5 == 0 || i == days - 1 ? "\(i + 1)" : "")
                            .font(.system(size: 9, weight: i == todayIndex ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(i == todayIndex ? .primary : .secondary)
                            .frame(width: square)
                            .fixedSize()
                    }
                }
                .accessibilityHidden(true)
                ForEach(Array(model.habits.enumerated()), id: \.element.id) { index, habit in
                    BoardRow(habit: habit, color: PixelPalette.color(index), start: month.start, days: days,
                             todayIndex: todayIndex, square: square, gap: gap, nameWidth: nameWidth, streakWidth: streakWidth)
                }
            }
        }
        .frame(height: CGFloat(model.habits.count) * 24 + 20)
    }
}

private struct BoardRow: View {
    @Environment(AppModel.self) private var model
    let habit: Habit
    let color: Color
    let start: Date
    let days: Int
    let todayIndex: Int
    let square: CGFloat
    let gap: CGFloat
    let nameWidth: CGFloat
    let streakWidth: CGFloat
    @State private var renaming = false
    @State private var newName = ""
    @State private var hovering = false

    var body: some View {
        let cal = Calendar.current
        let streak = model.progress(habit).streak
        HStack(spacing: gap) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(habit.name).font(.callout).lineLimit(1)
            }
            .frame(width: nameWidth, alignment: .leading)
            ForEach(0..<days, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start) ?? start
                let answer = model.habitAnswers[habit.id]?[HabitDay.key(day)]
                let planned = habit.weekdays.contains(cal.component(.weekday, from: day))
                let future = i > todayIndex
                square(answer: answer, planned: planned, future: future, today: i == todayIndex)
                    .overlay {
                        // Any past or present day can be marked; before the habit existed and the future can't.
                        if !future, habit.canAnswer(day) {
                            Menu {
                                Button("Done", systemImage: "checkmark.circle") { Task { await model.answer(habit, .done, on: day) } }
                                Button("Not Done", systemImage: "circle.dashed") { Task { await model.answer(habit, .notToday, on: day) } }
                                Button("Skipped", systemImage: "forward.end") { Task { await model.answer(habit, .skipped, on: day) } }
                                if answer != nil { Button("Clear") { Task { await model.answer(habit, nil, on: day) } } }
                            } label: { Color.clear.contentShape(.rect) }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                            .help("\(habit.name), \(day.formatted(.dateTime.weekday(.wide).day().month()))")
                        }
                    }
            }
            HStack(spacing: 3) {
                if streak > 0 {
                    Image(systemName: "flame.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    Text("\(streak)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(width: streakWidth - 22, alignment: .trailing)
            Menu { actions } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovering ? 1 : 0.35)
                .help("Habit options")
                .accessibilityLabel("\(habit.name) options")
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(streak) day streak")
        .contextMenu { actions }
        .alert("Rename Habit", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await model.rename(habit, to: newName) } }
        }
    }

    /// The same choices in the ⋯ menu and on right-click.
    @ViewBuilder private var actions: some View {
        Button("Every Day") { Task { await model.setWeekdays(habit, to: Array(1...7)) } }
        Button("Weekdays") { Task { await model.setWeekdays(habit, to: [2, 3, 4, 5, 6]) } }
        Button("Weekends") { Task { await model.setWeekdays(habit, to: [1, 7]) } }
        Divider()
        Button("Rename…", systemImage: "pencil") { newName = habit.name; renaming = true }
        Button("Remove Habit", systemImage: "trash", role: .destructive) { Task { await model.archive(habit) } }
    }

    private func square(answer: HabitAnswer?, planned: Bool, future: Bool, today: Bool) -> some View {
        RoundedRectangle(cornerRadius: square / 4, style: .continuous)
            .fill(answer == .done ? color : future ? Color.clear : Color.secondary.opacity(planned ? 0.18 : 0.07))
            .overlay(RoundedRectangle(cornerRadius: square / 4, style: .continuous)
                .strokeBorder(future ? Color.secondary.opacity(0.18) : answer == .skipped ? color.opacity(0.7) : .clear, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: square / 4 + 1, style: .continuous)
                .strokeBorder(today ? Color.primary.opacity(0.7) : .clear, lineWidth: 1.5).padding(-2))
            .frame(width: square, height: square)
    }
}

/// A few numbers under the board: this week's habit days kept, the best running streak, goals done.
private struct StatChips: View {
    @Environment(AppModel.self) private var model
    let goals: [WeeklyGoal]

    var body: some View {
        let cal = Calendar.current
        let weekStart = HabitDay.date(fromKey: model.thisWeek) ?? model.habitToday
        let daysSoFar = (cal.dateComponents([.day], from: weekStart, to: model.habitToday).day ?? 0) + 1
        let week = (0..<daysSoFar).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let planned = model.habits.flatMap { h in week.filter { h.weekdays.contains(cal.component(.weekday, from: $0)) && h.canAnswer($0) }.map { (h, $0) } }
        let kept = planned.filter { model.habitAnswers[$0.0.id]?[HabitDay.key($0.1)] == .done }.count
        let best = model.habits.map { model.progress($0).streak }.max() ?? 0
        HStack(spacing: 10) {
            if !model.habits.isEmpty {
                chip("\(kept) of \(planned.count)", "habit days this week", "checkmark.circle.fill", .green)
                chip("\(best)", best == 1 ? "day, best streak" : "days, best streak", "flame.fill", .orange)
            }
            if !goals.isEmpty {
                chip("\(goals.filter(\.isDone).count) of \(goals.count)", "goals done", "flag.fill", .blue)
            }
            Spacer()
        }
    }

    private func chip(_ value: String, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .cardSurface(radius: Tokens.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}

/// When the week's look back shows: Friday onwards (the week ends Sunday).
enum WeekLookBack {
    static func isShowing(now: Date, calendar: Calendar = .current) -> Bool {
        [6, 7, 1].contains(calendar.component(.weekday, from: now)) // Friday, Saturday, Sunday
    }
}

/// One goal: a check for a one-off, or a colored pixel bar filling up with +1 and −1 for a counter.
struct GoalRow: View {
    @Environment(AppModel.self) private var model
    let goal: WeeklyGoal
    @State private var hovering = false

    var body: some View {
        let color = PixelPalette.color(goal.position + 3) // offset from the habits' first colors, so goals stand apart
        HStack(spacing: 12) {
            if goal.isCheck {
                Button { Task { await model.bump(goal, by: goal.isDone ? -1 : 1) } } label: {
                    Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(goal.isDone ? color : .secondary).imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goal.isDone ? "Mark as not done" : "Mark as done")
            }
            Text(goal.title).strikethrough(goal.isDone).foregroundStyle(goal.isDone ? .secondary : .primary)
            if let space = model.spaces.first(where: { $0.id == goal.spaceID }) { SpaceChip(space: space) }
            Spacer()
            if !goal.isCheck {
                PixelProgress(done: goal.doneCount, of: goal.target, color: color)
                Text("\(goal.doneCount)/\(goal.target)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button("One Less", systemImage: "minus") { Task { await model.bump(goal, by: -1) } }
                    .labelStyle(.iconOnly).disabled(goal.doneCount == 0)
                Button("One More", systemImage: "plus") { Task { await model.bump(goal, by: 1) } }
                    .labelStyle(.iconOnly).disabled(goal.isDone)
            }
            Menu { actions } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovering ? 1 : 0.35)
                .help("Goal options")
                .accessibilityLabel("\(goal.title) options")
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityValue(goal.isCheck ? (goal.isDone ? "Done" : "Not done") : "\(goal.doneCount) of \(goal.target)")
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        if goal.doneCount > 0 { Button("Start Over", systemImage: "arrow.counterclockwise") { Task { await model.bump(goal, by: -goal.doneCount) } } }
        Button("Delete Goal", systemImage: "trash", role: .destructive) { Task { await model.deleteGoal(goal) } }
    }
}

/// A counter as a row of squares lit in the goal's color as it fills (up to 15; more show as the number alone).
struct PixelProgress: View {
    let done: Int
    let of: Int
    var color: Color = .green

    var body: some View {
        if of <= 15 {
            HStack(spacing: 3) {
                ForEach(0..<of, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(i < done ? color : Color.secondary.opacity(0.18))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Plan my week: type what you want to get done, one per line; Blink reads the counts ("5 posts", "gym 3 times") and
/// shows the goals to check before adding them. Read on this Mac: nothing is sent anywhere.
struct PlanWeekSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let goals = WeekPlan.goals(from: text)
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan your week").font(.title2.bold())
            Text("What do you want to get done this week? One goal per line. Add a number to count it, like “Create 5 posts” or “Gym 3 times”.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .accessibilityLabel("This week's goals, one per line")
            if !goals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                        HStack {
                            Text(goal.title)
                            Spacer()
                            if goal.target == 1 { Text("check off").foregroundStyle(.secondary) }
                            else { PixelProgress(done: 0, of: goal.target, color: PixelPalette.color(model.weeklyGoals.count + i + 3)) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(goals.count <= 1 ? "Add Goal" : "Add \(goals.count) Goals") {
                    Task { await model.addGoals(goals); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(goals.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
#endif
