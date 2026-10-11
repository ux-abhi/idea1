// © Pexilim
import Foundation
import Supabase

/// The connection to the user's own server: sign-in, this device's row, the profile row.
public final class BlinkServer: Sendable {
    public let config: ServerConfig
    private let client: SupabaseClient
    private let keychain: Keychain
    private static let deviceIDKey = "device.id"
    private static let configKey = "server.config"

    public init(config: ServerConfig, keychain: Keychain) {
        self.config = config
        self.keychain = keychain
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: .init(auth: .init(storage: KeychainAuthStorage(keychain: keychain), emitLocalSessionAsInitialSession: true))
        )
    }

    /// The signed-in email from the saved session, without touching the network.
    public var savedEmail: String? { client.auth.currentSession?.user.email }

    // These are async so Keychain access runs off the main actor (ARCHITECTURE §36.1).

    /// The saved server and signed-in email, if setup has run.
    public static func restore(keychain: Keychain) async -> (server: BlinkServer, email: String?)? {
        guard let data = try? keychain.data(for: configKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data)
        else { return nil }
        let server = BlinkServer(config: config, keychain: keychain)
        return (server, server.savedEmail)
    }

    public static func save(_ config: ServerConfig, keychain: Keychain) async throws {
        try keychain.set(JSONEncoder().encode(config), for: configKey)
    }

    public static func forget(keychain: Keychain) async {
        try? keychain.remove(configKey)
    }

    public func signIn(email: String, password: String) async throws -> String {
        let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        return session.user.email ?? email
    }

    /// Registers this device once and creates the profile row if there is none. Returns the time of the round trip.
    @discardableResult
    public func checkIn(platform: String, deviceName: String, timeZone: String) async throws -> Date {
        _ = try await client.auth.session // refreshes, or throws if the login is gone
        let now = Date.now

        // An existing profile keeps its time zone; the user may have changed it.
        try await client.from("profile")
            .upsert(["timezone": timeZone], onConflict: "owner_id", returning: .minimal, ignoreDuplicates: true)
            .execute()

        if let saved = try keychain.data(for: Self.deviceIDKey), let id = String(data: saved, encoding: .utf8) {
            let touched: [DeviceRow] = try await client.from("device")
                .update(["last_seen_at": now])
                .eq("id", value: id)
                .is("revoked_at", value: nil)
                .select("id")
                .execute().value
            if !touched.isEmpty { return now }
        }
        let row: DeviceRow = try await client.from("device")
            .insert(NewDevice(platform: platform, name: deviceName, last_seen_at: now))
            .select("id")
            .single()
            .execute().value
        try keychain.set(Data(row.id.uuidString.utf8), for: Self.deviceIDKey)
        return now
    }

    /// Marks this device revoked, then ends the session. Local state is cleared even when offline.
    /// shortcut: an offline sign-out leaves the server row un-revoked; retry it when Phase 1 puts approval keys on device rows.
    public func signOut() async {
        if let saved = try? keychain.data(for: Self.deviceIDKey), let id = String(data: saved, encoding: .utf8) {
            _ = try? await client.from("device").update(["revoked_at": Date.now]).eq("id", value: id).execute()
        }
        try? await client.auth.signOut(scope: .local)
        try? keychain.remove(Self.deviceIDKey)
    }

    private struct DeviceRow: Decodable { let id: UUID }
    private struct NewDevice: Encodable {
        let platform: String
        let name: String
        let last_seen_at: Date
    }
}

/// What went wrong, in terms the UI can put into words.
public enum ServerProblem: Equatable, Sendable {
    case unreachable, signedOut, wrongLogin, other(String)

    public init(_ error: any Error) {
        if error is URLError {
            self = .unreachable
        } else if let auth = error as? AuthError {
            switch auth.errorCode {
            case .invalidCredentials: self = .wrongLogin
            case .sessionNotFound, .refreshTokenNotFound, .refreshTokenAlreadyUsed, .userNotFound: self = .signedOut
            default: self = auth == .sessionMissing || auth == .refreshDiscarded ? .signedOut : .other(auth.localizedDescription)
            }
        } else {
            self = .other(error.localizedDescription)
        }
    }
}
