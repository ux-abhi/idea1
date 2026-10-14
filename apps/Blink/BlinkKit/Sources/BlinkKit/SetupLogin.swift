// © Pexilim
import Foundation
import Security

/// The login Blink makes for the owner on a server it sets up, so nobody invents a password (kept in this Mac's Keychain,
/// shown in Settings › Server, filled in on the Sign in screen). The address receives no mail: it's only the login's name.
/// shortcut: lives on this Mac only; a lost Mac means resetting the user in the Supabase dashboard. Replace with QR
/// device pairing (§36.5) before more than one Mac per owner is common.
public enum SetupLogin {
    private static let account = "setup.login"

    public static func saved(in keychain: Keychain) -> (email: String, password: String)? {
        guard let data = try? keychain.data(for: account),
              let login = try? JSONDecoder().decode([String: String].self, from: data),
              let email = login["email"], let password = login["password"] else { return nil }
        return (email, password)
    }

    /// The saved login, or a new one saved first: a retried install must create and sign in with the same one.
    public static func make(in keychain: Keychain) throws -> (email: String, password: String) {
        if let login = saved(in: keychain) { return login }
        let alphabet = Array("abcdefghijkmnopqrstuvwxyz23456789")
        let tag = String((0..<8).map { _ in alphabet.randomElement()! })
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ServerSetup.Problem(message: "Couldn't make a secure password on this Mac. Try again.")
        }
        let login = (email: "owner-\(tag)@blinkk.app", password: Data(bytes).base64EncodedString())
        do {
            try keychain.set(JSONEncoder().encode(["email": login.email, "password": login.password]), for: account)
        } catch {
            throw ServerSetup.Problem(message: "Couldn't save your login in the Keychain. Try again.")
        }
        return login
    }
}
