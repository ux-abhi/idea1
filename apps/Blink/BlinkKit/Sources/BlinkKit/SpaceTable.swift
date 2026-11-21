// © Pexilim
import Foundation

/// A table block's column (a property, in Notion's words): a name, what kind of value it holds, and for a Category its
/// options.
public struct SpaceColumn: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, category, tags, checkbox, date, email, link
        public var title: String {
            switch self {
            case .text: "Text"
            case .category: "Category"
            case .tags: "Tags"
            case .checkbox: "Checkbox"
            case .date: "Date"
            case .email: "Email"
            case .link: "URL"
            }
        }
    }
    public let id: String
    public var name: String
    public var kind: Kind
    /// A Category's choices, in order (cells hold the option's id, so renaming an option changes every card at once).
    public var options: [SpaceOption]?
    /// How wide the column is drawn in a table, in points; nil is the standard width.
    public var width: Double?

    public static let widths: [(name: String, value: Double)] = [("Narrow", 120), ("Medium", 180), ("Wide", 280), ("Extra Wide", 400)]

    public init(id: String = String(UUID().uuidString.lowercased().prefix(8)), name: String, kind: Kind = .text, options: [SpaceOption]? = nil) {
        (self.id, self.name, self.kind, self.options) = (id, name, kind, options)
    }
}

/// One choice of a Category column, with an Apple system colour by name.
public struct SpaceOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    public static let colors = ["gray", "brown", "orange", "yellow", "green", "teal", "blue", "indigo", "pink", "red"]
    public let id: String
    public var name: String
    public var color: String

    public init(id: String = String(UUID().uuidString.lowercased().prefix(8)), name: String, color: String) {
        (self.id, self.name, self.color) = (id, name, color)
    }
}

/// A saved way of looking at a table: as rows or as a board grouped by a Category, with its own filters and sort.
public struct SpaceTableView: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case table, board }
    public let id: String
    public var name: String
    public var kind: Kind
    /// The Category column a board is grouped by.
    public var groupBy: String?
    public var filters: [RowFilter]
    public var sortColumn: String?
    public var sortAscending: Bool
    /// Columns this view doesn't show (they're still there, and still in other views and on the card).
    public var hidden: [String]?

    public init(id: String = String(UUID().uuidString.lowercased().prefix(8)), name: String, kind: Kind, groupBy: String? = nil,
                filters: [RowFilter] = [], sortColumn: String? = nil, sortAscending: Bool = true) {
        (self.id, self.name, self.kind, self.groupBy) = (id, name, kind, groupBy)
        (self.filters, self.sortColumn, self.sortAscending) = (filters, sortColumn, sortAscending)
    }
}

/// One filter: a column, how to compare, and the value ("is Ready", "contains Berlin", "is checked").
public struct RowFilter: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Op: String, Codable, CaseIterable, Sendable {
        case contains, is_, isNot, isEmpty, isNotEmpty, checked, unchecked
        public var title: String {
            switch self {
            case .contains: "contains"
            case .is_: "is"
            case .isNot: "is not"
            case .isEmpty: "is empty"
            case .isNotEmpty: "is not empty"
            case .checked: "is checked"
            case .unchecked: "is not checked"
            }
        }
        /// The comparisons that make sense for a kind of column.
        public static func choices(for kind: SpaceColumn.Kind) -> [Op] {
            switch kind {
            case .checkbox: [.checked, .unchecked]
            case .category: [.is_, .isNot, .isEmpty, .isNotEmpty]
            default: [.contains, .is_, .isEmpty, .isNotEmpty]
            }
        }
        public var needsValue: Bool { ![.isEmpty, .isNotEmpty, .checked, .unchecked].contains(self) }
    }
    public let id: String
    public var column: String
    public var op: Op
    public var value: String

    public init(id: String = String(UUID().uuidString.lowercased().prefix(8)), column: String, op: Op, value: String = "") {
        (self.id, self.column, self.op, self.value) = (id, column, op, value)
    }
}

/// One row of a table block: column id → text.
public struct SpaceRow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let blockID: String
    public var position: Double
    public var cells: [String: String]

    enum CodingKeys: String, CodingKey { case id, position, cells; case blockID = "block_id" }

    public init(id: String = UUID().uuidString.lowercased(), blockID: String, position: Double, cells: [String: String] = [:]) {
        (self.id, self.blockID, self.position, self.cells) = (id, blockID, position, cells)
    }
}

