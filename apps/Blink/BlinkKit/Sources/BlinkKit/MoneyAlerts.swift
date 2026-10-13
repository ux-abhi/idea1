// © Pexilim
import Foundation

/// What the notch says about money on its own: a category reaching 80% or 100% of its monthly limit (once each per month),
/// and last week's spending in one line (once per week, on the first sync of the new week).
public enum MoneyAlerts {
    public struct Alert: Equatable, Sendable {
        /// Remembered once told ("2026-10:food:80"), so each is said once.
        public let key: String
        public let text: String
        public let over: Bool
    }

    /// Limits crossed this month that haven't been told yet; at 100% only the "over" one (not also 80%).
    public static func crossed(_ spends: [Spend], budgets: [Budget], month: String, told: Set<String>) -> [Alert] {
        let totals = Dictionary(uniqueKeysWithValues: MoneyMath.totals(spends, month: month).map { ($0.category, $0.total) })
        return budgets.compactMap { budget in
            let spent = totals[budget.category] ?? 0
            let used = MoneyMath.used(spent, of: budget.monthlyLimit)
            let limit = budget.monthlyLimit.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))
            if used >= 1 {
                let key = "\(month):\(budget.category.rawValue):100"
                guard !told.contains(key) else { return nil }
                return Alert(key: key, text: "\(budget.category.title) is over its \(limit) limit: \(spent.formatted(.currency(code: MoneyMath.currency))) this month.", over: true)
            }
            if used >= 0.8 {
                let key = "\(month):\(budget.category.rawValue):80"
                guard !told.contains(key) else { return nil }
                return Alert(key: key, text: "\(budget.category.title) is at \(Int((used * 100).rounded(.down)))% of its \(limit) limit.", over: false)
            }
            return nil
        }
    }

    /// What to remember as said: this month's limit keys plus the newest week key; older ones can never come back, so the
    /// list stays a handful of entries however long Blink runs.
    public static func remember(_ told: Set<String>, adding said: [String], month: String) -> [String] {
        let all = told.union(said)
        let newestWeek = all.filter { $0.hasPrefix("week-") }.max { weekOrder($0) < weekOrder($1) }
        return (all.filter { $0.hasPrefix(month) } + [newestWeek].compactMap { $0 }).sorted()
    }

    /// "week-2027-9" → 2027 * 100 + 9, so weeks compare by number, not by text.
    static func weekOrder(_ key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[1]), let week = Int(parts[2]) else { return 0 }
        return year * 100 + week
    }

    /// Last week (Monday to Sunday before `today`) in one line, with the top three categories; nil if nothing was spent.
    public static func lastWeek(_ spends: [Spend], today: Date, calendar: Calendar = .current) -> (key: String, text: String)? {
        var cal = calendar
        cal.firstWeekday = 2 // weeks start on Monday
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today),
              let start = cal.date(byAdding: .day, value: -7, to: thisWeek.start) else { return nil }
        let days = Set((0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map { HabitDay.key($0, calendar: cal) })
        let week = spends.filter { days.contains($0.spentOn) }
        guard !week.isEmpty else { return nil }
        let total = week.reduce(Decimal.zero) { $0 + $1.amount }
        let top = Dictionary(grouping: week, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(Decimal.zero) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }.prefix(3)
            .map { "\($0.category.title) \($0.total.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))))" }
        let week_ = cal.component(.weekOfYear, from: start), year = cal.component(.yearForWeekOfYear, from: start)
        return ("week-\(year)-\(week_)", "Last week: \(total.formatted(.currency(code: MoneyMath.currency))). \(top.joined(separator: ", ")).")
    }
}
