// © Pexilim
import Foundation

/// A bulk mail (ADR-0003): the owner's description of the batch, and the account it goes out from.
public struct MailCampaign: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case draft, review, sending, paused, done }
    public let id: String
    public var title: String
    public var context: String
    public var goal: String
    public var tone: String
    public var account: String
    public var status: Status
    /// Read each company's own website for the mails (ADR-0003 §2, path A).
    public var research: Bool
    /// Files that go with every mail.
    public var attachments: [MailAttachment] = []
    /// Made from a Space: the Space, the table its contacts come from, and the tag that picks the rows ("" for all).
    public var spaceID: String?
    public var tableBlock: String?
    public var tag: String = ""

    enum CodingKeys: String, CodingKey {
        case id, title, context, goal, tone, account, status, research, attachments, tag
        case spaceID = "segment_id", tableBlock = "table_block"
    }

    public init(id: String = UUID().uuidString.lowercased(), title: String, context: String = "", goal: String = "", tone: String = "",
                account: String, status: Status = .draft, research: Bool = true) {
        (self.id, self.title, self.context, self.goal, self.tone, self.account, self.status) = (id, title, context, goal, tone, account, status)
        self.research = research
    }
}

/// A file that goes with every mail of a bulk mail, stored in the owner's private folder on their server.
public struct MailAttachment: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let type: String
    public let size: Int

    public init(path: String, name: String, type: String, size: Int) { (self.path, self.name, self.type, self.size) = (path, name, type, size) }

    /// What the server accepts: PDFs, pictures, PowerPoint and Word, 10 MB each, 15 MB and 5 files together.
    public static let types: [String: String] = ["pdf": "application/pdf", "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
        "gif": "image/gif", "webp": "image/webp",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
    public static let fileLimit = 10_000_000, totalLimit = 15_000_000, countLimit = 5

    /// Why these new files can't be added next to `existing`, or nil when they can.
    public static func problem(adding files: [(name: String, size: Int)], to existing: [MailAttachment]) -> String? {
        if existing.count + files.count > countLimit { return "Up to \(countLimit) files. For more, share a folder link." }
        if let bad = files.first(where: { types[($0.name as NSString).pathExtension.lowercased()] == nil }) {
            return "“\(bad.name)” can't be attached. Use a PDF, a picture, or a PowerPoint or Word file."
        }
        if let big = files.first(where: { $0.size > fileLimit }) { return "“\(big.name)” is over 10 MB. Share a link to it instead." }
        if existing.reduce(0, { $0 + $1.size }) + files.reduce(0, { $0 + $1.size }) > totalLimit {
            return "Together the files would be over 15 MB, too big for many mailboxes. Share a link instead."
        }
        return nil
    }
}

/// One person in a bulk mail: their row, the mail the AI wrote for them, and where it is.
public struct MailRecipient: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case new, written, approved, skipped, inDrafts = "in_drafts", sent, failed, bounced, replied }
    public let id: String
    public let campaignID: String
    public let email: String
    public var name: String
    public var fields: [String: String]
    public var subject: String
    public var body: String
    /// Set by Blink: "role" (info@…), "mailed_recently", "no_mail_server", "known" (you've mailed before).
    public var flags: [String]
    public var status: Status
    public var error: String?
    /// What Blink read on their company's website; empty until the mail is written.
    public var card: ResearchCard
    /// The Space table row this contact came from, so the mail's status shows there.
    public var rowID: String?

    enum CodingKeys: String, CodingKey { case id, email, name, fields, subject, body, flags, status, error, card; case campaignID = "campaign_id", rowID = "row_id" }

    public init(id: String = UUID().uuidString.lowercased(), campaignID: String, email: String, name: String = "", fields: [String: String] = [:],
                subject: String = "", body: String = "", flags: [String] = [], status: Status = .new, error: String? = nil, rowID: String? = nil) {
        self.rowID = rowID
        (self.id, self.campaignID, self.email, self.name, self.fields) = (id, campaignID, email, name, fields)
        (self.subject, self.body, self.flags, self.status, self.error) = (subject, body, flags, status, error)
        card = ResearchCard()
    }
}

