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

    enum CodingKeys: String, CodingKey { case id, amount, note, category, spentOn = "spent_on" }
}

/// A spend the AI read from what the owner typed, not saved yet: the owner checks and edits it first.
public struct SpendDraft: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var amount: Decimal
    public var note: String
    public var category: SpendCategory
    public var spentOn: String

    enum CodingKeys: String, CodingKey { case amount, note, category, spentOn = "spent_on" }

    public init(amount: Decimal, note: String, category: SpendCategory, spentOn: String) {
        (self.amount, self.note, self.category, self.spentOn) = (amount, note, category, spentOn)
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

    /// A typed amount ("8.50", "8,50", "€ 12") in cents precision; nil if it isn't a positive amount.
    public static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        guard cleaned.filter({ $0 == "." }).count <= 1, let value = Decimal(string: cleaned), value > 0, value < 1_000_000 else { return nil }
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded
    }

    /// Share of a limit used, 0…1+ (over 1 means over the limit).
    public static func used(_ total: Decimal, of limit: Decimal) -> Double {
        limit > 0 ? NSDecimalNumber(decimal: total / limit).doubleValue : 0
    }
}
