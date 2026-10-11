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

        enum CodingKeys: String, CodingKey {
            case title, summary, verb, reminder, due
            case targetID = "target_id"
        }
    }

    /// The card's question; falls back to the kind.
    public var title: String { payload.title ?? kind }

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

    public enum Problem: Error { case unavailable, cancelled }

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
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored, authenticationContext: context)
        do {
            return try key.signature(for: message).rawRepresentation
        } catch {
            throw Problem.cancelled
        }
    }
}
