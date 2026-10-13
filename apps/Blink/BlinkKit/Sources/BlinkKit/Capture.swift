// © Pexilim
import CryptoKit
import Foundation

/// A private link key for Apple Pay capture: the owner's iPhone Shortcuts automation sends each tap to the server's
/// `capture` function with it. Shown once; the server keeps only its SHA-256 (`capture_token.token_hash`).
public struct CaptureToken: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let lastUsedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt = "created_at", lastUsedAt = "last_used_at"
    }

    /// A new token ("blk_" + 32 random bytes, URL-safe) and the hash the server stores, as Postgres bytea text.
    public static func make() -> (token: String, hash: String) {
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let token = "blk_" + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return (token, hash(of: token))
    }

    static func hash(of token: String) -> String {
        "\\x" + SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Where the Shortcuts automation posts each tap.
    public static func endpoint(for server: ServerConfig) -> URL {
        server.url.appending(path: "functions/v1/capture")
    }
}
