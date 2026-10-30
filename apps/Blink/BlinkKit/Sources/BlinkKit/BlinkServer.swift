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
        // The same invite in two calendars would make Postgres refuse the whole upsert; keep one per key.
        var seen = Set<String>()
        let unique = events.filter { seen.insert("\($0.source)|\($0.extID)|\($0.start.timeIntervalSince1970)").inserted }
        let rows = unique.map {
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
            .select("id, type, title, body, status, due_at, updated_at, segment_id, stage, start_at")
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
        // An update that matches no row (deleted elsewhere) must not look like a save.
        let saved: [IDRow] = try await client.from("item").update(ItemRow(item)).eq("id", value: item.id).select("id").execute().value
        if saved.isEmpty { throw RowGone() }
    }

    /// Soft delete, so a sync can tell other devices it's gone.
    public func delete(_ item: BlinkItem) async throws {
        try await client.from("item").update(["deleted_at": Date.now]).eq("id", value: item.id).execute()
    }

    /// Undoes `delete` (it only marks the item deleted).
    public func restore(_ item: BlinkItem) async throws {
        struct Undelete: Encodable { let deleted_at: Date? = nil }
        try await client.from("item").update(Undelete()).eq("id", value: item.id).execute()
    }

    private struct ItemRow: Encodable {
        let id: String, type: String, title: String, body: String, status: String
        let due_at: Date?
        let segment_id: String?
        let stage: String?
        let start_at: Date?
        init(_ item: BlinkItem) {
            segment_id = item.spaceID
            stage = item.stage
            start_at = item.startAt
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
            try c.encode(stage, forKey: .stage)
            try c.encode(start_at, forKey: .start_at)
        }
        enum CodingKeys: String, CodingKey { case id, type, title, body, status, due_at, segment_id, stage, start_at }
    }

    // MARK: Spaces

    public func spaces() async throws -> [Space] {
        try await client.from("segment")
            .select("id, title, goal, status, due_at, color, icon, cover, columns")
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
    /// Deletes a Space (its canvas goes with it) and its pictures' files.
    public func delete(_ space: Space) async throws {
        try await client.from("segment").delete().eq("id", value: space.id).execute()
        // The Space is gone by now; a failure from here on only leaves files behind, never says the delete failed.
        guard let user = try? await client.auth.session.user.id else { return }
        let folder = "\(user.uuidString.lowercased())/\(space.id)"
        // shortcut: lists the first 100 files only; page through if a Space ever holds more pictures.
        if let files = try? await client.storage.from("canvas").list(path: folder), !files.isEmpty {
            _ = try? await client.storage.from("canvas").remove(paths: files.map { "\(folder)/\($0.name)" })
        }
    }

    // MARK: Habits

    public func habits() async throws -> [Habit] {
        try await client.from("habit").select("id, name, weekdays, created_at")
            .is("archived_at", value: nil).order("created_at").execute().value
    }

    /// Answers from `sinceDay` ("yyyy-MM-dd") on.
    public func habitLogs(since sinceDay: String) async throws -> [HabitLog] {
        // The server returns at most 1,000 rows per request, and years of answers are more: read page by page.
        var logs: [HabitLog] = []
        while true {
            let page: [HabitLog] = try await client.from("habit_log").select("habit_id, day, status")
                .gte("day", value: sinceDay).order("day").order("habit_id")
                .range(from: logs.count, to: logs.count + 999).execute().value
            logs += page
            if page.count < 1000 { return logs }
        }
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

    public func setDayTimes(wake: (hour: Int, minute: Int), evening: (hour: Int, minute: Int)) async throws {
        let user = try await client.auth.session.user.id
        func text(_ t: (hour: Int, minute: Int)) -> String { String(format: "%02d:%02d:00", t.hour, t.minute) }
        try await client.from("profile")
            .update(["wake_time": text(wake), "evening_time": text(evening)])
            .eq("owner_id", value: user)
            .execute()
    }

    // MARK: Content (§36.4)

    /// One draft per platform from the idea, saved on the server; returns the questions the model wants answered for a
    /// stronger post (it asks rather than invents). Reload with `contentPieces()`.
    @discardableResult
    public func draftContent(idea: String, platforms: [ContentPiece.Platform], spaceID: String? = nil,
                             plannedFor: String? = nil) async throws -> [String] {
        struct Body: Encodable { let idea: String; let platforms: [String]; let space_id: String?; let planned_for: String? }
        struct Reply: Decodable { let saved: Int; let questions: [String]? }
        do {
            let reply: Reply = try await client.functions.invoke(
                "content", options: .init(body: Body(idea: idea, platforms: platforms.map(\.rawValue), space_id: spaceID,
                                                     planned_for: plannedFor)))
            return reply.questions ?? []
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't write drafts.")
        }
    }

    /// Six ideas for the owner's page (optionally around a theme), to pick from. Nothing is saved.
    /// `days` set: the week plan, each idea on one of those days.
    public func contentIdeas(theme: String, platforms: [ContentPiece.Platform], days: [String] = []) async throws -> [ContentIdea] {
        struct Body: Encodable { let mode: String; let idea: String; let platforms: [String]; let days: [String] }
        struct Reply: Decodable { let ideas: [ContentIdea] }
        do {
            let reply: Reply = try await client.functions.invoke(
                "content", options: .init(body: Body(mode: days.isEmpty ? "ideas" : "week", idea: theme,
                                                     platforms: platforms.map(\.rawValue), days: days)))
            return reply.ideas
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't come up with ideas.")
        }
    }

    /// Reads the owner's own public Instagram page (Apify) and sums it up; posts are kept on the server.
    public func readPage() async throws -> PageRead {
        do {
            // The server reads only the handle saved in Voice.
            return try await client.functions.invoke("page", options: .init(body: [String: String]()))
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't read your page.")
        }
    }

    /// A cover or a text-free carousel background from Cloudflare FLUX (the owner's free daily allowance), as JPEG data.
    public func makeImage(subject: String, background: Bool) async throws -> Data {
        struct Body: Encodable { let subject: String; let kind: String }
        struct Reply: Decodable { let image: String }
        do {
            let reply: Reply = try await client.functions.invoke(
                "image", options: .init(body: Body(subject: String(subject.prefix(500)), kind: background ? "background" : "cover")))
            guard let data = Data(base64Encoded: reply.image) else { throw ChatProblem(message: "The image didn't come through. Try again.") }
            return data
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't make an image.")
        }
    }

    /// Settings › Connections: "ok", "missing", "rejected" or "unreachable" per key on the server (never the keys).
    public func connections() async throws -> [String: String] {
        try await client.functions.invoke("connections", options: .init(body: [String: String]()))
    }

    /// The Supabase project's ref when the free plan has paused it (Supabase answers 540 until the owner restores it),
    /// nil when it isn't paused or can't be asked.
    public func pausedProject() async -> String? {
        var request = URLRequest(url: config.url.appending(path: "rest/v1/"), timeoutInterval: 10)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 540 else { return nil }
        return Self.projectRef(config.url)
    }

    /// "abc123" from https://abc123.supabase.co; nil for a server on another domain (or anything else under supabase.co).
    public static func projectRef(_ url: URL) -> String? {
        let parts = (url.host() ?? "").lowercased().split(separator: ".")
        guard parts.count == 3, parts[1] == "supabase", parts[2] == "co", parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return String(parts[0])
    }

    /// Keys and passwords saved from the app (names only; values are never readable back).
    public func savedKeys() async throws -> Set<String> {
        struct Row: Decodable { let name: String }
        let rows: [Row] = try await client.from("server_key").select("name").execute().value
        return Set(rows.map(\.name))
    }

    /// Saves one key or password to the server's Vault (only names the server knows are accepted).
    public func saveKey(_ name: String, value: String) async throws {
        try await client.rpc("set_server_key", params: ["key_name": name, "key_value": value]).execute()
    }

    /// Removes a key saved from the app; a dashboard secret with the same name, if any, applies again.
    public func removeKey(_ name: String) async throws {
        try await client.rpc("remove_server_key", params: ["key_name": name]).execute()
    }

    /// Revokes Blink's Google access at Google and deletes it from the server.
    public func disconnectGoogle() async throws {
        _ = try await client.functions.invoke("google/disconnect", options: .init(body: [String: String]()))
    }

    private struct IDRow: Decodable { let id: String }
    /// The row to update isn't on the server (removed outside the app): save it as new instead.
    public struct RowGone: Error {}

    // MARK: Mail (Phase 5)

    /// The last week's triaged mail that isn't done, newest first. Newsletters are fetched on their own, smaller list,
    /// so a busy day of them can't push unhandled important mail off the end.
    public func emails() async throws -> [EmailMessage] {
        func page(newsletters: Bool, limit: Int) async throws -> [EmailMessage] {
            let query = client.from("email_msg")
                .select("id, account, message_id, from_name, from_addr, subject, received_at, triage, reason, summary, needs_reply, status, created_at, actions")
                .neq("status", value: "done")
                .gte("created_at", value: Date.now.addingTimeInterval(-7 * 86_400).ISO8601Format())
            return try await (newsletters ? query.eq("triage", value: "newsletter") : query.neq("triage", value: "newsletter"))
                .order("received_at", ascending: false)
                .limit(limit)
                .execute().value
        }
        async let rest = page(newsletters: false, limit: 300)
        async let newsletters = page(newsletters: true, limit: 60)
        return try await (rest + newsletters).sorted { ($0.receivedAt ?? $0.createdAt) > ($1.receivedAt ?? $1.createdAt) }
    }

    public func mailStates() async throws -> [MailState] {
        try await client.from("mail_state").select("account, last_checked_at, last_error").execute().value
    }

    public func setStatus(_ status: EmailMessage.Status, of email: EmailMessage) async throws {
        try await setStatus(status, ids: [email.id])
    }

    /// One update for many mails (bulk Done, and its Undo).
    public func setStatus(_ status: EmailMessage.Status, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await client.from("email_msg").update(["status": status.rawValue]).in("id", values: ids).execute()
    }

    /// The full text of one mail for the reading pane, fetched from the mailbox now (the server never stores it).
    public func readMail(_ email: EmailMessage) async throws -> String {
        struct Body: Encodable { let action = "read"; let id: String }
        struct Reply: Decodable { let text: String }
        do {
            let reply: Reply = try await client.functions.invoke("mail", options: .init(body: Body(id: email.id)))
            return reply.text
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't open that email.")
        }
    }

    /// Checks the mailboxes now (the server also does every 5 minutes).
    public func syncMail() async throws {
        do {
            _ = try await client.functions.invoke("mail", options: .init(body: [String: String]()))
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't check mail.")
        }
    }

    /// A reply in the owner's voice, saved to that account's Drafts folder (it shows in Apple Mail), returned for review.
    /// With `reuse`, Blink's earlier draft is read back (including edits made in Apple Mail) instead of writing a new one.
    public func draftReply(to email: EmailMessage, note: String, reuse: Bool = false) async throws -> MailDraft {
        struct Body: Encodable { let action = "draft"; let id: String; let note: String; let reuse: Bool }
        struct Reply: Decodable { let draft: MailDraft }
        do {
            let reply: Reply = try await client.functions.invoke("mail", options: .init(body: Body(id: email.id, note: note, reuse: reuse)))
            return reply.draft
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't write the draft.")
        }
    }

    /// Proposes sending exactly this reply at `sendAt` as a red action; it goes out only after `approveRed` (Touch ID).
    public func proposeSend(_ draft: MailDraft, at sendAt: Date, title: String, summary: String) async throws -> BlinkAction {
        struct Payload: Encodable {
            let title: String, summary: String, verb = "Send"
            let email_id: String, account: String, from: String, to: String, subject: String, body: String
            let in_reply_to: String, message_id: String, send_at: String
        }
        struct Row: Encodable { let kind = "mail.send", risk = "red", payload: Payload, payload_hash = "\\x00", proposed_by = "blink" }
        let payload = Payload(title: title, summary: summary, email_id: draft.emailID, account: draft.account, from: draft.from,
                              to: draft.to.trimmingCharacters(in: .whitespaces), subject: draft.subject, body: draft.body,
                              in_reply_to: draft.inReplyTo, message_id: draft.messageID, send_at: sendAt.ISO8601Format())
        return try await client.from("action").insert(Row(payload: payload))
            .select("id, kind, risk, payload, payload_hash").single().execute().value
    }

    // MARK: Google Meet (/meet)

    /// The connected Google account's email, or nil when Google isn't connected.
    public func googleAccount() async throws -> String? {
        struct Row: Decodable { let email: String }
        let rows: [Row] = try await client.from("google_link").select("email").execute().value
        return rows.first?.email
    }

    /// Google's consent page for this owner (valid 10 minutes). Opened in the browser; the server keeps the token.
    public func googleConnectURL() async throws -> URL {
        struct Reply: Decodable { let url: URL }
        do {
            let reply: Reply = try await client.functions.invoke("google/start", options: .init(body: [String: String]()))
            return reply.url
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't start connecting Google.")
        }
    }

    /// One-click Google: the server exchanges Google's code (with the PKCE verifier) and keeps the token. Returns the account.
    public func googleExchange(code: String, verifier: String, redirect: String) async throws -> String {
        struct Reply: Decodable { let account: String }
        do {
            let reply: Reply = try await client.functions.invoke("google/exchange",
                options: .init(body: ["code": code, "verifier": verifier, "redirect": redirect]))
            return reply.account
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't connect Google.")
        }
    }

    public struct MeetResult: Decodable, Sendable {
        public let meetURL: URL?
        public let htmlLink: URL?
        enum CodingKeys: String, CodingKey { case meetURL = "meet_url", htmlLink = "html_link" }
    }

    /// Proposes exactly this meeting as a red action; it is created only after `approveRed` (Touch ID) and `createMeet`.
    public func proposeMeet(title: String, start: Date, minutes: Int, timeZone: String, guests: [String]) async throws -> BlinkAction {
        struct Payload: Encodable {
            let title: String, summary: String, verb = "Invite"
            let meet_title: String, start: String, minutes: Int, time_zone: String, guests: [String]
        }
        struct Row: Encodable { let kind = "meet.create", risk = "red", payload: Payload, payload_hash = "\\x00", proposed_by = "owner" }
        let when = start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
        let payload = Payload(title: "Invite \(guests.joined(separator: ", ")) to “\(title)”", summary: "Google Meet, \(when), \(minutes) min",
                              meet_title: title, start: start.ISO8601Format(), minutes: minutes, time_zone: timeZone, guests: guests)
        return try await client.from("action").insert(Row(payload: payload))
            .select("id, kind, risk, payload, payload_hash").single().execute().value
    }

    /// Why a meeting wasn't created. `spent`: the approval is used up, so a changed card needs a new one.
    public struct MeetProblem: Error, Sendable { public let message: String; public let spent: Bool }

    /// Creates the approved meeting in Google Calendar with a Meet link; Google emails the guests. Safe to retry.
    public func createMeet(_ action: BlinkAction) async throws -> MeetResult {
        do {
            return try await client.functions.invoke("google/meet", options: .init(body: ["action_id": action.id]))
        } catch let FunctionsError.httpError(code, data) {
            struct ErrorBody: Decodable { let error: String }
            throw MeetProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Google didn't create the meeting.",
                              spent: code != 412 && code < 500)
        }
    }

    /// Asks the mail worker to send approved mail that is due now (the 5-minute schedule does it too).
    public func sendDueMail() async throws {
        _ = try await client.functions.invoke("mail", options: .init(body: ["action": "send"]))
    }

    /// Approved mail waiting for its send time, soonest first.
    public func outbox() async throws -> [BlinkAction] {
        try await client.from("action")
            .select("id, kind, risk, payload, payload_hash, status, decided_at")
            .eq("kind", value: "mail.send").eq("status", value: "approved")
            .order("created_at")
            .execute().value
    }

    /// Stops a scheduled send if it hasn't gone yet. Returns false when it's too late (already sending or sent).
    public func cancelSend(_ action: BlinkAction) async throws -> Bool {
        let rows: [IDRow] = try await client.from("action")
            .update(["status": "declined", "decided_at": Date.now.ISO8601Format()])
            .eq("id", value: action.id).eq("status", value: "approved")
            .select("id").execute().value
        return !rows.isEmpty
    }

    /// A sender rule as it was before `teach` changed it, so Undo can put it back.
    /// A sender the owner taught Blink about: all their mail is important, or never is. `example` is a subject it was taught on.
    public struct SenderRule: Codable, Sendable, Identifiable, Equatable {
        public let sender: String
        public let verdict: String
        public let example: String?
        public var id: String { sender }
        public var important: Bool { verdict == SenderVerdict.important.rawValue }
    }

    /// Everything the owner has taught Blink about senders, A to Z.
    public func senderRules() async throws -> [SenderRule] {
        try await client.from("mail_sender_rule").select("sender, verdict, example").order("sender").execute().value
    }

    /// Forgets one sender rule: later mail from them is sorted on its own again (mail already sorted stays as it is).
    public func forget(rule: SenderRule) async throws {
        try await client.from("mail_sender_rule").delete().eq("sender", value: rule.sender).execute()
    }

    /// The owner says what this mail is; the sender rule makes all later mail from them follow suit. Returns the rule
    /// it replaced, if there was one.
    @discardableResult
    public func teach(_ verdict: SenderVerdict, for email: EmailMessage) async throws -> SenderRule? {
        struct Rule: Encodable { let sender: String, verdict: String, example: String }
        let earlier: [SenderRule] = try await client.from("mail_sender_rule").select("sender, verdict, example")
            .eq("sender", value: email.senderKey).execute().value
        try await client.from("email_msg").update(["triage": verdict.rawValue])
            .eq("from_addr", value: email.senderKey).neq("status", value: "done").execute()
        try await client.from("mail_sender_rule")
            .upsert(Rule(sender: email.senderKey, verdict: verdict.rawValue, example: String(email.subject.prefix(300))), onConflict: "owner_id,sender")
            .execute()
        return earlier.first
    }

    /// Undoes `teach`: puts back the sender's earlier rule (or drops the new one) and each mail as it was sorted before.
    public func forget(senderKey: String, restoring emails: [EmailMessage], rule: SenderRule? = nil) async throws {
        if let rule {
            try await client.from("mail_sender_rule").upsert(rule, onConflict: "owner_id,sender").execute()
        } else {
            try await client.from("mail_sender_rule").delete().eq("sender", value: senderKey).execute()
        }
        for email in emails {
            try await client.from("email_msg").update(["triage": email.triage.rawValue]).eq("id", value: email.id).execute()
        }
    }

    // MARK: Server package

    /// The Blink server package this server runs (`server_info`, written by Blink's installer); nil when none is recorded,
    /// including on a server from before that table existed.
    public func serverPackage() async throws -> String? {
        struct Row: Decodable { let value: String }
        do {
            let rows: [Row] = try await client.from("server_info").select("value").eq("key", value: "package").execute().value
            return rows.first?.value
        } catch let error as PostgrestError where ["PGRST205", "42P01"].contains(error.code) {
            return nil
        }
    }

    // MARK: Space canvas

    public func canvas(of spaceID: String) async throws -> (nodes: [SpaceNode], edges: [SpaceEdge]) {
        async let nodes: [SpaceNode] = client.from("space_node").select("id, segment_id, kind, ref, x, y, color, w, h, text_scale")
            .eq("segment_id", value: spaceID).execute().value
        async let edges: [SpaceEdge] = client.from("space_edge").select("id, segment_id, from_node, to_node")
            .eq("segment_id", value: spaceID).execute().value
        return try await (nodes, edges)
    }

    public func save(_ node: SpaceNode) async throws {
        try await client.from("space_node").upsert(node).execute()
    }

    /// The row already exists (a unique constraint said no), e.g. another Mac made the same canvas card first.
    public static func isDuplicate(_ error: Error) -> Bool { (error as? PostgrestError)?.code == "23505" }

    /// Removes a node; the links to it go with it on the server.
    public func delete(_ node: SpaceNode) async throws {
        try await client.from("space_node").delete().eq("id", value: node.id).execute()
    }

    public func removeCanvasImage(_ path: String) async throws {
        try await client.storage.from("canvas").remove(paths: [path])
    }

    /// Stores a canvas picture (already made ready by `CanvasImage.jpeg`) in the owner's own folder; returns its path.
    public func uploadCanvasImage(_ jpeg: Data, space spaceID: String) async throws -> String {
        let user = try await client.auth.session.user.id
        let path = "\(user.uuidString.lowercased())/\(spaceID)/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("canvas").upload(path, data: jpeg, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
        return path
    }

    public func canvasImage(_ path: String) async throws -> Data {
        try await client.storage.from("canvas").download(path: path)
    }

    public func save(_ edge: SpaceEdge) async throws {
        try await client.from("space_edge").upsert(edge, onConflict: "from_node,to_node").execute()
    }

    public func delete(_ edge: SpaceEdge) async throws {
        try await client.from("space_edge").delete().eq("id", value: edge.id).execute()
    }

    // MARK: Blink connector (Claude, ChatGPT)

    /// A connector link in use: when it was made and last used by Claude or ChatGPT.
    public struct ConnectorLink: Decodable, Identifiable, Sendable {
        public let id: String
        public let createdAt: Date
        public let lastUsedAt: Date?
        enum CodingKeys: String, CodingKey { case id, createdAt = "created_at", lastUsedAt = "last_used_at" }
    }

    /// A new link to paste into Claude or ChatGPT as a custom connector. Shown once: the server keeps only its hash.
    public func createConnectorLink() async throws -> URL {
        let code: String = try await client.rpc("create_mcp_token").execute().value
        return config.url.appending(path: "functions/v1/mcp/\(code)")
    }

    public func connectorLinks() async throws -> [ConnectorLink] {
        try await client.from("mcp_token").select("id, created_at, last_used_at").order("created_at", ascending: false).execute().value
    }

    /// Turns every connector link off; Claude and ChatGPT lose access at once.
    public func revokeConnectorLinks() async throws {
        try await client.from("mcp_token").delete().neq("id", value: "00000000-0000-0000-0000-000000000000").execute()
    }

    // MARK: Money (Phase 7, first slice)

    /// Spends from `since` ("2026-09-01") on, newest first.
    public func spends(since: String) async throws -> [Spend] {
        try await client.from("transaction").select("id, amount, note, category, spent_on, account_id, created_at")
            .gte("spent_on", value: since)
            .order("spent_on", ascending: false).order("created_at", ascending: false)
            .limit(1000)
            .execute().value
    }

    public func budgets() async throws -> [Budget] {
        try await client.from("budget").select("category, monthly_limit").execute().value
    }

    /// The AI reads what the owner typed into spends with categories; nothing is saved yet.
    public func sortSpends(_ text: String, today: String) async throws -> [SpendDraft] {
        struct Reply: Decodable { let entries: [SpendDraft] }
        do {
            let reply: Reply = try await client.functions.invoke("money", options: .init(body: ["text": text, "today": today]))
            return reply.entries
        } catch let FunctionsError.httpError(_, data) {
            struct ErrorBody: Decodable { let error: String }
            throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Couldn't sort that.")
        }
    }

    public func add(_ drafts: [SpendDraft]) async throws -> [Spend] {
        try await client.from("transaction").insert(drafts)
            .select("id, amount, note, category, spent_on, account_id, created_at").execute().value
    }

    public func save(_ spend: Spend) async throws {
        struct Row: Encodable { let amount: Decimal, note: String, category: SpendCategory, spent_on: String, account_id: String? }
        try await client.from("transaction")
            .update(Row(amount: spend.amount, note: spend.note, category: spend.category, spent_on: spend.spentOn, account_id: spend.accountID))
            .eq("id", value: spend.id).execute()
    }

    public func delete(_ spend: Spend) async throws {
        try await client.from("transaction").delete().eq("id", value: spend.id).execute()
    }

    // MARK: Apple Pay capture

    public func captureTokens() async throws -> [CaptureToken] {
        try await client.from("capture_token").select("id, name, created_at, last_used_at").order("created_at").execute().value
    }

    /// Stores only the token's hash; returns the token, to show the owner once.
    public func makeCaptureToken(name: String) async throws -> String {
        struct Row: Encodable { let name: String, token_hash: String }
        let made = CaptureToken.make()
        try await client.from("capture_token").insert(Row(name: name, token_hash: made.hash)).execute()
        return made.token
    }

    public func deleteCaptureToken(_ token: CaptureToken) async throws {
        try await client.from("capture_token").delete().eq("id", value: token.id).execute()
    }

    public func accounts() async throws -> [MoneyAccount] {
        try await client.from("money_account_now").select("id, name, kind, balance, balance_at, is_default, spent_since").order("created_at").execute().value
    }

    /// A new account with today's balance; the first one becomes the default.
    public func addAccount(name: String, kind: MoneyAccount.Kind, balance: Decimal, isDefault: Bool) async throws -> MoneyAccount {
        struct Row: Encodable { let name: String, kind: MoneyAccount.Kind, balance: Decimal, is_default: Bool }
        return try await client.from("money_account").insert(Row(name: name, kind: kind, balance: balance, is_default: isDefault))
            .select("id, name, kind, balance, balance_at, is_default").single().execute().value
    }

    /// The owner checked their bank: this is the balance now (spends from here on come off it).
    public func setBalance(_ balance: Decimal, of account: MoneyAccount) async throws -> MoneyAccount {
        // balance_at is set by the server (its clock, like the spends'), whenever the balance is written.
        struct Row: Encodable { let balance: Decimal }
        return try await client.from("money_account").update(Row(balance: balance))
            .eq("id", value: account.id).select("id, name, kind, balance, balance_at, is_default").single().execute().value
    }

    /// Spends with no account named come off this one (only one default at a time).
    public func makeDefault(_ account: MoneyAccount) async throws {
        // One transaction on the server, so a dropped connection can't leave no default.
        try await client.rpc("set_default_account", params: ["account": account.id]).execute()
    }

    /// Removes an account; its spends stay, without an account.
    public func deleteAccount(_ account: MoneyAccount) async throws {
        try await client.from("money_account").delete().eq("id", value: account.id).execute()
    }

    /// Sets a category's monthly limit, or removes it with nil.
    public func setLimit(_ limit: Decimal?, for category: SpendCategory) async throws {
        if let limit {
            try await client.from("budget").upsert(Budget(category: category, monthlyLimit: limit), onConflict: "owner_id,category").execute()
        } else {
            try await client.from("budget").delete().eq("category", value: category.rawValue).execute()
        }
    }

    /// The owner's Instagram posts the page reader saw, newest first (for the Content overview).
    public func pagePosts() async throws -> [PagePost] {
        try await client.from("social_post").select("url, kind, caption, likes, comments, views, posted_at")
            .order("posted_at", ascending: false, nullsFirst: false).limit(200).execute().value
    }

    public func socialAccounts() async throws -> [SocialAccount] {
        try await client.from("social_account").select("platform, handle, followers, updated_at").execute().value
    }

    /// Saves a typed-in follower number (nil = no account there yet).
    public func save(_ account: SocialAccount) async throws {
        struct Row: Encodable { let platform: String, handle: String, followers: Int? }
        try await client.from("social_account")
            .upsert(Row(platform: account.platform.rawValue, handle: account.handle, followers: account.followers), onConflict: "owner_id,platform")
            .execute()
    }

    public func contentPieces() async throws -> [ContentPiece] {
        try await client.from("content_piece")
            .select("id, idea, platform, format, hook, body, parts, hashtags, status, lint_score, published_at, created_at, planned_for, segment_id")
            .neq("status", value: "archived")
            .order("created_at", ascending: false)
            .limit(200)
            .execute().value
    }

    public func save(_ piece: ContentPiece) async throws {
        struct Row: Encodable {
            let hook: String, body: String, parts: [String], hashtags: [String], status: String
            let lint_score: Int?, published_at: Date?
        }
        try await client.from("content_piece")
            .update(Row(hook: piece.hook, body: piece.body, parts: piece.parts, hashtags: piece.hashtags,
                        status: piece.status.rawValue, lint_score: piece.lintScore, published_at: piece.publishedAt))
            .eq("id", value: piece.id)
            .execute()
    }

    public func voiceProfile() async throws -> VoiceProfile {
        let rows: [VoiceProfile] = try await client.from("voice_profile").select("page, audience, topics, notes, never_say, brief").execute().value
        return rows.first ?? VoiceProfile()
    }

    public func save(_ voice: VoiceProfile) async throws {
        try await client.from("voice_profile").upsert(voice, onConflict: "owner_id").execute()
    }


    /// Which model each feature uses ("chat", "content"), from profile.model_prefs.
    public func modelPrefs() async throws -> [String: String] {
        struct Row: Decodable { let model_prefs: [String: String]? }
        let rows: [Row] = try await client.from("profile").select("model_prefs").execute().value
        return rows.first?.model_prefs ?? [:]
    }

    public func setModelPrefs(_ prefs: [String: String]) async throws {
        let user = try await client.auth.session.user.id
        try await client.from("profile").update(["model_prefs": prefs]).eq("owner_id", value: user).execute()
    }

    /// The daily limit for paid models in USD (profile.settings.daily_cap_usd); nil means the server default ($5).
    public func dailyCap() async throws -> Double? {
        struct Settings: Decodable { let daily_cap_usd: Double? }
        struct Row: Decodable { let settings: Settings? }
        let rows: [Row] = try await client.from("profile").select("settings").execute().value
        return rows.first?.settings?.daily_cap_usd
    }

    public func setDailyCap(_ cap: Double?) async throws {
        struct Settings: Encodable { let daily_cap_usd: Double? }
        struct Row: Encodable { let settings: Settings }
        let user = try await client.auth.session.user.id
        try await client.from("profile").update(Row(settings: Settings(daily_cap_usd: cap))).eq("owner_id", value: user).execute()
    }

    // MARK: Usage (cost meter, §24)

    public struct Usage: Decodable, Sendable {
        public let feature: String
        public let model: String
        public let costUSD: Double
        enum CodingKeys: String, CodingKey { case feature, model, costUSD = "cost_usd" }
    }

    /// What the server logged for Claude and Groq since `since` (rows are written by the server only).
    public func usage(since: Date) async throws -> [Usage] {
        // shortcut: sums on the device; add a server-side sum when a month passes a few thousand requests.
        try await client.from("model_usage").select("feature, model, cost_usd")
            .gte("at", value: since.ISO8601Format()).limit(5000).execute().value
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

    public struct ChatProblem: Error, Sendable { public let message: String }

    /// One event of a streamed answer (server-sent events from the chat function).
    public enum ChatEvent: Equatable, Sendable {
        case delta(String), reset, done(reply: String, proposed: Int), failed(String)

        /// `data: {"t":"delta","text":"Hi"}` → .delta("Hi"); nil for anything else (blank lines, comments, unknown events).
        public static func parse(line: String) -> ChatEvent? {
            guard line.hasPrefix("data:"), let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            switch object["t"] as? String {
            case "delta": return (object["text"] as? String).map(ChatEvent.delta)
            case "reset": return .reset
            case "done": return .done(reply: object["reply"] as? String ?? "Done.", proposed: object["proposed"] as? Int ?? 0)
            case "error": return .failed(object["error"] as? String ?? "Blink couldn't answer.")
            default: return nil
            }
        }
    }

    /// Asks Blink and streams the answer as it's written. Same request as `chat`, plus `stream: true`.
    public func chatStream(_ message: String, history: [ChatTurn], timeZone: String,
                           reminders: [AgendaReminder] = [], context: String? = nil,
                           spaceID: String? = nil) -> AsyncThrowingStream<ChatEvent, Error> {
        struct Reminder: Encodable { let id: String; let title: String; let due: String? }
        struct Body: Encodable {
            let message: String; let history: [ChatTurn]; let timeZone: String; let reminders: [Reminder]; let context: String?
            let space_id: String?; let stream = true
        }
        let body = Body(message: message, history: Self.recent(history), timeZone: timeZone,
                        reminders: reminders.map { Reminder(id: $0.id, title: $0.title, due: $0.due?.ISO8601Format()) },
                        context: context.map { String($0.prefix(4000)) }, space_id: spaceID)
        let endpoint = config.url.appending(path: "functions/v1/chat"), key = config.publishableKey, client = client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await client.auth.session.accessToken
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue(key, forHTTPHeaderField: "apikey")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        // Refused before streaming (no key, over the daily limit, signed out): the function says why in JSON.
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        struct ErrorBody: Decodable { let error: String }
                        throw ChatProblem(message: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Blink couldn't answer.")
                    }
                    for try await line in bytes.lines {
                        if let event = ChatEvent.parse(line: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The last turns the server accepts (20), starting with one of yours: Claude's API expects the owner to speak first,
    /// and a local Blink line (e.g. "What should I add?") can shift the order.
    static func recent(_ history: [ChatTurn]) -> [ChatTurn] {
        Array(history.suffix(20).drop { $0.role == .assistant })
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
