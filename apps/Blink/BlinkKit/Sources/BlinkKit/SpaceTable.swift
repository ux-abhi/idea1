// © Pexilim
import Foundation

/// A table block's column: a name and what kind of text it holds.
public struct SpaceColumn: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, email, link, tags
        public var title: String {
            switch self {
            case .text: "Text"
            case .email: "Email"
            case .link: "Link"
            case .tags: "Tags"
            }
        }
    }
    public let id: String
    public var name: String
    public var kind: Kind

    public init(id: String = String(UUID().uuidString.lowercased().prefix(8)), name: String, kind: Kind = .text) {
        (self.id, self.name, self.kind) = (id, name, kind)
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
    public static let rowLimit = 2000, columnLimit = 30, cellLimit = 1000

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

    /// The table as CSV, header first, quoted where needed.
    public static func csv(columns: [SpaceColumn], rows: [SpaceRow]) -> String {
        func quote(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        return ([columns.map { quote($0.name) }.joined(separator: ",")]
                + rows.map { row in columns.map { quote(row.cells[$0.id] ?? "") }.joined(separator: ",") }).joined(separator: "\n")
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
            for column in columns where !used.contains(column.id) { if let value = row.cells[column.id], !value.isEmpty { fields[lower(column)] = String(value.prefix(500)) } }
            found.append((row.id, ContactList.Contact(email: address, name: String(name.prefix(200)), fields: fields)))
        }
        return (found, problems)
    }
}
