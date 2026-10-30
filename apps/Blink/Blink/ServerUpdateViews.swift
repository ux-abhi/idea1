// © Pexilim
import AuthenticationServices
import BlinkKit
import SwiftUI

/// Update Server: one Supabase sign-in, then Blink adds the database changes and server functions this app version
/// needs (only what's missing; nothing of yours is touched). The Supabase token is used once and never kept.
struct UpdateServerButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var installer = ServerInstaller()
    @State private var signingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { Task { await start() } } label: { Label("Update Server", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.borderedProminent)
                    .disabled(installer.working || signingIn || ServerInstaller.helper == nil)
                if installer.working || signingIn {
                    ProgressView().controlSize(.small)
                    Text(installer.step?.updateTitle ?? "Signing in with Supabase…").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let problem = installer.problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
            }
        }
    }

    private func start() async {
        guard let url = installer.startURL() else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            let callback = try await webAuth.blinkSignIn(url, for: installer.pkce, model: model)
            let token = try await installer.token(from: callback)
            await installer.update(token: token, model: model)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closing the sign-in window is not a problem worth a message.
        } catch {
            installer.fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

extension ServerInstaller.Step {
    /// What an update is doing right now, in words.
    var updateTitle: String {
        switch self {
        case .database: "Updating your data…"
        case .functions: "Updating Blink's brain…"
        default: "Updating…"
        }
    }
}

extension WebAuthenticationSession {
    /// The Supabase sign-in in the browser. Someone new to Supabase confirms their email in a new tab, and that tab's
    /// blink://signin link reaches Blink through macOS (AppDelegate), not this session: either one ends it.
    func blinkSignIn(_ url: URL, for attempt: ServerSetup.PKCE, model: AppModel) async throws -> URL {
        model.openedSignin = nil
        // Whichever answers first wins; the other is cancelled (the browser one may stay open until closed by hand).
        let (answers, answer) = AsyncStream<Result<URL, any Error>>.makeStream()
        let browser = Task {
            do { answer.yield(.success(try await authenticate(using: url, callbackURLScheme: "blink", preferredBrowserSession: nil))) }
            catch { answer.yield(.failure(error)) }
        }
        let link = Task {
            for await opened in Observations({ model.openedSignin }) { if let opened, attempt.answers(opened) { answer.yield(.success(opened)); break } }
        }
        defer { browser.cancel(); link.cancel(); answer.finish() }
        for await result in answers { return try result.get() }
        throw CancellationError()
    }
}
