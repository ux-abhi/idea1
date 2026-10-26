// © Pexilim
import Foundation

/// What a spend was for. Matches the `transaction.category` check on the server.
public enum SpendCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, groceries, transport, housing, bills, shopping, health, fun, travel, education, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .food: "Food & Drinks"
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .housing: "Housing"
        case .bills: "Bills"
        case .shopping: "Shopping"
        case .health: "Health"
        case .fun: "Fun"
        case .travel: "Travel"
        case .education: "Education"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "cart"
        case .transport: "tram"
        case .housing: "house"
        case .bills: "doc.text"
        case .shopping: "bag"
        case .health: "cross.case"
        case .fun: "gamecontroller"
        case .travel: "airplane"
        case .education: "book"
        case .other: "square.grid.2x2"
        }
    }
}

/// One spend (`transaction`). Money is a Decimal, never a Double.
public struct Spend: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var amount: Decimal
    public var note: String
    public var category: SpendCategory
    /// The local day it was spent, "2026-10-12".
    public var spentOn: String
    /// The account it came off, if any.
    public var accountID: String?
    /// When it was entered: spends entered after an account's balance was set come off that balance.
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount, note, category
        case spentOn = "spent_on", accountID = "account_id", createdAt = "created_at"
    }
}

/// A bank, savings, cash or card account with the balance the owner last set (`money_account`).
public struct MoneyAccount: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case checking, savings, cash, card, other
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .checking: "Current account"
            case .savings: "Savings"
            case .cash: "Cash"
            case .card: "Credit card"
            case .other: "Other"
            }
        }
        public var symbol: String {
            switch self {
            case .checking: "building.columns"
            case .savings: "banknote"
            case .cash: "eurosign"
            case .card: "creditcard"
            case .other: "wallet.bifold"
            }
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind
    public var balance: Decimal
    public var balanceAt: Date
    public var isDefault: Bool
    /// Spends from this account entered since `balanceAt`, added up by the server (`money_account_now`).
    public var spentSince: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, balance
        case balanceAt = "balance_at", isDefault = "is_default", spentSince = "spent_since"
    }

    public init(id: String, name: String, kind: Kind, balance: Decimal, balanceAt: Date, isDefault: Bool, spentSince: Decimal? = nil) {
        (self.id, self.name, self.kind, self.balance, self.balanceAt, self.isDefault, self.spentSince) =
            (id, name, kind, balance, balanceAt, isDefault, spentSince)
    }
}

/// A spend the AI read from what the owner typed, not saved yet: the owner checks and edits it first.
public struct SpendDraft: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var amount: Decimal
    public var note: String
    public var category: SpendCategory
    public var spentOn: String
    public var accountID: String?

    enum CodingKeys: String, CodingKey { case amount, note, category, spentOn = "spent_on", accountID = "account_id" }

    public init(amount: Decimal, note: String, category: SpendCategory, spentOn: String, accountID: String? = nil) {
        (self.amount, self.note, self.category, self.spentOn, self.accountID) = (amount, note, category, spentOn, accountID)
    }
}

/// A monthly limit for one category (`budget`).
public struct Budget: Codable, Equatable, Sendable {
    public var category: SpendCategory
    public var monthlyLimit: Decimal

    enum CodingKeys: String, CodingKey { case category, monthlyLimit = "monthly_limit" }

    public init(category: SpendCategory, monthlyLimit: Decimal) {
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}

public enum MoneyMath {
    /// Every amount on screen is shown in this currency.
    // shortcut: one currency for the owner; read money_account.currency per account when a non-EUR owner appears.
    public static let currency = "EUR"

    /// "2026-10" for a "2026-10-12" day key.
    public static func month(of day: String) -> String { String(day.prefix(7)) }

