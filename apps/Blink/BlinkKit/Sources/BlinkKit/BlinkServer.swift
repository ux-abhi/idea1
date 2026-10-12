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

    // MARK: Notes and tasks

    public func items() async throws -> [BlinkItem] {
        try await client.from("item")
            .select("id, type, title, body, status, due_at, updated_at, segment_id")
            .in("type", values: ["note", "task"])
            .is("deleted_at", value: nil)
            .neq("status", value: "archived")
            .order("updated_at", ascending: false)
            .execute().value
    }

    /// Inserts with the client's id, so the item can show at once and be saved later.
    public func save(new item: BlinkItem) async throws {
        try await client.from("item").insert(ItemRow(item)).execute()
    }

    public func save(_ item: BlinkItem) async throws {
        try await client.from("item").update(ItemRow(item)).eq("id", value: item.id).execute()
    }

    /// Soft delete, so a sync can tell other devices it's gone.
    public func delete(_ item: BlinkItem) async throws {
        try await client.from("item").update(["deleted_at": Date.now]).eq("id", value: item.id).execute()
    }

    private struct ItemRow: Encodable {
        let id: String, type: String, title: String, body: String, status: String
        let due_at: Date?
        let segment_id: String?
        init(_ item: BlinkItem) {
            segment_id = item.spaceID
            id = item.id
            type = item.type.rawValue
            title = item.title
            body = item.body
            status = item.status.rawValue
            due_at = item.dueAt
        }

        // Send due_at as null when cleared, rather than leaving the old date.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(type, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(body, forKey: .body)
            try c.encode(status, forKey: .status)
            try c.encode(due_at, forKey: .due_at)
            try c.encode(segment_id, forKey: .segment_id)
        }
        enum CodingKeys: String, CodingKey { case id, type, title, body, status, due_at, segment_id }
    }

    // MARK: Spaces

    public func spaces() async throws -> [Space] {
        try await client.from("segment")
            .select("id, title, goal, status, due_at, color, icon")
            .neq("status", value: "archived")
            .order("created_at")
            .execute().value
    }

    public func save(new space: Space) async throws {
        try await client.from("segment").insert(space).execute()
    }

    public func save(_ space: Space) async throws {
        try await client.from("segment").update(space).eq("id", value: space.id).execute()
    }

    /// Deletes the space; its tasks and notes stay, outside any space (the database clears segment_id).
    public func delete(_ space: Space) async throws {
        try await client.from("segment").delete().eq("id", value: space.id).execute()
    }

    // MARK: Habits

    public func habits() async throws -> [Habit] {
        try await client.from("habit").select("id, name, weekdays, created_at")
            .is("archived_at", value: nil).order("created_at").execute().value
    }

    /// Answers from `sinceDay` ("yyyy-MM-dd") on.
    public func habitLogs(since sinceDay: String) async throws -> [HabitLog] {
        try await client.from("habit_log").select("habit_id, day, status")
            .gte("day", value: sinceDay).execute().value
    }

    public func save(new habit: Habit) async throws {
        try await client.from("habit").insert(HabitRow(id: habit.id, name: habit.name, weekdays: habit.weekdays)).execute()
    }

    public func save(_ habit: Habit) async throws {
        try await client.from("habit").update(HabitRow(id: habit.id, name: habit.name, weekdays: habit.weekdays))
            .eq("id", value: habit.id).execute()
    }

    public func archive(_ habit: Habit) async throws {
        try await client.from("habit").update(["archived_at": Date.now]).eq("id", value: habit.id).execute()
    }

    public func answer(_ habit: Habit, day: String, with answer: HabitAnswer) async throws {
        try await client.from("habit_log")
            .upsert(HabitLog(habitID: habit.id, day: day, status: answer), onConflict: "habit_id,day", returning: .minimal)
            .execute()
    }

    public func clearAnswer(_ habit: Habit, day: String) async throws {
        try await client.from("habit_log").delete().eq("habit_id", value: habit.id).eq("day", value: day).execute()
    }

    /// The owner's wake and evening times from the profile ("HH:mm:ss"): habit days end at wake; the check-in opens at evening.
    public func dayTimes() async throws -> (wake: (hour: Int, minute: Int), evening: (hour: Int, minute: Int)) {
        struct Row: Decodable { let wake_time: String; let evening_time: String }
        let row: Row = try await client.from("profile").select("wake_time, evening_time").single().execute().value
        func parse(_ s: String, _ fallback: (Int, Int)) -> (hour: Int, minute: Int) {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            return (parts.first ?? fallback.0, parts.dropFirst().first ?? fallback.1)
        }
        return (parse(row.wake_time, (7, 0)), parse(row.evening_time, (21, 30)))
    }

    private struct HabitRow: Encodable { let id: String, name: String, weekdays: [Int] }

    // MARK: Chat

    public struct ChatTurn: Codable, Equatable, Sendable, Identifiable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        public let id: UUID
        public let role: Role
        public let text: String
        public init(role: Role, text: String) {
            id = UUID()
            self.role = role
            self.text = text
        }
        enum CodingKeys: String, CodingKey { case role, text }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            role = try c.decode(Role.self, forKey: .role)
            text = try c.decode(String.self, forKey: .text)
        }
    }

    public struct ChatReply: Decodable, Sendable {
        public let reply: String
        public let proposed: Int
    }

    public struct ChatProblem: Error, Sendable { public let message: String }

    /// Asks Blink on the owner's server; Claude's proposals arrive as Ask-First cards.
    public func chat(_ message: String, history: [ChatTurn], timeZone: String,
                     reminders: [AgendaReminder] = []) async throws -> ChatReply {
        // ISO 8601 text: the function's default encoder would send dates as seconds since 2001, which the server refuses.
        struct Reminder: Encodable { let id: String; let title: String; let due: String? }
        struct Body: Encodable { let message: String; let history: [ChatTurn]; let timeZone: String; let reminders: [Reminder] }
        do {
            return try await client.functions.invoke(
                "chat", options: .init(body: Body(message: message, history: Array(history.suffix(20)), timeZone: timeZone,
                                                  reminders: reminders.map { Reminder(id: $0.id, title: $0.title, due: $0.due?.ISO8601Format()) })))
        } catch let FunctionsError.httpError(_, data) {
            // The function explains itself in words, e.g. a missing API key.
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't answer.")
        }
    }

    // MARK: Text helpers (Groq)

    public enum TextTask: String, CaseIterable, Sendable {
        case fix, shorter, clearer, summarize

        public var title: String {
            switch self {
            case .fix: "Fix Spelling & Grammar"
            case .shorter: "Make Shorter"
            case .clearer: "Make Clearer"
            case .summarize: "Summarise"
            }
        }
    }

    /// Returns the edited text; nothing is changed until the owner accepts the preview.
    public func edit(_ text: String, task: TextTask) async throws -> String {
        struct Body: Encodable { let task: String; let text: String }
        struct Reply: Decodable { let text: String }
        do {
            let reply: Reply = try await client.functions.invoke("text", options: .init(body: Body(task: task.rawValue, text: text)))
            return reply.text
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't edit that.")
        }
    }

    // MARK: Devices

    public struct DeviceInfo: Decodable, Identifiable, Sendable {
        public let id: String
        public let platform: String
        public let name: String
        public let lastSeenAt: Date?
        public let revokedAt: Date?
        public let hasApprovalKey: Bool

        enum CodingKeys: String, CodingKey {
            case id, platform, name
            case lastSeenAt = "last_seen_at", revokedAt = "revoked_at", approvalKey = "approval_key"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            platform = try c.decode(String.self, forKey: .platform)
            name = try c.decode(String.self, forKey: .name)
            lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
            revokedAt = try c.decodeIfPresent(Date.self, forKey: .revokedAt)
            hasApprovalKey = try c.decodeIfPresent(String.self, forKey: .approvalKey) != nil
        }
    }

    public func devices() async throws -> [DeviceInfo] {
        try await client.from("device")
            .select("id, platform, name, last_seen_at, revoked_at, approval_key")
            .order("created_at")
            .execute().value
    }

    /// Revokes a lost device: it can no longer approve red actions.
    public func revoke(deviceID id: String) async throws {
        try await client.from("device").update(["revoked_at": Date.now]).eq("id", value: id).execute()
    }

    /// This device's row id, lowercased to match the server's.
    public var currentDeviceID: String? { (try? deviceID())?.lowercased() }

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
