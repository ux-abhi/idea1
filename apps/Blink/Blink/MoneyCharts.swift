// © Pexilim
#if os(macOS)
import BlinkKit
import Charts
import SwiftUI

/// Euros for chart axes: whole numbers, no cents.
private let axisEuros = FloatingPointFormatStyle<Double>.Currency(code: "EUR").precision(.fractionLength(0))
private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

/// One headline number on the Money dashboard.
struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var detailColor: Color = .secondary
    var valueColor: Color = .primary

    init(title: String, value: Decimal, detail: String? = nil, detailColor: Color = .secondary, valueColor: Color = .primary) {
        self.init(title: title, text: value.formatted(.currency(code: "EUR")), detail: detail, detailColor: detailColor, valueColor: valueColor)
    }

    init(title: String, text: String, detail: String? = nil, detailColor: Color = .secondary, valueColor: Color = .primary) {
        (self.title, self.value, self.detail, self.detailColor, self.valueColor) = (title, text, detail, detailColor, valueColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// This month's running total against last month's, day by day, with the sum of the limits when there are any.
struct PaceChart: View {
    let thisMonth: [Decimal]   // cumulative, through today only
    let lastMonth: [Decimal]   // cumulative, the whole month
    let limit: Decimal?
    let daysInMonth: Int

    var body: some View {
        Chart {
            ForEach(Array(lastMonth.enumerated()), id: \.offset) { day, value in
                LineMark(x: .value("Day", day + 1), y: .value("Spent", double(value)), series: .value("Month", "Last month"))
                    .foregroundStyle(Color.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(Array(thisMonth.enumerated()), id: \.offset) { day, value in
                AreaMark(x: .value("Day", day + 1), y: .value("Spent", double(value)))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", day + 1), y: .value("Spent", double(value)), series: .value("Month", "This month"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let limit {
                RuleMark(y: .value("Limits", double(limit)))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) { Text("Your limits").font(.caption2).foregroundStyle(.red) }
            }
        }
        .chartXScale(domain: 1...max(lastMonth.count, daysInMonth))
        .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel(format: axisEuros) } }
        .frame(height: 200)
        .accessibilityLabel("Spending this month against last month")
        .accessibilityValue("\(thisMonth.last.map { double($0) }?.formatted(axisEuros) ?? "0") so far; last month by the same day \(lastMonth[safe: thisMonth.count - 1].map { double($0).formatted(axisEuros) } ?? "nothing")")
    }
}

/// What was spent each day this month, with the average as a line.
struct DailyBars: View {
    let daily: [Decimal]       // through today
    let average: Decimal
    let daysInMonth: Int

    var body: some View {
        Chart {
            ForEach(Array(daily.enumerated()), id: \.offset) { day, value in
                BarMark(x: .value("Day", day + 1), y: .value("Spent", double(value)), width: .fixed(7))
                    .foregroundStyle(day == daily.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .cornerRadius(3)
            }
            if average > 0 {
                RuleMark(y: .value("Average", double(average)))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: 0.5...(Double(daysInMonth) + 0.5))
        .chartXAxis { AxisMarks(values: [1, 8, 15, 22, 29].filter { $0 <= daysInMonth }) }
        .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel(format: axisEuros) } }
        .frame(height: 170)
        .accessibilityLabel("Spending per day this month")
    }
}

/// Where the month's money went, as a ring, with the total in the middle.
struct CategoryRing: View {
    let totals: [(category: SpendCategory, total: Decimal)]

    var body: some View {
        let sum = totals.reduce(Decimal.zero) { $0 + $1.total }
        Chart(totals, id: \.category) { row in
            SectorMark(angle: .value("Spent", double(row.total)), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("Category", row.category.title))
        }
        .chartLegend(position: .trailing, alignment: .center)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let rect = geo[frame]
                    VStack(spacing: 0) {
                        Text("Total").font(.caption2).foregroundStyle(.secondary)
                        Text(sum, format: .currency(code: "EUR").precision(.fractionLength(0))).font(.headline).monospacedDigit()
                    }
                    .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Spending by category")
        .accessibilityValue(totals.map { "\($0.category.title) \(double($0.total).formatted(axisEuros))" }.formatted())
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
