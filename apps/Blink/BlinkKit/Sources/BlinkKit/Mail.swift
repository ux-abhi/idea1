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

    enum CodingKeys: String, CodingKey {
        case id, account, subject, triage, reason, summary, status
        case messageID = "message_id", fromName = "from_name", fromAddr = "from_addr", receivedAt = "received_at"
        case needsReply = "needs_reply", createdAt = "created_at"
    }

    public var sender: String { fromName.isEmpty ? fromAddr : fromName }

    /// "Gmail", "iCloud", "Uni Siegen".
    public static func accountName(_ account: String) -> String {
        switch account {
        case "gmail": "Gmail"
        case "icloud": "iCloud"
        case "uni": "Uni Siegen"
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