    /// Spent per category in one month ("2026-10"), biggest first; categories with nothing spent are left out.
    public static func totals(_ spends: [Spend], month: String) -> [(category: SpendCategory, total: Decimal)] {
        let inMonth = spends.filter { self.month(of: $0.spentOn) == month }
        return Dictionary(grouping: inMonth, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(Decimal.zero) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    /// The whole month's total.
    public static func total(_ spends: [Spend], month: String) -> Decimal {
        spends.filter { self.month(of: $0.spentOn) == month }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Days in the month of a "2026-10" key.
    public static func daysIn(month: String, calendar: Calendar = .current) -> Int {
        guard let first = HabitDay.date(fromKey: month + "-01", calendar: calendar) else { return 30 }
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// The month before a "2026-10" key ("2026-09"; "2026-01" → "2025-12").
    public static func previous(month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        return parts[1] == 1 ? String(format: "%04d-12", parts[0] - 1) : String(format: "%04d-%02d", parts[0], parts[1] - 1)
    }

    /// Spent on each day of the month: index 0 is the 1st.
    public static func daily(_ spends: [Spend], month: String, calendar: Calendar = .current) -> [Decimal] {
        var days = Array(repeating: Decimal.zero, count: daysIn(month: month, calendar: calendar))
        for spend in spends where self.month(of: spend.spentOn) == month {
            if let day = Int(spend.spentOn.suffix(2)), days.indices.contains(day - 1) { days[day - 1] += spend.amount }
        }
        return days
    }

    /// Running total through the month.
    public static func cumulative(_ daily: [Decimal]) -> [Decimal] {
        var sum = Decimal.zero
        return daily.map { sum += $0; return sum }
    }

    /// The headline numbers for the month that `today` ("2026-10-12") is in.
    public struct Summary: Equatable, Sendable {
        public let total: Decimal
        public let today: Decimal
        /// Per day so far (today counts as a day).
        public let average: Decimal
        /// Where the month ends at this pace.
        public let forecast: Decimal
        /// Last month's total by the same day of the month, to compare like with like.
        public let lastMonthSoFar: Decimal
        public let lastMonthTotal: Decimal

        /// This month against last month by the same day: 0.12 = 12% more; nil when last month had nothing.
        public var change: Double? {
            lastMonthSoFar > 0 ? NSDecimalNumber(decimal: (total - lastMonthSoFar) / lastMonthSoFar).doubleValue : nil
        }
    }

    public static func summary(_ spends: [Spend], today: String, calendar: Calendar = .current) -> Summary {
        let month = month(of: today)
        let dayOfMonth = max(Int(today.suffix(2)) ?? 1, 1)
        let thisMonth = daily(spends, month: month, calendar: calendar)
        let lastMonth = daily(spends, month: previous(month: month), calendar: calendar)
        let total = thisMonth.reduce(Decimal.zero, +)
        let average = total / Decimal(dayOfMonth)
        return Summary(
            total: total,
            today: thisMonth.indices.contains(dayOfMonth - 1) ? thisMonth[dayOfMonth - 1] : 0,
            average: average,
            forecast: average * Decimal(thisMonth.count),
            lastMonthSoFar: lastMonth.prefix(dayOfMonth).reduce(Decimal.zero, +),
            lastMonthTotal: lastMonth.reduce(Decimal.zero, +))
    }

    /// An account's balance now: what the owner last set, minus spends from it entered since then (summed by the server).
    public static func balance(of account: MoneyAccount) -> Decimal {
        account.balance - (account.spentSince ?? 0)
    }

    /// All accounts together, now.
    public static func totalBalance(_ accounts: [MoneyAccount]) -> Decimal {
        accounts.reduce(Decimal.zero) { $0 + balance(of: $1) }
    }

    /// What's left on the last day of the month if spending carries on at this month's daily average.
    public static func leftAtMonthEnd(total: Decimal, summary: Summary, today: String, calendar: Calendar = .current) -> Decimal {
        let day = Int(today.suffix(2)) ?? 1
        let remaining = max(daysIn(month: month(of: today), calendar: calendar) - day, 0)
        return total - summary.average * Decimal(remaining)
    }

    /// Whole days the money lasts at this month's daily average; nil when nothing has been spent yet.
    public static func runwayDays(total: Decimal, average: Decimal) -> Int? {
        guard average > 0, total > 0 else { return average > 0 ? 0 : nil }
        return Int(NSDecimalNumber(decimal: total / average).doubleValue.rounded(.down))
    }

    /// A typed spend or limit ("8.50", "8,50", "€ 12", "1.234,56"): the same rules as a balance, but positive and
    /// under a million; nil otherwise ("1.250" is ambiguous and refused, never read as 1.25).
    public static func parseAmount(_ text: String) -> Decimal? {
        guard let value = parseBalance(text), value > 0, value < 1_000_000 else { return nil }
        return value
    }

    /// A typed account balance: may be zero or negative (a card you owe on); "1.234,56", "1250.40" and "-50" all work.
    public static func parseBalance(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // One number only: "2 x 4.50" must not become 24.50 (grouping like "1 234,56" or "1'234.50" is still one).
        guard trimmed.matches(of: /\d(?:[\d.,' \u{00A0}]*\d)?/).count == 1 else { return nil }
        // "-50", "€ -50" and macOS's "−50" (Unicode minus) are all negative.
        let negative = trimmed.first { $0.isNumber || $0 == "-" || $0 == "−" }.map { !$0.isNumber } ?? false
        // With a comma, dots group thousands (German style); without one, a dot is the decimal point.
        let plain = trimmed.contains(",") ? trimmed.replacingOccurrences(of: ".", with: "") : trimmed
        let digits = plain.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        // "1.250" or "1,234.56" are ambiguous; cents never have more than two digits, so refuse rather than guess.
        guard !digits.isEmpty, digits.filter({ $0 == "." }).count <= 1, (digits.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0) <= 2,
              let value = Decimal(string: digits), value < 100_000_000_000 else { return nil }
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return negative ? -rounded : rounded
    }

    /// Share of a limit used, 0…1+ (over 1 means over the limit).
    public static func used(_ total: Decimal, of limit: Decimal) -> Double {
        limit > 0 ? NSDecimalNumber(decimal: total / limit).doubleValue : 0
    }
}
