// © Pexilim
import CryptoKit
import Foundation

/// One-click server setup (owner decision 2026-10-12): after "Sign in with Supabase", Blink creates the owner's own free
/// project and installs the database and server functions bundled in the app. The Supabase token is used only for this
/// and then dropped; Pexilim never holds it (the sign-in helper only passes it back to this app).
public enum ServerSetup {
    /// PKCE (RFC 7636): a random verifier stays in the app; only its SHA-256 challenge goes to the browser.
    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String
        public let state: String

        public init() {
            verifier = Self.randomURLSafe(48)
            challenge = Self.challenge(for: verifier)
            state = Self.randomURLSafe(24)
        }

        public static func challenge(for verifier: String) -> String {
            base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }

        static func randomURLSafe(_ bytes: Int) -> String {
            var data = Data(count: bytes)
            _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
            return base64URL(data)
        }

        static func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }

    /// The region nearest the owner, from their time zone (Supabase picks no default for us).
    public static func region(for timeZone: String) -> String {
        switch true {
        case timeZone.hasPrefix("Asia/Kolkata"), timeZone.hasPrefix("Asia/Calcutta"), timeZone.hasPrefix("Asia/Dhaka"),
             timeZone.hasPrefix("Asia/Karachi"), timeZone.hasPrefix("Asia/Colombo"): "ap-south-1"
        case timeZone.hasPrefix("Asia/Tokyo"), timeZone.hasPrefix("Asia/Seoul"): "ap-northeast-1"
        case timeZone.hasPrefix("Asia/"): "ap-southeast-1"
        case timeZone.hasPrefix("Australia/"), timeZone.hasPrefix("Pacific/Auckland"): "ap-southeast-2"
        case timeZone.hasPrefix("America/Los_Angeles"), timeZone.hasPrefix("America/Vancouver"), timeZone.hasPrefix("America/Denver"): "us-west-1"
        case timeZone.hasPrefix("America/Sao_Paulo"), timeZone.hasPrefix("America/Argentina"): "sa-east-1"
        case timeZone.hasPrefix("America/"): "us-east-1"
        case timeZone.hasPrefix("Europe/London"), timeZone.hasPrefix("Europe/Dublin"): "eu-west-2"
        default: "eu-central-1"
        }
    }

    /// A strong database password the owner never needs to see (Supabase requires one to create a project).
    public static func databasePassword() -> String { PKCE.randomURLSafe(30) }

    /// Where an interrupted setup got to, so "Try Again" continues instead of making a second server.
    public struct Progress {
        let defaults: UserDefaults
        public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

        public var ref: String? {
            get { defaults.string(forKey: "setup.ref") }
            nonmutating set { defaults.set(newValue, forKey: "setup.ref") }
        }
        public var ownerCreated: Bool {
            get { defaults.bool(forKey: "setup.owner") }
            nonmutating set { defaults.set(newValue, forKey: "setup.owner") }
        }
        public func done(_ step: String) -> Bool { defaults.bool(forKey: "setup.done.\(step)") }
        public func markDone(_ step: String) { defaults.set(true, forKey: "setup.done.\(step)") }

        /// Forget it all: after success, or when the saved project is gone (deleted, or another Supabase account).
        public func reset() {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("setup.") { defaults.removeObject(forKey: key) }
        }
    }

    /// The saved project no longer belongs to this Supabase sign-in (deleted, or a different account).
    public struct Gone: Error {}

    public struct Problem: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        public init(message: String) { self.message = message }
    }

    /// The Supabase Management API, as the signed-in owner.
    public struct Client: Sendable {
        let token: String
        let session: URLSession
        let base = URL(string: "https://api.supabase.com/v1/")!

        public init(token: String, session: URLSession = .shared) {
            self.token = token
            self.session = session
        }

        public struct Organization: Decodable, Sendable { public let slug: String; public let name: String }
        public struct Project: Decodable, Sendable { public let ref: String; public let status: String? }
        public struct Health: Decodable, Sendable { public let name: String; public let status: String }
        public struct Key: Decodable, Sendable { public let type: String?; public let api_key: String?; public let name: String }

        /// The URL for a Management API path; the query goes through URLComponents (`appending(path:)` would encode a `?`).
        func url(_ path: String, query: [URLQueryItem] = []) -> URL {
            var parts = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { parts.queryItems = query }
            return parts.url!
        }

        func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", json: Encodable? = nil) async throws -> Data {
            var request = URLRequest(url: url(path, query: query))
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(json)
            }
            return try await send(request)
        }

        func send(_ request: URLRequest) async throws -> Data {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let detail = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
                throw Problem(message: status == 401 || status == 403
                              ? "Supabase didn't allow that. Sign in with Supabase again."
                              : "Supabase answered \(status). \(detail)")
            }
            return data
        }

        public func organizations() async throws -> [Organization] {
            try JSONDecoder().decode([Organization].self, from: try await request("organizations"))
        }

        public func createProject(organization: String, name: String, region: String, password: String) async throws -> Project {
            struct Body: Encodable { let organization_slug: String, name: String, region: String, db_pass: String, plan = "free" }
            return try JSONDecoder().decode(Project.self, from: try await request("projects", method: "POST",
                json: Body(organization_slug: organization, name: name, region: region, db_pass: password)))
        }

        /// True once the database, sign-in and the REST API all answer; throws `Gone` when the project isn't this
        /// account's (403/404), so a stale saved project never makes setup wait forever.
        public func isReady(_ ref: String) async throws -> Bool {
            var request = URLRequest(url: url("projects/\(ref)/health", query: [URLQueryItem(name: "services", value: "db,auth,rest")]))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 || status == 404 { throw Gone() }
            guard status == 200, let health = try? JSONDecoder().decode([Health].self, from: data) else { return false }
            return health.count == 3 && health.allSatisfy { $0.status == "ACTIVE_HEALTHY" }
        }

        public func runSQL(_ ref: String, _ query: String) async throws {
            struct Body: Encodable { let query: String }
            _ = try await request("projects/\(ref)/database/query", method: "POST", json: Body(query: query))
        }

        /// Versions already applied, from the server itself (the table the Supabase CLI uses too), so a retry after a
        /// lost reply never runs a migration twice.
        public func appliedMigrations(_ ref: String) async throws -> Set<String> {
            struct Body: Encodable { let query: String }
            struct Row: Decodable { let version: String }
            try await runSQL(ref, Migration.ledger)
            let data = try await request("projects/\(ref)/database/query", method: "POST",
                                         json: Body(query: "select version from supabase_migrations.schema_migrations"))
            return Set(try JSONDecoder().decode([Row].self, from: data).map(\.version))
        }

        /// Uploads one function's files (its own and the shared ones), named as the CLI names them.
        public func deployFunction(_ ref: String, slug: String, files: [(path: String, data: Data)], verifyJWT: Bool) async throws {
            let boundary = "blink-\(UUID().uuidString)"
            var body = Data()
            func part(_ header: String, _ content: Data) {
                body.append(Data("--\(boundary)\r\n\(header)\r\n\r\n".utf8))
                body.append(content)
                body.append(Data("\r\n".utf8))
            }
            let metadata = try JSONSerialization.data(withJSONObject: [
                "entrypoint_path": "supabase/functions/\(slug)/index.ts", "name": slug, "verify_jwt": verifyJWT,
            ])
            part("Content-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json", metadata)
            for file in files {
                part("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.path)\"\r\nContent-Type: application/typescript", file.data)
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            var request = URLRequest(url: url("projects/\(ref)/functions/deploy", query: [URLQueryItem(name: "slug", value: slug)]))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            _ = try await send(request)
        }

        public func setSecrets(_ ref: String, _ secrets: [String: String]) async throws {
            struct Secret: Encodable { let name: String, value: String }
            guard !secrets.isEmpty else { return }
            _ = try await request("projects/\(ref)/secrets", method: "POST", json: secrets.map { Secret(name: $0.key, value: $0.value) })
        }

        /// The publishable key (for the apps) and a secret key (used once here, to create the owner's login).
        public func keys(_ ref: String) async throws -> (publishable: String, secret: String) {
            let keys = try JSONDecoder().decode([Key].self, from: try await request("projects/\(ref)/api-keys", query: [URLQueryItem(name: "reveal", value: "true")]))
            guard let publishable = keys.first(where: { $0.type == "publishable" })?.api_key ?? keys.first(where: { $0.name == "anon" })?.api_key,
                  let secret = keys.first(where: { $0.type == "secret" })?.api_key ?? keys.first(where: { $0.name == "service_role" })?.api_key else {
                throw Problem(message: "Supabase didn't return the project's keys yet. Try again in a minute.")
            }
            return (publishable, secret)
        }

        /// Turns off public sign-ups: only the owner's login exists on their server (§33).
        public func closeSignups(_ ref: String) async throws {
            struct Body: Encodable { let disable_signup = true }
            _ = try await request("projects/\(ref)/config/auth", method: "PATCH", json: Body())
        }
    }

    /// Creates the owner's login on their new server with the secret key, confirmed so they can sign in at once.
    public static func createOwner(projectURL: URL, secretKey: String, email: String, password: String,
                                   session: URLSession = .shared) async throws {
        var request = URLRequest(url: projectURL.appending(path: "auth/v1/admin/users"))
        request.httpMethod = "POST"
        request.setValue(secretKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "email_confirm": true])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        // Already there (a retry after a lost reply): that's the login we wanted.
        if status == 422, text.localizedCaseInsensitiveContains("already") { return }
        guard (200..<300).contains(status) else { throw Problem(message: "Couldn't create your login: \(text.prefix(160))") }
    }

    /// One bundled migration file, applied in a transaction together with its row in the migrations ledger: either both
    /// land or neither, so "Try Again" can always tell what is done.
    public struct Migration: Sendable, Equatable {
        public let version: String
        public let name: String

        static let ledger = "create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);"

        /// `20261012130000_money_accounts.sql` → version `20261012130000`, name `money_accounts`; nil for anything else.
        public init?(fileName: String) {
            guard fileName.hasSuffix(".sql") else { return nil }
            let stem = fileName.dropLast(4)
            let version = String(stem.prefix(while: \.isNumber))
            let name = stem.dropFirst(version.count).drop(while: { $0 == "_" })
            guard version.count >= 8, !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
            self.version = version
            self.name = String(name)
        }

        /// The migration plus its ledger row in one transaction (version and name are digits and letters only).
        public func wrapped(_ sql: String) -> String {
            "begin;\n\(sql)\n;\ninsert into supabase_migrations.schema_migrations (version, name) values ('\(version)', '\(name)') on conflict do nothing;\ncommit;"
        }
    }

    /// Which bundled functions go to an owner's server, and whether each checks the login itself (mail does).
    /// The sign-in helper and retired probes are Pexilim-only and never installed.
    public static func installable(_ names: [String]) -> [(slug: String, verifyJWT: Bool)] {
        names.filter { !$0.hasPrefix("_") && !["signin", "mail-probe"].contains($0) }.sorted()
            .map { ($0, $0 != "mail") }
    }
}
