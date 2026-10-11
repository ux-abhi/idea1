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

    /// Uploads this device's calendar snapshot for `window` (§36.1): upsert what's there, then drop what's gone.
    public func uploadCalendar(_ events: [AgendaEvent], window: DateInterval) async throws {
        guard let saved = try keychain.data(for: Self.deviceIDKey), let device = String(data: saved, encoding: .utf8) else { return }
        // Whole seconds survive the round trip exactly, so the "older than this upload" delete can't hit this upload's rows.
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let rows = events.map {
            CalendarRow(source: $0.source, ext_id: $0.extID, occurrence_start: $0.start, ends_at: $0.end, title: $0.title,
                        location: $0.location, url: $0.url?.absoluteString, snapshot_device: device, snapshot_at: now)
        }
        if !rows.isEmpty {
            try await client.from("calendar_event")
                .upsert(rows, onConflict: "owner_id,source,ext_id,occurrence_start", returning: .minimal)
                .execute()
        }
        // Rows from this device in the window that this snapshot didn't touch were deleted or moved.
        try await client.from("calendar_event").delete()
            .eq("snapshot_device", value: device)
            .gte("occurrence_start", value: window.start)
            .lt("occurrence_start", value: window.end)
            .lt("snapshot_at", value: now)
            .execute()
    }

    // MARK: Ask-First

    /// Enrols this device's approval key if the server has none for it yet. The server allows only the first device (§36.5).
    public func enrollApprovalKeyIfNeeded() async throws {
        guard ApprovalKey.isAvailable, let device = try deviceID() else { return }
        let rows: [KeyRow] = try await client.from("device").select("approval_key").eq("id", value: device).execute().value
        guard rows.first?.approval_key == nil else { return }
        let key = try await ApprovalKey.publicKey(keychain: keychain)
        try await client.from("device")
            .update(["approval_key": "\\x" + key.map { String(format: "%02x", $0) }.joined()])
            .eq("id", value: device)
            .execute()
    }

    public func pendingActions() async throws -> [BlinkAction] {
        try await client.from("action")
            .select("id, kind, risk, payload, payload_hash")
            .eq("status", value: "pending")
            .or("expires_at.is.null,expires_at.gt.\(Date.now.ISO8601Format())") // expired cards can't be approved
            .order("created_at")
            .execute().value
    }

    /// The latest decided actions, newest first, for Activity.
    public func recentActivity(limit: Int = 50) async throws -> [BlinkAction] {
        try await client.from("action")
            .select("id, kind, risk, payload, payload_hash, status, decided_at")
            .neq("status", value: "pending")
            .order("decided_at", ascending: false, nullsFirst: false)
            .limit(limit)
            .execute().value
    }

    /// Green and amber actions are decided by the client directly; the database refuses this for red approvals.
    public func setStatus(_ status: String, for action: BlinkAction, result: [String: String]? = nil) async throws {
        var change: [String: AnyJSON] = ["status": .string(status), "decided_at": .string(Date.now.ISO8601Format())]
        if let device = try deviceID() { change["decided_by_device"] = .string(device) }
        if let result { change["result"] = .object(result.mapValues { .string($0) }) }
        try await client.from("action").update(change).eq("id", value: action.id).execute()
    }

    /// Red: sign (action, payload hash, expiry) with the Secure Enclave key after Touch ID, and let the server verify it.
    public func approveRed(_ action: BlinkAction) async throws {
        guard let device = try deviceID() else { throw ApprovalKey.Problem.unavailable }
        let expires = Int(Date.now.timeIntervalSince1970) + 120
        let message = BlinkAction.approvalMessage(actionID: action.id, payloadHash: action.payloadHash, expires: expires)
        let signature = try await ApprovalKey.sign(message, reason: action.title, keychain: keychain)
        try await client.functions.invoke("approve", options: .init(body: [
            "action_id": AnyJSON.string(action.id),
            "device_id": .string(device),
            "expires": .integer(expires),
            "signature": .string(signature.base64EncodedString()),
        ]))
    }

    private func deviceID() throws -> String? {
        try keychain.data(for: Self.deviceIDKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Ends the session on this device. The device row and its approval key stay, so signing back in reuses them
    /// (a new row would never be allowed a key). Revoking a lost device happens from another device with pairing (§36.5).
    public func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    private struct DeviceRow: Decodable { let id: UUID }
    private struct KeyRow: Decodable { let approval_key: String? }
    private struct CalendarRow: Encodable {
        let source, ext_id: String
        let occurrence_start, ends_at: Date
        let title: String
        let location, url: String?
        let snapshot_device: String
        let snapshot_at: Date
    }
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
