// © Pexilim
#if os(macOS)
import BlinkKit
import Charts
import SwiftUI

/// Today, shown rather than told: rings for the day, a strip of the day's hours, the week as bars, setup as a ring.

private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

/// Three rings, Activity style: meetings behind you, tasks done, habits done. Numbers beside them, no sentences.
struct DayRings: View {
    struct Ring: Identifiable {
        let id: String
        let done: Int
        let total: Int
        let tint: Color
        var fraction: Double { total == 0 ? 0 : min(Double(done) / Double(total), 1) }
    }

    let rings: [Ring]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let size = 132 - CGFloat(index) * 30
                    Circle().stroke(ring.tint.opacity(0.18), lineWidth: 11).frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: ring.fraction)
                        .stroke(ring.tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                        .animation(reduceMotion ? nil : .spring(duration: 0.8), value: ring.fraction)
                }
            }
            .frame(width: 136, height: 136)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rings) { ring in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ring.id).font(.caption).foregroundStyle(.secondary)
                        Text(ring.total == 0 ? "—" : "\(ring.done)/\(ring.total)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(ring.tint)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(ring.id): \(ring.total == 0 ? "none today" : "\(ring.done) of \(ring.total)")")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
    }
}

/// The day's hours as one strip: meetings as blocks, tasks and reminders as dots, a line for now.
struct DayStrip: View {
    let plan: DayPlan
    let now: Date
    var startHour = 7
    var endHour = 23

    var body: some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .hour, value: startHour, to: day)!
        let end = cal.date(byAdding: .hour, value: endHour, to: day)!
        GeometryReader { geo in
            let width = geo.size.width
            let x: (Date) -> CGFloat = { width * CGFloat(min(max($0.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(.quaternary).frame(height: 30).offset(y: 14)
                ForEach(plan.timed) { entry in
                    if entry.kind == .meeting, let finish = entry.end {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(finish < now ? Color.mint.opacity(0.4) : Color.mint)
                            .frame(width: max(x(finish) - x(entry.start), 6), height: 30)
                            .offset(x: x(entry.start), y: 14)
                            .help("\(entry.title), \(entry.start.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Circle()
                            .fill(entry.start < now ? Color.orange : Color.accentColor)
                            .frame(width: 10, height: 10)
                            .offset(x: x(entry.start) - 5, y: 24)
                            .help("\(entry.title), \(entry.start.formatted(date: .omitted, time: .shortened))")
                    }
                }
                if now > start && now < end {
                    Rectangle().fill(.red).frame(width: 2, height: 42).offset(x: x(now) - 1, y: 8)
                    Text(now, format: .dateTime.hour().minute()).font(.caption2.weight(.semibold)).foregroundStyle(.red)
                        .offset(x: min(max(x(now) - 14, 0), width - 32), y: -8)
                }
                ForEach(Array(stride(from: startHour, through: endHour, by: 4)), id: \.self) { hour in
                    Text(cal.date(byAdding: .hour, value: hour, to: day)!, format: .dateTime.hour()).font(.caption2).foregroundStyle(.tertiary)
                        .offset(x: min(x(cal.date(byAdding: .hour, value: hour - startHour, to: start)!), width - 30), y: 50)
                }
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your day")
        .accessibilityValue("\(plan.timed.filter { $0.kind == .meeting }.count) meetings, \(plan.timed.filter { $0.kind != .meeting }.count) tasks and reminders with a time")
    }
}

/// The last 7 days as bars: one value per day, today highlighted.
struct WeekBars: View {
    let title: String
    let days: [(day: String, value: Double)]   // oldest first, last = today
    let tint: Color
    var format: (Double) -> String = { $0.formatted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(format(days.map(\.value).reduce(0, +))).font(.headline).monospacedDigit().foregroundStyle(tint)
            }
            // Bars by position, labelled with the weekday's letter: "T" for Tuesday and Thursday must stay two bars.
            Chart(Array(days.enumerated()), id: \.offset) { index, day in
                BarMark(x: .value("Day", index), y: .value(title, day.value), width: .ratio(0.7))
                    .foregroundStyle(index == days.count - 1 ? tint : tint.opacity(0.4))
                    .cornerRadius(3)
            }
            .chartXScale(domain: -0.5...(Double(days.count) - 0.5))
            .chartXAxis {
                AxisMarks(values: Array(days.indices)) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), days.indices.contains(i) {
                            Text(HabitDay.date(fromKey: days[i].day).map { $0.formatted(.dateTime.weekday(.narrow)) } ?? "")
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 90)
            .accessibilityLabel(title)
            .accessibilityValue(days.map { "\(HabitDay.date(fromKey: $0.day).map { $0.formatted(.dateTime.weekday(.wide)) } ?? $0.day): \(format($0.value))" }
                .joined(separator: ", "))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
    }
}

/// "Setup 3 of 6" as a ring, and the next missing steps as one-click rows.
struct SetupCard: View {
    @Environment(AppModel.self) private var model
    let steps: [SetupStep]

    var body: some View {
        let done = steps.filter(\.done).count
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: Double(done) / Double(max(steps.count, 1)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(done)/\(steps.count)").font(.system(.headline, design: .rounded)).monospacedDigit()
                    Text("set up").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup, \(done) of \(steps.count) done")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps.filter { !$0.done }.prefix(3)) { step in
                    HStack(spacing: 10) {
                        Image(systemName: step.symbol).foregroundStyle(Color.accentColor).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(step.title).font(.callout.weight(.medium))
                            Text(step.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(step.action) { model.go(to: step.destination) }.controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
    }
}

extension WeekBars {
    /// The last 7 local days as keys, oldest first.
    static func lastWeek(now: Date = .now) -> [String] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }.map { HabitDay.key($0) }
    }

    static func euros(_ d: Decimal) -> Double { double(d) }
}
#endif
