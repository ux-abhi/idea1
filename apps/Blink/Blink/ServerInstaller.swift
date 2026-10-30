// © Pexilim
import BlinkKit
import Foundation
import Observation

/// "Sign in with Supabase" → the owner's own Blink server, made and set up for them (onboarding step 1).
/// Progress is saved after each step, so "Try again" resumes instead of making a second server.
@Observable
final class ServerInstaller {
    enum Step: Int, CaseIterable {
        case create, start, database, functions, lock, connect
        var title: String {
            switch self {
            case .create: "Creating your server"
            case .start: "Starting it up (about 2 minutes)"
            case .database: "Setting up your data"
            case .functions: "Installing Blink's brain"
            case .lock: "Locking it to you"
            case .connect: "Connecting Blink"
            }
        }
    }

    private(set) var step: Step?
    private(set) var problem: String?
    private(set) var working = false

    /// The helper from Local.xcconfig; nil (no button) when this build has none.
    static var helper: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "BlinkSigninHelper") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// Fresh for every attempt, so a retry never reuses a challenge or state.
    private(set) var pkce = ServerSetup.PKCE()
    let progress = ServerSetup.Progress()

    /// The page the browser opens (the helper forwards it to Supabase's consent screen); each call starts a new attempt.
    func startURL() -> URL? {
        guard let helper = Self.helper else { return nil }
        pkce = ServerSetup.PKCE()
        var parts = URLComponents(url: helper.appending(path: "start"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "challenge", value: pkce.challenge), URLQueryItem(name: "state", value: pkce.state)]
        return parts.url
    }

    /// The browser came back with blink://signin?code=…&state=…: trade the code for a Supabase token (through the helper).
    func token(from callback: URL) async throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Only answers to this attempt count, errors included, and only fixed words are shown (never text from the link).
        guard pkce.answers(callback) else {
            throw ServerSetup.Problem(message: "That sign-in didn't come from this Blink. Start again.")
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw ServerSetup.Problem(message: error == "access_denied" ? "You didn't allow Blink in Supabase. Try again when you're ready." : "Supabase sign-in didn't finish. Try again.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, let helper = Self.helper else {
            throw ServerSetup.Problem(message: "That sign-in didn't come from this Blink. Start again.")
        }
        var request = URLRequest(url: helper.appending(path: "token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": pkce.verifier])
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Reply: Decodable { let access_token: String?; let error: String? }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200, let token = reply?.access_token else {
            throw ServerSetup.Problem(message: reply?.error ?? "Supabase didn't accept the sign-in. Start again.")
        }
        return token
    }

    /// Something failed before the install began (the browser sign-in or the token).
    func fail(_ message: String) { problem = message }

    /// Makes and sets up the server, creates the owner's login (made up by Blink and kept in the Keychain, so there's no
    /// password to invent), then connects and signs in. AI works without a key (Apple's on-device model).
    func install(token: String, model: AppModel) async {
        guard !working else { return }
        working = true
        problem = nil
        defer { working = false }
        do {
            let login = try model.setupLogin()
            do {
                try await run(ServerSetup.Client(token: token), email: login.email, password: login.password, model: model)
            } catch is ServerSetup.Gone {
                // The saved project isn't this account's any more (deleted, or another Supabase account): start over once.
                progress.reset()
                try await run(ServerSetup.Client(token: token), email: login.email, password: login.password, model: model)
            }
            progress.reset()
            step = nil
        } catch is ServerSetup.Gone {
            problem = "Supabase doesn't let this account use that server. Try again, signing in with the account you want Blink on."
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func run(_ api: ServerSetup.Client, email: String, password: String, model: AppModel) async throws {
        // 1. The project (once: its ref is kept, so a retry continues with it).
        step = .create
        if progress.ref == nil {
            guard let org = try await api.organizations().first else {
                throw ServerSetup.Problem(message: "Your Supabase account has no organization yet. Create one at supabase.com, then try again.")
            }
            let project = try await api.createProject(organization: org.slug, name: "Blink",
                                                      region: ServerSetup.region(for: TimeZone.current.identifier),
                                                      password: ServerSetup.databasePassword())
            progress.ref = project.ref
        }
        guard let ref = progress.ref else { return }
        let projectURL = URL(string: "https://\(ref).supabase.co")!

        // 2. Wait until it answers (new projects take a minute or two).
        step = .start
        var waited = 0
        while try !(await api.isReady(ref)) {
            guard waited < 600 else { throw ServerSetup.Problem(message: "Your server is taking longer than usual to start. Try again in a few minutes.") }
            try await Task.sleep(for: .seconds(5))
            waited += 5
        }

        // 3–4. The database and the server functions, then a note of which package the server now runs.
        try await installPackage(api, ref: ref)
        let bundle = try Self.bundledServer()

        // 5. The owner's login, then nobody else's; each schedule once.
        step = .lock
        let keys = try await api.keys(ref)
        if !progress.ownerCreated {
            try await Self.createLogin(api, ref: ref, projectURL: projectURL, keys: keys, email: email, password: password)
            progress.ownerCreated = true
        }
        try? model.saveLogin(email: email, password: password, host: projectURL.host())
        try await api.closeSignups(ref)
        if !progress.done("mailSchedule") {
            let mail = try String(contentsOf: bundle.appending(path: "setup/mail_schedule.sql"), encoding: .utf8)
                .replacingOccurrences(of: "<PROJECT_URL>", with: projectURL.absoluteString)
            try await api.runSQL(ref, mail)
            progress.markDone("mailSchedule")
        }
        if !progress.done("cleanupSchedule") {
            try await api.runSQL(ref, String(contentsOf: bundle.appending(path: "setup/cleanup_schedule.sql"), encoding: .utf8))
            progress.markDone("cleanupSchedule")
        }

        // The server is complete: nothing to resume from here on.
        progress.reset()

        // 6. Into Blink: the same as connecting to a server by hand, then signing in. Connecting already shows the
        // Sign in screen (this view is gone), so a failed sign-in is told there.
        step = .connect
        try await model.connect(url: projectURL.absoluteString, key: keys.publishable)
        if let failure = await model.signIn(email: email, password: password) {
            model.noteSignIn("Your server is ready. Sign in to finish: \(failure)")
        }
    }

    /// The database changes this server doesn't have yet, in order (each only once, by the server's own record), then
    /// every server function (deploying again just replaces it), then the package fingerprint, so the app can tell later
    /// whether the server is behind. Shared by setup and Update Server.
    private func installPackage(_ api: ServerSetup.Client, ref: String) async throws {
        step = .database
        let bundle = try Self.bundledServer()
        let files = try FileManager.default.contentsOfDirectory(at: bundle.appending(path: "migrations"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .map { file in
                // A name Blink can't read must stop setup, never be skipped: later migrations build on it.
                guard let migration = ServerSetup.Migration(fileName: file.lastPathComponent) else {
                    throw ServerSetup.Problem(message: "This copy of Blink has a server file it can't read (\(file.lastPathComponent)). Update Blink.")
                }
                return (file, migration)
            }
        for migration in ServerSetup.Migration.pending(files.map(\.1), record: try await api.ledger(ref)) {
            guard let file = files.first(where: { $0.1 == migration })?.0 else {
                throw ServerSetup.Problem(message: "This copy of Blink is missing a server file (\(migration.name)). Update Blink.")
            }
            try await api.runSQL(ref, migration.wrapped(try String(contentsOf: file, encoding: .utf8)))
        }

        step = .functions
        let functionsDir = bundle.appending(path: "functions")
        let shared = try Self.files(in: functionsDir.appending(path: "_shared"), as: "supabase/functions/_shared")
        let names = try FileManager.default.contentsOfDirectory(atPath: functionsDir.path)
        for function in ServerSetup.installable(names) {
            let own = try Self.files(in: functionsDir.appending(path: function.slug), as: "supabase/functions/\(function.slug)")
            try await api.deployFunction(ref, slug: function.slug, files: own + shared, verifyJWT: function.verifyJWT)
        }

        // The fingerprint is 32 hex characters, so it goes into the SQL as is.
        let package = try Self.bundledPackageID()
        try await api.runSQL(ref, "insert into public.server_info (key, value) values ('package', '\(package)') on conflict (key) do update set value = excluded.value, updated_at = now();")
    }

    /// Brings the connected server up to this app's package after an app update: one Supabase sign-in, then only what's
    /// missing. The token is used for this and dropped; Blink never keeps it.
    func update(token: String, model: AppModel) async {
        guard !working else { return }
        working = true
        problem = nil
        defer { working = false }
        do {
            guard let url = model.server?.config.url, let ref = BlinkServer.projectRef(url) else {
                throw ServerSetup.Problem(message: "Blink can only update a server on Supabase. Update yours from its own dashboard.")
            }
            try await installPackage(ServerSetup.Client(token: token), ref: ref)
            step = nil
            await model.checkServerPackage()
        } catch let error as ServerSetup.Problem where error.message.contains("403") || error.message.contains("404") {
            step = nil
            problem = "Supabase doesn't let this account change your server. Sign in with the Supabase account that owns it."
        } catch {
            step = nil
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The bundled package's fingerprint, worked out once per launch (the files never change while Blink runs).
    static let packageID: String? = try? bundledPackageID()

    /// The fingerprint of the server package inside this app (every migration and function file).
    static func bundledPackageID() throws -> String {
        let bundle = try bundledServer()
        let migrations = try FileManager.default.contentsOfDirectory(at: bundle.appending(path: "migrations"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .map { ("migrations/\($0.lastPathComponent)", try Data(contentsOf: $0)) }
        let functionsDir = bundle.appending(path: "functions")
        // Only what goes to a customer's server: the shared code and the installable functions (not Pexilim's own).
        let names = try FileManager.default.contentsOfDirectory(atPath: functionsDir.path)
        let functions = try (["_shared"] + ServerSetup.installable(names).map(\.slug))
            .flatMap { try files(in: functionsDir.appending(path: $0), as: "functions/\($0)") }
        return ServerSetup.packageID(migrations + functions)
    }

    /// The owner's login on a server, without the secret key when Supabase hides it from apps like Blink: open sign-ups
    /// (with no confirmation email) for this one login; the caller locks them again. The setting takes about 10 seconds to
    /// go live, so wait, then retry while the server is busy; then mark it confirmed.
    static func createLogin(_ api: ServerSetup.Client, ref: String, projectURL: URL, keys: (publishable: String, secret: String?),
                            email: String, password: String) async throws {
        if let secret = keys.secret {
            try await ServerSetup.createOwner(projectURL: projectURL, secretKey: secret, email: email, password: password)
            return
        }
        try await api.openSignupsForOwner(ref)
        do {
            try await Task.sleep(for: .seconds(15))
            var tries = 0
            while true {
                do {
                    try await ServerSetup.signUpOwner(projectURL: projectURL, publishableKey: keys.publishable, email: email, password: password)
                    break
                } catch is ServerSetup.Busy where tries < 8 {
                    tries += 1
                    try await Task.sleep(for: .seconds(5))
                }
            }
            try await api.confirmOwner(ref, email: email)
        } catch {
            try? await api.closeSignups(ref)
            throw error is ServerSetup.Busy ? ServerSetup.Problem(message: "Your server was busy creating your login. Try again in a minute.") : error
        }
    }

    /// "Sign in with Supabase" on the Sign in step, for a server that already exists (made on another Mac, or by hand):
    /// no login yet → Blink makes one; its one owner login → a fresh password, kept in this Mac's Keychain. Then signs in.
    func signInToExisting(token: String, model: AppModel) async {
        guard !working, let server = model.server, let ref = BlinkServer.projectRef(server.config.url) else { return }
        working = true
        problem = nil
        defer { working = false }
        let api = ServerSetup.Client(token: token)
        do {
            let logins: [String]
            do { logins = try await api.loginEmails(ref) } catch let error as ServerSetup.Problem where error.message.contains("403") || error.message.contains("404") {
                throw ServerSetup.Problem(message: "This server isn't in the Supabase account you signed in with. Sign in with the account that owns it.")
            }
            var email = "", password = ""
            do {
                switch logins.count {
                case 0:
                    (email, password) = try model.setupLogin()
                    step = .lock
                    try await Self.createLogin(api, ref: ref, projectURL: server.config.url, keys: try await api.keys(ref), email: email, password: password)
                case 1:
                    // shortcut: one password per owner, so signing in here can change another Mac's saved one (that Mac
                    // stays signed in, and the same button brings it back). Upgrade with QR pairing (§36.5).
                    if let saved = model.savedLogin, saved.email == logins[0], await model.signIn(email: saved.email, password: saved.password) == nil {
                        (email, password) = saved
                    } else {
                        (email, password) = (logins[0], try SetupLogin.newPassword())
                        try await api.setPassword(ref, email: email, password: password)
                    }
                default:
                    throw ServerSetup.Problem(message: "This server has more than one login. Sign in below with yours.")
                }
            } catch {
                // Sign-ups never stay open, whatever failed (a dropped connection mid-way included).
                try? await api.closeSignups(ref)
                throw error
            }
            // Every path, every time: cheap, and it closes sign-ups an earlier failed try may have left open.
            try await api.closeSignups(ref)
            try model.saveLogin(email: email, password: password, host: server.config.host)
            step = .connect
            if let failure = await model.signIn(email: email, password: password) { problem = failure }
            step = nil
        } catch {
            step = nil
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The server package inside the app: backend/supabase's migrations, functions and setup, bundled at build time.
    static func bundledServer() throws -> URL {
        guard let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appending(path: "migrations").path) else {
            throw ServerSetup.Problem(message: "This copy of Blink is missing its server package. Reinstall Blink.")
        }
        return url
    }

    /// A function folder's TypeScript files (tests left out), named as they'll sit on the server.
    static func files(in folder: URL, as prefix: String) throws -> [(path: String, data: Data)] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "ts" && !$0.lastPathComponent.hasSuffix("_test.ts") }
            .map { ("\(prefix)/\($0.lastPathComponent)", try Data(contentsOf: $0)) }
    }
}
