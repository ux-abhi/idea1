// © Pexilim
import BlinkKit
import Foundation
import Testing

/// Runs inside the Blink app so the Keychain has the app's entitlements (package tests don't).
@Suite struct KeychainTests {
    @Test func roundTrip() throws {
        let keychain = Keychain(service: "blink.tests.\(UUID().uuidString)")
        defer { try? keychain.remove("token") }

        #expect(try keychain.data(for: "token") == nil)
        try keychain.set(Data("one".utf8), for: "token")
        #expect(try keychain.data(for: "token") == Data("one".utf8))
        try keychain.set(Data("two".utf8), for: "token")
        #expect(try keychain.data(for: "token") == Data("two".utf8))
        try keychain.remove("token")
        #expect(try keychain.data(for: "token") == nil)
    }
}
