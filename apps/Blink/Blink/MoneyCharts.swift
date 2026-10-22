// © Pexilim
#if os(macOS)
import BlinkKit
import Charts
import SwiftUI

/// Euros for chart axes: whole numbers, no cents.
private let axisEuros = FloatingPointFormatStyle<Double>.Currency(code: MoneyMath.currency).precision(.fractionLength(0))
private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

/// One headline number on the Money dashboard.
struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var detailColor: Color = .secondary
    var valueColor: Color = .primary

    init(title: String, value: Decimal, detail: String? = nil, detailColor: Color = .secondary, valueColor: Color = .primary) {
        self.init(title: title, text: value.formatted(.currency(code: MoneyMath.currency)), detail: detail, detailColor: detailColor, valueColor: valueColor)
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
            if let detail { Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Tokens.Radius.tile)
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
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", day + 1), y: .value("Spent", double(value)), series: .value("Month", "This month"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
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

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