/// Tables in Spaces: reading a CSV into one, writing one out, and turning its rows into bulk mail contacts.
public enum SpaceTable {
    public static let rowLimit = 2000, columnLimit = 30, cellLimit = 1000, noteLimit = 2000 // a row is capped at 8 KB on the server, with all its cells
    /// The cell that holds a card's own note (not a column, so it never shows as one).
    public static let noteKey = "_note"

    /// A CSV (or tab-separated text) with a header row as columns and rows; column kinds guessed from names and values.
    public static func fromCSV(_ text: String) -> (columns: [SpaceColumn], rows: [[String: String]]) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first else { return ([], []) }
        let separator: Character = header.contains("\t") ? "\t" : header.filter { $0 == ";" }.count > header.filter { $0 == "," }.count ? ";" : ","
        let names = ContactList.cells(header, separator).prefix(columnLimit)
        let values = lines.dropFirst().prefix(rowLimit).map { ContactList.cells($0, separator) }
        let columns = names.enumerated().map { i, name in
            let sample = values.compactMap { i < $0.count ? $0[i] : nil }.filter { !$0.isEmpty }.prefix(20)
            let lower = name.lowercased()
            let kind: SpaceColumn.Kind =
                lower.contains("mail") || (!sample.isEmpty && sample.allSatisfy(ContactList.isAddress)) ? .email
                : lower.contains("tag") ? .tags
                : ["website", "url", "link", "site"].contains(where: lower.contains) || (!sample.isEmpty && sample.allSatisfy { $0.lowercased().hasPrefix("http") }) ? .link
                : .text
            return SpaceColumn(name: name.isEmpty ? "Column \(i + 1)" : String(name.prefix(60)), kind: kind)
        }
        let rows = values.map { cells in
            Dictionary(uniqueKeysWithValues: zip(columns, cells).filter { !$0.1.isEmpty }.map { ($0.0.id, String($0.1.prefix(cellLimit))) })
        }
        return (columns, rows)
    }

    /// What a cell shows: a Category's option name, "Yes" for a ticked checkbox, else the text.
    public static func display(_ row: SpaceRow, _ column: SpaceColumn) -> String {
        let raw = row.cells[column.id] ?? ""
        switch column.kind {
        case .category: return column.options?.first { $0.id == raw }?.name ?? ""
        case .checkbox: return raw == "true" ? "Yes" : ""
        default: return raw
        }
    }

    /// The rows a view shows: its filters (all must match) and a search over every cell, in its sort order (else as
    /// they were added).
    public static func apply(_ view: SpaceTableView, columns: [SpaceColumn], rows: [SpaceRow], search: String = "") -> [SpaceRow] {
        let byID = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })
        let query = search.trimmingCharacters(in: .whitespaces)
        var shown = rows.filter { row in
            view.filters.allSatisfy { filter in
                guard let column = byID[filter.column] else { return true } // a filter on a deleted column hides nothing
                let raw = row.cells[column.id] ?? "", text = display(row, column)
                switch filter.op {
                case .contains: return filter.value.isEmpty || text.localizedCaseInsensitiveContains(filter.value)
                case .is_: return column.kind == .category ? raw == filter.value : text.caseInsensitiveCompare(filter.value) == .orderedSame
                case .isNot: return column.kind == .category ? raw != filter.value : text.caseInsensitiveCompare(filter.value) != .orderedSame
                case .isEmpty: return text.isEmpty
                case .isNotEmpty: return !text.isEmpty
                case .checked: return raw == "true"
                case .unchecked: return raw != "true"
                }
            } && (query.isEmpty || columns.contains { display(row, $0).localizedCaseInsensitiveContains(query) }
                  || (row.cells[noteKey] ?? "").localizedCaseInsensitiveContains(query))
        }
        if let id = view.sortColumn, let column = byID[id] {
            // Category sorts by its options' order; empty cells always last.
            let rank = { (row: SpaceRow) -> String in
                if column.kind == .category, let i = column.options?.firstIndex(where: { $0.id == row.cells[id] }) { return String(format: "%04d", i) }
                return display(row, column).lowercased()
            }
            shown.sort { a, b in
                let (x, y) = (rank(a), rank(b))
                if x.isEmpty != y.isEmpty { return !x.isEmpty }
                return view.sortAscending ? x < y : x > y
            }
        }
        return shown
    }

    /// A board's columns: one per option of the Category, in order, then the cards with none.
    public static func groups(_ rows: [SpaceRow], by column: SpaceColumn) -> [(option: SpaceOption?, rows: [SpaceRow])] {
        let options = column.options ?? []
        let known = Set(options.map(\.id))
        return options.map { option in (option, rows.filter { $0.cells[column.id] == option.id }) }
            + [(nil, rows.filter { !known.contains($0.cells[column.id] ?? "") })]
    }

    /// The table as CSV, header first, quoted where needed.
    public static func csv(columns: [SpaceColumn], rows: [SpaceRow]) -> String {
        func quote(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        return ([columns.map { quote($0.name) }.joined(separator: ",")]
                + rows.map { row in columns.map { quote(display(row, $0)) }.joined(separator: ",") }).joined(separator: "\n")
    }

    /// The column with the addresses: one typed Email, else the column where most filled cells are addresses (a list
    /// pasted into Text columns still works).
    public static func emailColumn(columns: [SpaceColumn], rows: [SpaceRow]) -> SpaceColumn? {
        if let typed = columns.first(where: { $0.kind == .email }) { return typed }
        return columns.first { column in
            let filled = rows.compactMap { $0.cells[column.id] }.filter { !$0.isEmpty }
            return !filled.isEmpty && filled.filter { ContactList.isAddress($0.trimmingCharacters(in: .whitespaces).lowercased()) }.count * 2 > filled.count
        }
    }

    /// A tags cell as tags: "#warm, studio" → ["warm", "studio"].
    public static func tags(in cell: String) -> [String] {
        cell.components(separatedBy: CharacterSet(charactersIn: ", ")).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased() }.filter { !$0.isEmpty }
    }

    /// Every tag used in the table's tag columns, sorted.
    public static func allTags(columns: [SpaceColumn], rows: [SpaceRow]) -> [String] {
        let tagColumns = columns.filter { $0.kind == .tags }.map(\.id)
        return Set(rows.flatMap { row in tagColumns.flatMap { tags(in: row.cells[$0] ?? "") } }).sorted()
    }

    /// The rows (with `tag`, or all when it's empty) as bulk mail contacts: the first email column is the address, a
    /// "name" (or first + last name) column the name, every other filled cell a field the mail may use.
    public static func contacts(columns: [SpaceColumn], rows: [SpaceRow], tag: String) -> (contacts: [(rowID: String, contact: ContactList.Contact)], problems: [String]) {
        guard let email = emailColumn(columns: columns, rows: rows) else {
            return ([], ["No column in this table holds email addresses. Add one, or set a column's type to Email."])
        }
        let wanted = tags(in: tag).first
        let tagColumns = columns.filter { $0.kind == .tags }.map(\.id)
        let lower = { (c: SpaceColumn) in c.name.lowercased() }
        var found: [(String, ContactList.Contact)] = [], problems: [String] = [], seen: Set<String> = []
        for (index, row) in rows.enumerated() {
            if let wanted, !tagColumns.contains(where: { tags(in: row.cells[$0] ?? "").contains(wanted) }) { continue }
            let address = (row.cells[email.id] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard ContactList.isAddress(address) else {
                problems.append("Row \(index + 1): “\(address.isEmpty ? "no email" : address)” isn't an email address."); continue
            }
            guard seen.insert(address).inserted else { problems.append("Row \(index + 1): \(address) is already in the list."); continue }
            let full = columns.first { ["name", "full name"].contains(lower($0)) }.flatMap { row.cells[$0.id] }
            let first = columns.first { ["first name", "firstname"].contains(lower($0)) }.flatMap { row.cells[$0.id] }
            let last = columns.first { ["last name", "lastname", "surname"].contains(lower($0)) }.flatMap { row.cells[$0.id] }
            let name = full ?? [first, last].compactMap { $0 }.joined(separator: " ")
            let used = Set([email.id] + columns.filter { ["name", "full name", "first name", "firstname", "last name", "lastname", "surname"].contains(lower($0)) }.map(\.id))
            var fields: [String: String] = [:]
            for column in columns where !used.contains(column.id) {
                let value = display(row, column)
                if !value.isEmpty { fields[lower(column)] = String(value.prefix(500)) }
            }
            found.append((row.id, ContactList.Contact(email: address, name: String(name.prefix(200)), fields: fields)))
        }
        return (found, problems)
    }
}