/// A company's website in a few lines, for a personal first line (filled by the server; `{}` when nothing was read).
public struct ResearchCard: Codable, Equatable, Sendable {
    public var summary: String?
    public var facts: [String]?
    public var source: String?
    public init() {}
    public var isEmpty: Bool { (summary ?? "").isEmpty && (facts ?? []).isEmpty }
}

/// A pasted list or a CSV file read into contacts. Every problem row is reported, none is dropped silently.
public enum ContactList {
    public struct Contact: Equatable, Sendable {
        public let email: String
        public let name: String
        public let fields: [String: String]
    }

    /// Most contacts one bulk mail takes: Blink is for the owner's own outreach, not a newsletter (ADR-0003 §3).
    public static let limit = 500

    private static let roles: Set<String> = ["info", "contact", "hello", "office", "admin", "support", "sales", "team", "mail",
                                             "noreply", "no-reply", "donotreply", "billing", "jobs", "careers", "press", "marketing"]

    public static func isAddress(_ text: String) -> Bool {
        text.count <= 320 && text.range(of: #"^[^@\s,;<>"]+@[^@\s,;<>"]+\.[^@\s,;<>".]{2,}$"#, options: .regularExpression) != nil
    }

    /// A shared inbox (info@, sales@…): mail there reaches nobody in particular and is more often marked as spam.
    public static func isRole(_ email: String) -> Bool { roles.contains(email.split(separator: "@").first.map { $0.lowercased() } ?? "") }

    /// Reads a CSV with a header row (an "email" column; "name", or "first name" + "last name"; every other column kept as
    /// a field), or plain lines like "Ana Silva <ana@studio.com>", "ana@studio.com" or "Ana, ana@studio.com".
    /// `blocked` holds the do-not-mail list: whole addresses and "@domain"s.
    public static func parse(_ text: String, blocked: Set<String> = []) -> (contacts: [Contact], problems: [String]) {
        // shortcut: one row per line, so a quoted cell can't hold a line break; fine for contact lists, upgrade if a CSV with notes breaks.
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.firstIndex(where: { !$0.isEmpty }) else { return ([], []) }
        let separatorOf = { (line: String) -> Character in
            line.contains("\t") ? "\t" : line.filter { $0 == ";" }.count > line.filter { $0 == "," }.count ? ";" : ","
        }
        let separator = separatorOf(lines[first])
        let head = cells(lines[first], separator).map { $0.lowercased() }
        let emailColumn = head.firstIndex { ["email", "e-mail", "email address", "mail", "e-mail address"].contains($0) }
        let isHeader = emailColumn != nil && !lines[first].contains("@")

        var contacts: [Contact] = [], problems: [String] = [], seen: Set<String> = []
        for (index, line) in lines.enumerated() where !line.isEmpty && !(isHeader && index == first) {
            let row = cells(line, isHeader ? separator : separatorOf(line)) // pasted lines may mix "," and ";"
            var email = "", name = "", fields: [String: String] = [:]
            if isHeader, let emailColumn {
                for (i, cell) in row.enumerated() where i < head.count && !cell.isEmpty {
                    switch head[i] {
                    case _ where i == emailColumn: email = cell
                    case "name", "full name": name = cell
                    case "first name", "firstname": name = ([cell] + [name]).filter { !$0.isEmpty }.joined(separator: " ")
                    case "last name", "lastname", "surname": name = [name, cell].filter { !$0.isEmpty }.joined(separator: " ")
                    default: fields[head[i].isEmpty ? "column \(i + 1)" : head[i]] = String(cell.prefix(500))
                    }
                }
            } else if let angled = line.range(of: #"<[^<>]+>"#, options: .regularExpression) {
                email = String(line[angled].dropFirst().dropLast())
                name = line.replacingCharacters(in: angled, with: "").trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\",;")))
            } else {
                email = row.first { $0.contains("@") } ?? ""
                name = row.filter { $0 != email }.joined(separator: " ")
            }
            email = email.trimmingCharacters(in: .whitespaces).lowercased()
            let shown = email.isEmpty ? line.prefix(60) : Substring(email)
            if !isAddress(email) { problems.append("Line \(index + 1): “\(shown)” isn't an email address."); continue }
            if blocked.contains(email) || blocked.contains("@" + (email.split(separator: "@").last.map(String.init) ?? "")) {
                problems.append("Line \(index + 1): \(email) is on your do-not-mail list."); continue
            }
            if !seen.insert(email).inserted { problems.append("Line \(index + 1): \(email) is already in the list."); continue }
            if contacts.count == limit { problems.append("Only the first \(limit) contacts are kept. Bigger lists need a proper sending service."); break }
            contacts.append(Contact(email: email, name: String(name.prefix(200)), fields: fields))
        }
        return (contacts, problems)
    }

    /// One CSV line's cells, with "quoted, cells" and "" for a quote inside one.
    static func cells(_ line: String, _ separator: Character) -> [String] {
        var cells: [String] = [], current = "", quoted = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            if c == "\"" {
                if quoted, chars.first == "\"" { current.append("\""); chars.removeFirst() } else { quoted.toggle() }
            } else if c == separator, !quoted {
                cells.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(c)
            }
        }
        return cells + [current.trimmingCharacters(in: .whitespaces)]
    }
}

