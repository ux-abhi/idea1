// © Pexilim
import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// An Ask-First action from the `action` table (ARCHITECTURE §6).
public struct BlinkAction: Decodable, Identifiable, Equatable, Sendable {
    public enum Risk: String, Decodable, Sendable { case green, amber, red }

    /// Kept as the server's string: the signed message must use it byte for byte.
    public let id: String
    public let kind: String
    public let risk: Risk
    public let payload: Payload
    /// bytea as PostgREST sends it: "\x<hex>".
    public let payloadHash: String
    /// Set for decided actions (Activity): approved, done, declined, failed, expired, undone.
    public var status: String?
    public var decidedAt: Date?

    /// What every proposer puts in the payload so the card can show it; kind-specific fields sit beside these.
    public struct Payload: Decodable, Equatable, Sendable {
        /// "Add reminder “Pay rent”?" Optional so one malformed row can't hide every card.
        public let title: String?
        /// One preview line, e.g. "Tomorrow at 09:00".
        public let summary: String?
        /// The primary button's verb, e.g. "Add reminder" (§36.2).
        public let verb: String?
        /// For `reminder.add`: the reminder's text and due date.
        public let reminder: String?
        public let due: Date?
        /// For `task.complete` / `task.delete` / `reminder.complete` / `reminder.delete`.
        public let targetID: String?
        /// For `mail.compose` (from chat) and `mail.send`: which email, when to send, what to say, and to whom.
        public let emailID: String?
        public let sendAt: Date?
        public let note: String?
        public let to: String?
        public let subject: String?
        /// For `task.add` and `post.draft` from chat: the Space it goes into.
        public let spaceID: String?
        /// For `post.draft`: the platforms to write for ("instagram", "linkedin", "x"); the idea is in `note`.
        public let platforms: [String]?

        enum CodingKeys: String, CodingKey {
            case title, summary, verb, reminder, due, note, to, subject, platforms
            case targetID = "target_id", emailID = "email_id", sendAt = "send_at", spaceID = "space_id"
        }
    }

    /// The card's question; falls back to the kind.
    public var title: String { payload.title ?? kind }

    /// How a decided action reads in Activity: what happened, not the question the card asked.
    /// "Add reminder “Call Sam”?" done → "Added reminder “Call Sam”"; dismissed → "Dismissed: add reminder “Call Sam”".
    public var historyTitle: String {
        let question = title.hasSuffix("?") ? String(title.dropLast()) : title
        let lowered = question.prefix(1).lowercased() + question.dropFirst()
        switch status {
        case "done", "approved":
            let past = ["Add ": "Added ", "Move ": "Moved ", "Delete ": "Deleted ", "Mark done: ": "Marked done: "]
            for (verb, done) in past where question.hasPrefix(verb) { return done + question.dropFirst(verb.count) }
            return question
        case "declined": return "Dismissed: " + lowered
        case "failed": return "Didn't work: " + lowered
        case "expired": return "Expired: " + lowered
        case "undone": return "Undone: " + lowered
        default: return question
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, risk, payload, status
        case payloadHash = "payload_hash"
        case decidedAt = "decided_at"
    }

    /// The exact bytes a device signs to approve a red action; mirrors `approvalMessage` in functions/approve.
    public static func approvalMessage(actionID: String, payloadHash: String, expires: Int) -> Data {
        let hex = (payloadHash.hasPrefix("\\x") ? String(payloadHash.dropFirst(2)) : payloadHash).lowercased()
        return Data("blink-approve:v1\n\(actionID)\n\(hex)\n\(expires)".utf8)
    }
}

/// This device's Secure Enclave P-256 approval key, bound to the current biometric set (§36.5).
/// Only its `dataRepresentation` (an opaque, device-bound blob) is stored; the private key never leaves the Enclave.
public enum ApprovalKey {
    private static let account = "approval.key"

    public enum Problem: Error, Equatable {
        case unavailable, cancelled, keyInvalid

        /// What the owner sees; empty for a cancel, which keeps the card quietly (§36.5).
        public var message: String {
            switch self {
            case .cancelled: ""
            case .unavailable: "Touch ID isn't available right now. Open the lid or use a keyboard with Touch ID, then try again."
            case .keyInvalid: "Touch ID changed on this device, so Blink's approval key stopped working. Sending mail and other Touch ID approvals need this device paired again, which comes with the iPhone app."
            }
        }

        /// A cancel stays quiet; a locked-out or missing Touch ID says so.
        static func from(_ error: Error) -> Problem {
            guard let la = error as? LAError else { return .unavailable }
            switch la.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
            default: return .unavailable
            }
        }
    }

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Creates the key once and returns its public key (65-byte uncompressed point) for enrolment.
    public static func publicKey(keychain: Keychain) async throws -> Data {
        guard isAvailable else { throw Problem.unavailable }
        if let stored = try keychain.data(for: account) {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored).publicKey.x963Representation
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try keychain.set(key.dataRepresentation, for: account)
        return key.publicKey.x963Representation
    }

    /// Signs after Touch ID / Face ID, showing `reason` in the system prompt. Runs off the main actor.
    /// Returns the raw r‖s signature, the form WebCrypto verifies.
    public static func sign(_ message: Data, reason: String, keychain: Keychain) async throws -> Data {
        guard let stored = try keychain.data(for: account) else { throw Problem.unavailable }
        let context = LAContext()
        context.localizedReason = reason
        // Touch ID first, so a cancel and a changed finger set are told apart: after a successful check the key
        // only fails to sign when it was invalidated (§36.5: bound to the current biometric set).
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            throw Problem.from(error)
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored, authenticationContext: context)
            return try key.signature(for: message).rawRepresentation
        } catch {
            throw Problem.keyInvalid
        }
    }
}
