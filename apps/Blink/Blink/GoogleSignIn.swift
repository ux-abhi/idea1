// © Pexilim
#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Network

/// One-click Google with Blink's built-in Desktop client (Google's method for installed apps): PKCE, and for a moment a
/// listener on 127.0.0.1 only, which takes Google's one redirect. The code goes to the owner's server, which exchanges it;
/// no Google token ever sits on the Mac.
enum GoogleSignIn {
    /// Blink's Google client from the build (Local.xcconfig); nil means owners use their own Google app.
    static var client: (id: String, secret: String)? {
        let id = Bundle.main.object(forInfoDictionaryKey: "BlinkGoogleClientID") as? String ?? ""
        let secret = Bundle.main.object(forInfoDictionaryKey: "BlinkGoogleClientSecret") as? String ?? ""
        return id.isEmpty || secret.isEmpty ? nil : (id, secret)
    }

    struct Answer: Sendable { let code: String; let verifier: String; let redirect: String }
    struct Problem: Error { let message: String }

    /// Opens Google's page and waits (up to 5 minutes) for its answer on 127.0.0.1.
    static func authorize(clientID: String) async throws -> Answer {
        let verifier = random(48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = random(24)
        let receiver = try LoopbackReceiver()
        let port = try await receiver.start()
        let redirect = "http://127.0.0.1:\(port)"
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email https://www.googleapis.com/auth/calendar.events"),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        NSWorkspace.shared.open(url.url!)
        let query = try await receiver.firstRequest(state: state, timeout: 300)
        if query["error"] != nil { throw Problem(message: "Google sign-in was cancelled.") }
        guard let code = query["code"], !code.isEmpty else { throw Problem(message: "Google didn't send a sign-in code. Try again.") }
        return Answer(code: code, verifier: verifier, redirect: redirect)
    }

    /// URL-safe random text for the PKCE verifier and the state.
    private static func random(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URL
    }
}

private nonisolated extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A one-shot HTTP listener on 127.0.0.1: it waits for the browser's redirect carrying this sign-in's `state`, answers it
/// with a short page, then stops. Anything else gets a 400 and the wait goes on. All state lives on `queue`, so the wait
/// ends exactly once: the redirect, the timeout, or the caller cancelling.
private nonisolated final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "blink.google.loopback")
    private var done = false
    private var started = false
    private var state = ""
    private var waiting: CheckedContinuation<[String: String], Error>?
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// The port it listens on, once ready.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.newConnectionHandler = { [self] connection in handle(connection) }
            listener.stateUpdateHandler = { [self] state in
                guard !started else { return }
                switch state {
                case .ready:
                    started = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    started = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// The redirect's query items (its `state` matches); throws on timeout or when the calling task is cancelled.
    func firstRequest(state: String, timeout: TimeInterval) async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
                queue.async { [self] in
                    self.state = state
                    if done { continuation.resume(throwing: CancellationError()) } else { waiting = continuation }
                }
                queue.asyncAfter(deadline: .now() + timeout) { [self] in
                    finish(.failure(GoogleSignIn.Problem(message: "Google sign-in timed out. Try again.")))
                }
            }
        } onCancel: {
            queue.async { [self] in finish(.failure(CancellationError())) }
        }
    }

    /// Ends the wait once: stops listening and closes every connection the browser opened.
    private func finish(_ result: Result<[String: String], Error>) {
        guard !done else { return }
        done = true
        listener.cancel()
        connections.forEach { $0.cancel() }
        waiting?.resume(with: result)
        waiting = nil
    }

    private func handle(_ connection: NWConnection) {
        guard !done else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // "GET /?code=…&state=… HTTP/1.1": only the path's query matters.
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
            let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            // Only Google's redirect for this sign-in counts; a favicon or a stray local request doesn't end it.
            guard !done, !state.isEmpty, query["state"] == state else {
                reply(connection, status: "400 Bad Request", text: "This isn't the Blink sign-in.")
                return
            }
            // The server hasn't exchanged the code yet, so the page doesn't claim it's done.
            reply(connection, status: "200 OK", text: query["code"] != nil
                  ? "Almost done. Go back to Blink to finish connecting Google."
                  : "Google didn't connect. Go back to Blink and try again.")
            finish(.success(query))
        }
    }

    private func reply(_ connection: NWConnection, status: String, text: String) {
        let body = "<!doctype html><meta charset=utf-8><title>Blink</title><p style=\"font:16px -apple-system;margin:40px\">\(text)"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
#endif
