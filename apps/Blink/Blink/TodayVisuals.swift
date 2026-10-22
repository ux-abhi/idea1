// © Pexilim
#if os(macOS)
import BlinkKit
import Charts
import SwiftUI

/// Today, shown rather than told: rings for the day, a strip of the day's hours, the week as bars, setup as a ring.

private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