/// Checks a written mail for what gets mail sent to spam or an account limited (ADR-0003 §3). Warnings, never blocks:
/// the owner decides.
public enum MailLint {
    private static let shorteners = ["bit.ly", "tinyurl.com", "t.co/", "goo.gl", "ow.ly", "is.gd", "buff.ly", "rebrand.ly", "cutt.ly"]
    private static let spammy = ["act now", "click here", "limited time", "risk-free", "risk free", "guaranteed", "100% free",
                                 "winner", "urgent", "buy now", "no obligation", "earn money", "$$$"]

    /// Warnings for every mail of a batch at once, keyed by id; each mail's words are read once.
    public static func batch(_ mails: [(id: String, subject: String, body: String)]) -> [String: [String]] {
        let words = mails.map { Self.words($0.body) }
        var result: [String: [String]] = [:]
        for (i, mail) in mails.enumerated() {
            var found = warnings(subject: mail.subject, body: mail.body)
            if words[i].count >= 20, words.indices.contains(where: { $0 != i && similarity(words[i], words[$0]) > 0.85 }) {
                found.append(sameText)
            }
            result[mail.id] = found
        }
        return result
    }

    static let sameText = "Almost the same as another mail in this batch. Providers notice many identical mails."

    public static func warnings(subject: String, body: String, others: [String] = []) -> [String] {
        var found: [String] = []
        let text = (subject + "\n" + body).lowercased()
        let links = body.components(separatedBy: .whitespacesAndNewlines).filter { $0.lowercased().hasPrefix("http") || $0.lowercased().hasPrefix("www.") }
        if links.count > 2 { found.append("\(links.count) links. Mail with more than 2 links is more often sent to spam.") }
        if shorteners.contains(where: text.contains) { found.append("A shortened link. These look like spam; use the full address.") }
        let letters = subject.filter(\.isLetter)
        if letters.count >= 4, letters == letters.uppercased() { found.append("The subject is in capitals. That reads as shouting and as spam.") }
        if subject.contains("!") { found.append("An exclamation mark in the subject. Spam filters notice those.") }
        if let word = spammy.first(where: text.contains) { found.append("“\(word)” is a phrase spam filters look for.") }
        if text.contains("[add:") { found.append("Something for you to fill in: look for [add: …].") }
        if text.contains("{{") || text.contains("}}") { found.append("A placeholder wasn't filled in.") }
        let words = Self.words(body)
        if words.count >= 20, others.contains(where: { similarity(words, Self.words($0)) > 0.85 }) {
            found.append(sameText)
        }
        return found
    }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }

    /// Shared words over all words (Jaccard): 1 for the same text.
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let all = a.union(b).count
        return all == 0 ? 0 : Double(a.intersection(b).count) / Double(all)
    }
}
