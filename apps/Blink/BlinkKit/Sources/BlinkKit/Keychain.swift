// © Pexilim
import Foundation
import Security
import Supabase

/// Generic-password Keychain items for one service.
/// Tokens use `AfterFirstUnlockThisDeviceOnly` (ARCHITECTURE §36.5); the Mac uses the data-protection keychain.
/// shortcut: no shared access group yet; add one when widgets and intents need the session (Phase 1+).
public struct Keychain: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    public func set(_ data: Data, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(account).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func data(for account: String) throws -> Data? {
        var item: CFTypeRef?
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return item as? Data
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// Lets supabase-swift keep its session in our Keychain with our accessibility class.
struct KeychainAuthStorage: AuthLocalStorage {
    let keychain: Keychain
    func store(key: String, value: Data) throws { try keychain.set(value, for: key) }
    func retrieve(key: String) throws -> Data? { try keychain.data(for: key) }
    func remove(key: String) throws { try keychain.remove(key) }
}
