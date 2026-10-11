// © Pexilim
import BlinkKit
import EventKit
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// First run → sign in → home, plus the app lock.
@Observable
final class AppModel {
    enum Screen: Equatable { case loading, connect, signIn, home }
    enum Status: Equatable { case checking, connected, unreachable }

    private(set) var screen: Screen = .loading
    private(set) var server: BlinkServer?
    private(set) var email: String?
    private(set) var status: Status = .checking
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "lastSync") as? Date
    /// Shown above the sign-in form, e.g. after the server ended the session.
    private(set) var signInNotice: String?

    private var refreshing = false

    /// Ask-First cards waiting for the user (§6).
    private(set) var pending: [BlinkAction] = []
    private(set) var actionProblem: String?

    private(set) var agenda = Agenda.empty
    private(set) var calendarAccess = CalendarReader.access
    private let calendarReader = CalendarReader()
    private var watchingCalendar = false

    private(set) var locked = true
    private var awaySince: Date?
    /// The unlock prompt opens by itself once per lock; the prompt itself makes the scene inactive and active again.
    private var promptPending = true

    private let keychain = Keychain(service: Bundle.main.bundleIdentifier ?? "blink")

    // MARK: Server and account

    func load() async {
        guard screen == .loading else { return }
        if let saved = await BlinkServer.restore(keychain: keychain) {
            server = saved.server
            email = saved.email
            screen = email == nil ? .signIn : .home
        } else {
            screen = .connect
        }
        if calendarAccess == .granted { await startCalendar() }
    }

    func connect(url: String, key: String) async throws(ServerConfig.Problem) {
        let config = try ServerConfig.validate(url: url, key: key)
        // shortcut: a failed Keychain write only means the next launch asks for the server again; handle it when QR pairing (§36.5) replaces this screen.
        try? await BlinkServer.save(config, keychain: keychain)
        server = BlinkServer(config: config, keychain: keychain)
        signInNotice = nil
        screen = .signIn
    }

    func useDifferentServer() async {
        await BlinkServer.forget(keychain: keychain)
        server = nil
        screen = .connect
    }

    /// Returns a sentence to show when sign-in fails.
    func signIn(email: String, password: String) async -> String? {
        guard let server else { return nil }
        do {
            self.email = try await server.signIn(email: email, password: password)
            signInNotice = nil
            screen = .home // Home checks in when it appears
            return nil
        } catch {
            return switch ServerProblem(error) {
            case .wrongLogin, .signedOut: "That email and password don't match an account on this server."
            case .unreachable: "Can't reach \(server.config.host). Check your connection and the Project URL."
            case .other(let message): message
            }
        }
    }

    /// Checks in with the server: registers this device, creates the profile, records the sync time.
    func refresh() async {
        // One check-in at a time, or two could each register this device.
        guard let server, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        status = .checking
        do {
            let at = try await server.checkIn(platform: Self.platform, deviceName: Self.deviceName,
                                              timeZone: TimeZone.current.identifier)
            lastSync = at
            UserDefaults.standard.set(at, forKey: "lastSync")
            status = .connected
            // Creating the key shows no prompt; only signing a red approval asks for Touch ID.
            try? await server.enrollApprovalKeyIfNeeded()
            await reloadAgenda()
            await loadActions()
        } catch {
            switch ServerProblem(error) {
            case .signedOut:
                await endSession(notice: "You've been signed out. Sign in again to continue.")
            case .unreachable:
                status = .unreachable
            case .wrongLogin, .other:
                // shortcut: anything else is shown as unreachable; split out when sync adds real failure modes.
                status = .unreachable
            }
        }
    }

    func signOut() async {
        await endSession(notice: nil)
    }

    private func endSession(notice: String?) async {
        await server?.signOut()
        email = nil
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: "lastSync")
        signInNotice = notice
        screen = .signIn
    }

    // MARK: Ask-First

    /// shortcut: fetched on check-in and when the notch opens; subscribe with Realtime when server-side proposers land (Phase 3).
    func loadActions() async {
        guard let server, email != nil, let actions = try? await server.pendingActions() else { return }
        pending = actions
    }

    func approve(_ action: BlinkAction) async {
        guard let server else { return }
        actionProblem = nil
        do {
            switch action.risk {
            case .red:
                // shortcut: approval only; the server executors (mail, posts) and the 10 s "Sending… Cancel" land with them.
                try await server.approveRed(action)
            case .green, .amber:
                try await server.setStatus("approved", for: action)
                try await execute(action, server: server)
            }
            pending.removeAll { $0.id == action.id }
        } catch ApprovalKey.Problem.cancelled {
            // Cancel keeps the card (§36.5).
        } catch {
            actionProblem = "That didn't work. Check your connection and try again."
        }
    }

    func dismiss(_ action: BlinkAction) async {
        guard let server else { return }
        do {
            try await server.setStatus("declined", for: action)
            pending.removeAll { $0.id == action.id }
        } catch {
            actionProblem = "Couldn't dismiss. Check your connection and try again."
        }
    }

    /// Actions this device can carry out after approval. Unknown kinds stay approved for whoever handles them.
    private func execute(_ action: BlinkAction, server: BlinkServer) async throws {
        switch action.kind {
        case "reminder.add":
            do {
                let id = try await calendarReader.addReminder(action.payload.reminder ?? action.title, due: action.payload.due)
                try await server.setStatus("done", for: action, result: ["reminder_id": id])
            } catch {
                // Approved but not done: say so in the log rather than leave it looking approved.
                try? await server.setStatus("failed", for: action, result: ["error": error.localizedDescription])
                throw error
            }
        default:
            break
        }
    }

    // MARK: Calendar

    /// Asked only when the user taps Connect Calendar, never at launch.
    func connectCalendar() async {
        calendarAccess = await calendarReader.requestAccess()
        if calendarAccess == .granted { await startCalendar() }
    }

    private func startCalendar() async {
        await reloadAgenda()
        guard !watchingCalendar else { return }
        watchingCalendar = true
        Task {
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                await reloadAgenda()
            }
        }
    }

    /// Re-reads the calendar and uploads the snapshot when signed in.
    /// shortcut: reloads on launch, sign-in, check-in, calendar changes, wake and unlock; no midnight reload for a Mac left awake overnight; add one if reminders show stale.
    func reloadAgenda() async {
        guard calendarAccess == .granted else { return }
        let window = CalendarReader.window(from: .now)
        agenda = await calendarReader.agenda(in: window)
        guard let server, email != nil else { return }
        // The device is the source of truth; a failed upload is simply retried by the next reload.
        try? await server.uploadCalendar(agenda.events, window: window)
    }

    // MARK: App lock

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            if AppLock.shouldRelock(awaySince: awaySince) {
                locked = true
                promptPending = true
            }
            awaySince = nil
        } else if awaySince == nil {
            awaySince = .now
        }
    }

    func unlockIfPending() async {
        guard locked, promptPending else { return }
        promptPending = false
        await unlock()
    }

    func unlock() async {
        switch await AppLock.unlock(reason: "Unlock Blink") {
        case .unlocked, .unavailable: locked = false
        case .cancelled: break // stay on the lock screen, never a blank app
        }
    }

    // MARK: This device

    private static var platform: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    private static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}
