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
    private var pkce = ServerSetup.PKCE()
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
        guard items.first(where: { $0.name == "state" })?.value == pkce.state else {
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

        // 3. The database, migration by migration, in order; each one only once (the server's own ledger says which).
        step = .database
        let bundle = try Self.bundledServer()
        // shortcut: the ledger is the only record; an install half-done by the old counter-based build would rerun
        // migration 1 and stop. Only the owner ran that build, and finished; seed the ledger if another case appears.
        let files = try FileManager.default.contentsOfDirectory(at: bundle.appending(path: "migrations"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .map { file in
                // A name Blink can't read must stop setup, never be skipped: later migrations build on it.
                guard let migration = ServerSetup.Migration(fileName: file.lastPathComponent) else {
                    throw ServerSetup.Problem(message: "This copy of Blink has a server file it can't read (\(file.lastPathComponent)). Update Blink.")
                }
                return (file, migration)
            }
            .sorted { $0.1.version < $1.1.version }
        let applied = try await api.appliedMigrations(ref)
        for (file, migration) in files where !applied.contains(migration.version) {
            try await api.runSQL(ref, migration.wrapped(try String(contentsOf: file, encoding: .utf8)))
        }

        // 4. The server functions (each with the shared code they import). Deploying again just replaces them.
        step = .functions
        let functionsDir = bundle.appending(path: "functions")
        let shared = try Self.files(in: functionsDir.appending(path: "_shared"), as: "supabase/functions/_shared")
        let names = try FileManager.default.contentsOfDirectory(atPath: functionsDir.path)
        for function in ServerSetup.installable(names) {
            let own = try Self.files(in: functionsDir.appending(path: function.slug), as: "supabase/functions/\(function.slug)")
            try await api.deployFunction(ref, slug: function.slug, files: own + shared, verifyJWT: function.verifyJWT)
        }

        // 5. The owner's login, then nobody else's; each schedule once.
        step = .lock
        let keys = try await api.keys(ref)
        if !progress.ownerCreated {
            if let secret = keys.secret {
                try await ServerSetup.createOwner(projectURL: projectURL, secretKey: secret, email: email, password: password)
            } else {
                // Supabase keeps the secret key from apps like Blink: open sign-ups (with no confirmation email) for this one
                // login, then lock them below. The setting takes about 10 seconds to go live, so wait, then retry while busy.
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
            progress.ownerCreated = true
        }
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
