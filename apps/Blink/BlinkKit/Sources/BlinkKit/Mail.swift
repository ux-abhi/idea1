// © Pexilim
import Foundation

/// One triaged email from the mail worker (`email_msg`): who, what, why it matters. The body stays in the mailbox.
public struct EmailMessage: Codable, Identifiable, Equatable, Sendable {
    public enum Triage: String, Codable, Sendable { case important, normal, newsletter }
    public enum Status: String, Codable, Sendable { case new, seen, drafted, done }

    public let id: String
    public let account: String
    public let messageID: String
    public let fromName: String
    public let fromAddr: String
    public let subject: String
    public let receivedAt: Date?
    public var triage: Triage
    public let reason: String
    public let summary: String
    public let needsReply: Bool
    public var status: Status
    public let createdAt: Date
    /// Next steps the mail worker found (nil from an older server).
    public let actions: [MailAction]?

    enum CodingKeys: String, CodingKey {
        case id, account, subject, triage, reason, summary, status, actions
        case messageID = "message_id", fromName = "from_name", fromAddr = "from_addr", receivedAt = "received_at"
        case needsReply = "needs_reply", createdAt = "created_at"
    }

    public var sender: String { fromName.isEmpty ? fromAddr : fromName }
    public var nextSteps: [MailAction] { actions ?? [] }

    /// Where something made from this mail came from, so it can be found again ("From mail: Acme · Interview").
    public var sourceLine: String { "From mail: \(sender) · \(subject)" }

    /// "Gmail", "iCloud", "University".
    public static func accountName(_ account: String) -> String {
        switch account {
        case "gmail": "Gmail"
        case "icloud": "iCloud"
        case "uni": "University"
        default: account
        }
    }

    /// Opens this message in Apple Mail (message:// with the Message-ID).
    public var mailURL: URL? {
        let id = messageID.trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
        guard !id.isEmpty, let encoded = "<\(id)>".addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "message://\(encoded)")
    }
}

/// A next step found in a mail: an event, a deadline, a to-do or a detail to keep. Times are local wall-clock times
/// ("2026-10-21T15:00" or a day "2026-10-21"), read in this Mac's time zone.
public struct MailAction: Codable, Equatable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case event, deadline, task, note }
    public let kind: Kind
    public let title: String
    public let when: String
    public let end: String
    public let `where`: String

    public init(kind: Kind, title: String, when: String = "", end: String = "", where place: String = "") {
        (self.kind, self.title, self.when, self.end, self.where) = (kind, title, when, end, place)
    }

    /// True for a whole day ("2026-10-21"), false when a time is given.
    public var allDay: Bool { !when.contains("T") }
    public var start: Date? { Self.date(when) }
    public var finish: Date? { Self.date(end) }

    /// "2026-10-21T15:00" or "2026-10-21" as that wall-clock time in `calendar`'s zone; nil for anything else.
    static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(whereSeparator: { "-T:".contains($0) }).map { Int($0) }
        guard parts.count == 3 || parts.count == 5, text.count == (parts.count == 3 ? 10 : 16), !parts.contains(nil) else { return nil }
        let n = parts.map { $0! }
        let wanted = DateComponents(year: n[0], month: n[1], day: n[2], hour: parts.count == 5 ? n[3] : 0, minute: parts.count == 5 ? n[4] : 0)
        guard let date = calendar.date(from: wanted) else { return nil }
        // Reject rollovers like the 31st of a 30-day month.
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return back.year == wanted.year && back.month == wanted.month && back.day == wanted.day && back.hour == wanted.hour ? date : nil
    }
}

/// Where the mail worker is with one account (`mail_state`), for "checked 2 min ago" and problems.
public struct MailState: Codable, Equatable, Sendable {
    public let account: String
    public let lastCheckedAt: Date?
    public let lastError: String?
    enum CodingKeys: String, CodingKey { case account, lastCheckedAt = "last_checked_at", lastError = "last_error" }
}

/// A reply ready to review: what the mail worker wrote into Drafts, and exactly what will be sent once approved.
public struct MailDraft: Codable, Equatable, Sendable {
    public let emailID: String
    public let account: String
    public let from: String
    public var to: String
    public var subject: String
    public var body: String
    public let inReplyTo: String
    public let messageID: String

    enum CodingKeys: String, CodingKey {
        case account, from, to, subject, body
        case emailID = "email_id", inReplyTo = "in_reply_to", messageID = "message_id"
    }

    public init(emailID: String, account: String, from: String, to: String, subject: String, body: String, inReplyTo: String, messageID: String) {
        (self.emailID, self.account, self.from, self.to, self.subject, self.body, self.inReplyTo, self.messageID) =
            (emailID, account, from, to, subject, body, inReplyTo, messageID)
    }

    /// One plain address, the same rule the server checks before sending.
    public var hasValidRecipient: Bool {
        to.wholeMatch(of: /[^\s@<>,;"()]+@[^\s@<>,;"()]+\.[^\s@<>,;"()]+/) != nil
    }
}

/// The owner's verdict on a sender, taught from the Inbox: the worker applies it to all later mail from them.
public enum SenderVerdict: String, Sendable { case important, newsletter }

extension EmailMessage {
    /// The rule key for this sender: the address itself, lowercased.
    public var senderKey: String { fromAddr.lowercased() }
}
