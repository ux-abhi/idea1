// © Pexilim
import Foundation

/// The user's own Supabase server, typed in on first run and kept in the Keychain (ARCHITECTURE §36.9).
public struct ServerConfig: Codable, Equatable, Sendable {
    public let url: URL
    public let publishableKey: String

    public var host: String { url.host() ?? url.absoluteString }

    public enum Problem: Error, Equatable {
        case invalidURL, notHTTPS, emptyKey, secretKey
    }

    /// Trust boundary: everything the user pastes is checked here.
    public static func validate(url rawURL: String, key rawKey: String) throws(Problem) -> ServerConfig {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URLComponents(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              let host = parsed.host, !host.isEmpty, parsed.user == nil, parsed.password == nil
        else { throw .invalidURL }
        guard scheme == "https" else { throw .notHTTPS }

        var base = URLComponents()
        base.scheme = "https"
        base.host = host.lowercased()
        base.port = parsed.port
        guard let url = base.url else { throw .invalidURL }

        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .emptyKey }
        guard !isSecret(key) else { throw .secretKey }
        return ServerConfig(url: url, publishableKey: key)
    }

    /// The service-role key must never reach a device (§36.5). Catches new `sb_secret_` keys and legacy JWTs.
    static func isSecret(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return true }
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return claims["role"] as? String == "service_role"
    }
}
