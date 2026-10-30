// © Pexilim
import BlinkKit
import EventKit
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// First run → sign in → home, plus the app lock.
@Observable
final class AppModel {
    enum Screen: Equatable { case loading, connect, signIn, home }
    enum Status: Equatable { case checking, connected, unreachable }

    private(set) var screen: Screen = .loading

    /// Which server keys work ("ok", "missing", "rejected"), checked once per launch; nil until known.
    private(set) var keyStatus: [String: String]?

    func loadKeyStatus() async {
        guard let server, email != nil, let status = try? await server.connections() else { return }
        keyStatus = status
    }

    /// Settings › Connections checked the keys itself: share the answer, so setup prompts update at once.
    func updateKeyStatus(_ status: [String: String]) { keyStatus = status }

    /// Opens Settings from anywhere (the notch, a prompt), captured from the window's scene; works with it closed too.
    var settingsOpener: (() -> Void)?
    /// Opens a new Blink window when the last one was closed (SwiftUI's openWindow, captured by RootView).
    var windowOpener: (() -> Void)?
    /// The notch's own actions, for the tour's Try It buttons (set when the notch starts).
    enum NotchAction { case open, chat, clipboard }
    var notchAction: ((NotchAction) -> Void)?

    /// What's still to set up, in order (Today shows the ring; pages show their own step where it's needed).
    var setupSteps: [SetupStep] {
        SetupStep.all(keys: keyStatus, calendarGranted: calendarAccess == .granted, voicePage: voice.page,
                      mailConnected: mailStates.contains { $0.lastError == nil }, hasAccount: !accounts.isEmpty,
                      hasHabit: !habits.isEmpty, onDeviceAI: OnDeviceChat.problem == nil, content: showsContent)
    }

    /// The owner posts on social media: Content, its drafts and the Instagram step show. Asked at the end of setup;
    /// installs from before that question keep it on.
    /// Off by default: the notch hides from screenshots, recordings and screen sharing (§36.1). On for demo videos.
    var notchInRecordings = UserDefaults.standard.bool(forKey: "notch.inRecordings") {
        didSet { UserDefaults.standard.set(notchInRecordings, forKey: "notch.inRecordings") }
    }
    var showsContent = UserDefaults.standard.object(forKey: "features.content") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsContent, forKey: "features.content") }
    }

    // MARK: The login Blink makes on a server it sets up (no password to invent; see SetupLogin)

    func setupLogin() throws -> (email: String, password: String) { try SetupLogin.make(in: keychain) }
    var savedLogin: (email: String, password: String)? { SetupLogin.saved(in: keychain) }
    func saveLogin(email: String, password: String, host: String?) throws {
        try SetupLogin.save(email: email, password: password, host: host, in: keychain)
    }
    /// The server the saved login is for; Blink signs in by itself only there.
    var savedLoginHost: String? { SetupLogin.savedHost(in: keychain) }
    /// The owner pressed Sign Out: the Sign in screen then waits for them instead of signing straight back in (kept
    /// across relaunches, so signing out sticks).
    private(set) var signedOutOnPurpose = UserDefaults.standard.bool(forKey: "signedOutOnPurpose") {
        didSet { UserDefaults.standard.set(signedOutOnPurpose, forKey: "signedOutOnPurpose") }
    }

    /// The server's Supabase project when the free plan paused it (HTTP 540 after a week unused); nil otherwise.
    private(set) var pausedProject: String?

    /// Once, after setup: the notch shows the three shortcuts, one after another.
    func showShortcutTips() {
        #if os(macOS)
        guard !UserDefaults.standard.bool(forKey: "tips.shortcuts") else { return }
        UserDefaults.standard.set(true, forKey: "tips.shortcuts")
        Task {
            for tip in ["⌃⌥Space: ask Blink anything, right here", "⌃⌥V: everything you copied today", "⌃⌥K: find any note, task or reminder"] {
                announce(tip)
                try? await Task.sleep(for: .seconds(7))
            }
        }
        #endif
    }

    /// True when no AI key works: chat and drafts can't run until one is added.
    var aiKeyMissing: Bool { setupSteps.first { $0.id == .aiKey }?.done == false }

    /// True when the connected server runs an older Blink server package than this app carries (after an app update),
    /// so Today and Settings offer Update Server. A server from before the package record counts as behind.
    private(set) var serverBehind = false

    func checkServerPackage() async {
        // Only servers on Supabase can be updated by Blink; others never get a package record, so never a banner.
        guard let server, BlinkServer.projectRef(server.config.url) != nil, let bundled = ServerInstaller.packageID else { return }
        do {
            serverBehind = try await server.serverPackage() != bundled // no record yet (an older server) counts as behind
        } catch {
            // Offline or another problem: say nothing rather than guess.
        }
    }

    /// Brings the Blink window forward, or opens it again if it was closed.
    func showWindow() {
        #if os(macOS)
        NSApp.unhide(nil)
        NSApp.activate()
        // The main window only (WindowGroup id "main"), never the Keyboard Shortcuts window. A closed window stays in
        // NSApp.windows but can't be shown again, so only an open or minimised one is reused.
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.identifier?.rawValue.hasPrefix("main") == true
                                                     && ($0.isVisible || $0.isMiniaturized) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            windowOpener?()
        }
        #endif
    }

    /// Goes where a setup step is fixed: a Settings tab or a window page.
    func go(to destination: String) {
        if destination.hasPrefix("settings:") { openSettings(String(destination.dropFirst(9))) }
        else {
            #if os(macOS)
            showWindow()
            #endif
            openPage = destination
        }
    }

    /// Opens Settings at a tab ("general", "usage", "connections"…), bringing Blink forward.
    func openSettings(_ tab: String? = nil) {
        if let tab { UserDefaults.standard.set(tab, forKey: "settings.tab") }
        #if os(macOS)
        showWindow()
        #endif
        settingsOpener?()
    }
    private(set) var server: BlinkServer?
    private(set) var email: String?
    private(set) var status: Status = .checking
    private(set) var lastSync: Date? = {
        let saved = UserDefaults.standard.object(forKey: "lastSync") as? Date
        // Installs from before onboarding existed have synced already: don't walk them through it.
        if saved != nil, UserDefaults.standard.object(forKey: "onboarding.done") == nil {
            for key in ["onboarding.done", "onboarding.welcomed", "onboarding.calendarSeen"] { UserDefaults.standard.set(true, forKey: key) }
        }
        return saved
    }()
    /// Shown above the sign-in form, e.g. after the server ended the session.
    private(set) var signInNotice: String?

    private(set) var refreshing = false
    /// Goes up at every sign-out, so a sync that started for the previous account can tell its results are stale.
    private var session = 0
    /// A stale sync finished while the current one ran: run once more when it's done.
    private var resyncAfter = false

    /// Ask-First cards waiting for the user (§6).
    private(set) var pending: [BlinkAction] = []
    private(set) var actionProblem: String?
    /// Decided actions, newest first (Activity).
    private(set) var activity: [BlinkAction] = []

    /// Notes and tasks. Edits apply here at once; `unsaved` holds ids whose latest edit hasn't reached the server.
    private(set) var items: [BlinkItem] = []
    private var unsaved: Set<String> = []
    private var onServer: Set<String> = []
    private(set) var saveProblem: String?
    /// A note to open when the Notes screen appears (from Today's Note button).
    var focusNoteID: String?
    /// The note open on the Notes page, so the Blink panel can offer help with it.
    var openNoteID: String?

    private(set) var habits: [Habit] = []
    /// habit id → habit day ("yyyy-MM-dd") → answer.
    private(set) var habitAnswers: [String: [String: HabitAnswer]] = [:]
    private(set) var wake = (hour: 7, minute: 0)
    private(set) var evening = (hour: 21, minute: 30)
    private(set) var lastEvening: Date? = UserDefaults.standard.object(forKey: "lastEvening") as? Date
    /// Bumped when the owner finishes the evening check-in; the notch goes Sleepy.
    private(set) var eveningsDone = 0
    /// Bumped when an answer reaches a 7 / 30 / 100-day streak; the notch celebrates.
    private(set) var celebrations = 0

    /// The chat with Blink. shortcut: the last 20 turns are kept in plain form in the app's container on this Mac (FileVault
    /// protects it at rest); encrypt with a Keychain key, or sync it, when Chat history (§36.2) or the iPhone app needs it.
    private(set) var chat: [BlinkServer.ChatTurn] = AppModel.savedChat() {
        didSet { Self.saveChat(chat) }
    }

    /// The last 20 turns stay on this Mac across restarts (never sent anywhere but the chat function).
    private static func savedChat() -> [BlinkServer.ChatTurn] {
        UserDefaults.standard.data(forKey: "chat").flatMap { try? JSONDecoder().decode([BlinkServer.ChatTurn].self, from: $0) } ?? []
    }

    private static func saveChat(_ chat: [BlinkServer.ChatTurn]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(chat.suffix(20))), forKey: "chat")
    }
    private(set) var thinking = false
    /// The answer so far while it streams in; it joins `chat` once finished (so history isn't saved on every word).
    private(set) var streaming: String?

    /// The running Pomodoro phase or timer; kept on disk so it survives a restart.
    private(set) var timer: FocusTimer? = AppModel.savedTimer() {
        didSet { saveTimer() }
    }
    /// A phase that just ended, waiting for "Start break" / "Skip".
    private(set) var finishedTimer: FocusTimer?
    /// Bumped when a timer ends; the notch opens.
    private(set) var timersEnded = 0
    private var timerWatch: Task<Void, Never>?

    /// Today and the next days, minus meetings the owner marked done (those stay in the calendar and on the server).
    private(set) var agenda = Agenda.empty
    /// Every event as the calendar has it; `agenda` shows these minus `doneMeetings`.
    private(set) var calendarEvents: [AgendaEvent] = []
    /// Meetings marked done in the notch (event ids, which include the start time), on this Mac only.
    private(set) var doneMeetings = Set(UserDefaults.standard.stringArray(forKey: "meetings.done") ?? [])
    private(set) var calendarAccess = CalendarReader.access
    private let calendarReader = CalendarReader()
    private var watchingCalendar = false
    private var reloading = false
    private var reloadAgain = false

    private(set) var locked = true
    private var awaySince: Date?
    /// The unlock prompt opens by itself once per lock; the prompt itself makes the scene inactive and active again.
    private var promptPending = true

    private let keychain = Keychain(service: Bundle.main.bundleIdentifier ?? "blink")

    // MARK: Server and account

    func load() async {
        guard screen == .loading else { return }
        #if DEBUG
        // Testing the first run: open Blink with `--args -BlinkRestartSetup`.
        if ProcessInfo.processInfo.arguments.contains("-BlinkRestartSetup") {
            await BlinkServer.forget(keychain: keychain)
            for key in ["onboarding.welcomed", "onboarding.calendarSeen", "tour.v1.done"] { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.set(false, forKey: "onboarding.done")
        }
        #endif
        if let saved = await BlinkServer.restore(keychain: keychain) {
            server = saved.server
            email = saved.email
            screen = email == nil ? .signIn : .home
        } else {
            screen = .connect
        }
        if calendarAccess == .granted { await startCalendar() }
        watchTimer() // a timer that ran while Blink was closed ends now or keeps going
    }

    func connect(url: String, key: String) async throws(ServerConfig.Problem) {
        let config = try ServerConfig.validate(url: url, key: key)
        // shortcut: a failed Keychain write only means the next launch asks for the server again; handle it when QR pairing (§36.5) replaces this screen.
        try? await BlinkServer.save(config, keychain: keychain)
        server = BlinkServer(config: config, keychain: keychain)
        signInNotice = nil
        screen = .signIn
    }

    /// Sign out, forget the server on this device and show the first-run setup again. Nothing on the server changes.
    func restartSetup() async {
        await signOut()
        await useDifferentServer()
        for key in ["onboarding.done", "onboarding.welcomed", "onboarding.calendarSeen", "tour.v1.done"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(false, forKey: "onboarding.done") // so the "already synced" migration doesn't skip it
    }

    func useDifferentServer() async {
        await BlinkServer.forget(keychain: keychain)
        server = nil
        screen = .connect
    }

    /// Shown on the Sign in screen (e.g. when one-click setup finished but its sign-in didn't).
    func noteSignIn(_ message: String) { signInNotice = message }

    /// Returns a sentence to show when sign-in fails.
    func signIn(email: String, password: String) async -> String? {
        guard let server else { return nil }
        do {
            self.email = try await server.signIn(email: email, password: password)
            signInNotice = nil
            signedOutOnPurpose = false
            // The saved login works here: note which server it's for, so it can sign in by itself next time.
            if let saved = savedLogin, saved.email == email, saved.password == password, savedLoginHost == nil {
                try? saveLogin(email: email, password: password, host: server.config.host)
            }
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
        let mine = session
        refreshing = true
        defer {
            if session == mine { refreshing = false }
        }
        status = .checking
        do {
            let at = try await server.checkIn(platform: Self.platform, deviceName: Self.deviceName,
                                              timeZone: TimeZone.current.identifier)
            lastSync = at
            UserDefaults.standard.set(at, forKey: "lastSync")
            status = .connected
            pausedProject = nil
            // Creating the key shows no prompt; only signing a red approval asks for Touch ID.
            try? await server.enrollApprovalKeyIfNeeded()
            await reloadAgenda()
            await loadActions()
            await loadItems()
            await loadSpaces()
            await loadModelPrefs()
            await loadContent() // the brief and Today show posts ready
            await loadMail()
            await loadMoney()
            await loadHabits()
            await checkServerPackage()
            // Once per launch, and again on each sync while no key works (one free, read-only ping per provider).
            if keyStatus == nil || aiKeyMissing { await loadKeyStatus() }
        } catch {
            // A paused free server still answers (HTTP 540), so it fails as "other" or even "signed out": ask first.
            pausedProject = await server.pausedProject()
            switch ServerProblem(error) {
            case .signedOut where pausedProject == nil:
                // Only for the account this sync was for; a newer sign-in isn't affected.
                if session == mine { await endSession(notice: "You've been signed out. Sign in again to continue.") }
            case .signedOut, .unreachable:
                status = .unreachable
            case .wrongLogin, .other:
                // shortcut: anything else is shown as unreachable; split out when sync adds real failure modes.
                status = .unreachable
            }
        }
        // Signed out (and maybe into another account) while this ran: drop what it loaded and sync the current one.
        // Only server-loaded lists go; anything typed since (notes, drafts, chat) stays.
        if session != mine {
            if email == nil {
                clearAccountData()
            } else {
                clearLoadedData()
                // The new account's own sync may be running and have loaded some lists before this one wrote over
                // them: sync again once it's done.
                if refreshing { resyncAfter = true } else { Task { await refresh() } }
            }
        } else if resyncAfter {
            resyncAfter = false
            Task { await refresh() } // runs after this one has finished (refreshing is false by then)
        }
    }

    func signOut() async {
        signedOutOnPurpose = true
        await endSession(notice: nil)
    }

    private func endSession(notice: String?) async {
        await server?.signOut()
        email = nil
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: "lastSync")
        // Nothing of this account stays behind for the next one to see, or to be saved into it.
        mailWatch?.cancel(); mailWatch = nil
        sendCountdown?.cancel(); sendCountdown = nil
        clearAccountData()
        // A sync still in flight sees the new session when it ends and throws its results away (see refresh).
        session += 1
        refreshing = false
        resyncAfter = false
        signInNotice = notice
        screen = .signIn
    }

    /// Everything of this account: what came from the server and what was typed here.
    private func clearAccountData() {
        clearLoadedData()
        unsaved = []; focusNoteID = nil; openNoteID = nil; contentUnsaved = []; reviewing = nil
        chat = []; UserDefaults.standard.removeObject(forKey: "chat")
    }

    /// Only what syncs load from the server (lists, statuses), never unsaved typing.
    private func clearLoadedData() {
        pending = []; activity = []; actionProblem = nil; undoChip = nil
        items = []; onServer = []; saveProblem = nil
        habits = []; habitAnswers = [:]
        agenda = .empty; calendarEvents = []; allReminders = []; quickReplies = []
        content = []; voice = VoiceProfile(); contentProblem = nil
        ideas = []; questions = [:]; pageRead = nil; designed = []
        spends = []; budgets = []; accounts = []; captureTokens = []; moneyProblem = nil; pagePosts = []; socialAccounts = []
        emails = []; mailStates = []; mailProblem = nil; outbox = []; sendingNow = nil
        modelPrefs = [:]; modelProblem = nil; dailyCap = nil; spaces = []; openPage = nil; keyStatus = nil
    }

    // MARK: Ask-First

    /// shortcut: fetched on check-in and when the notch opens; subscribe with Realtime when the server proposes actions on its own (scheduled jobs, autoposting).
    func loadActions() async {
        guard let server, email != nil, let actions = try? await server.pendingActions() else { return }
        pending = actions
    }

    func loadActivity() async {
        guard let server, email != nil, let recent = try? await server.recentActivity() else { return }
        activity = recent
    }

    /// Actions being approved right now: a quick double ⌘⏎ must not run one twice.
    private var approving: Set<String> = []

    func approve(_ action: BlinkAction) async {
        guard let server, approving.insert(action.id).inserted else { return }
        defer { approving.remove(action.id) }
        actionProblem = nil
        do {
            switch action.risk {
            case .red where action.kind == "meet.create":
                // Approved only on the /meet card, which shows the exact time and guests (like mail below).
                try await server.setStatus("declined", for: action)
                actionProblem = "Meetings are set up with /meet, where you can see the time and everyone invited."
            case .red where action.kind == "mail.send":
                // Mail is sent only from the review sheet, which shows the exact recipient and text. A card shows only its
                // title, which whoever inserted it chose, so it is never approved from here.
                try await server.setStatus("declined", for: action)
                actionProblem = "Mail is sent from the Inbox, where you can see the whole message."
            case .red:
                // shortcut: approval only; the post executor lands with autoposting.
                try await server.approveRed(action)
            case .green, .amber:
                try await server.setStatus("approved", for: action)
                try await execute(action, server: server)
            }
            pending.removeAll { $0.id == action.id }
            await loadActivity()
        } catch let problem as ApprovalKey.Problem {
            // Cancel keeps the card quietly (§36.5); anything else says what's wrong.
            if problem != .cancelled { actionProblem = problem.message }
        } catch {
            actionProblem = "That didn't work. Check your connection and try again."
        }
    }

    func dismiss(_ action: BlinkAction) async {
        guard let server else { return }
        do {
            try await server.setStatus("declined", for: action)
            pending.removeAll { $0.id == action.id }
            await loadActivity()
        } catch {
            actionProblem = "Couldn't dismiss. Check your connection and try again."
        }
    }

    /// Actions this device can carry out after approval. Unknown kinds stay approved for whoever handles them.
    private func execute(_ action: BlinkAction, server: BlinkServer) async throws {
        switch action.kind {
        case "task.complete", "task.delete":
            guard let id = action.payload.targetID, let task = items.first(where: { $0.id == id }) else {
                try await server.setStatus("failed", for: action, result: ["error": "That task is gone."])
                return
            }
            if action.kind == "task.delete" { await delete(task) } else if task.status != .done { await toggle(task) }
            try await server.setStatus("done", for: action, result: ["item_id": id])
        case "task.reschedule":
            guard let id = action.payload.targetID, var task = items.first(where: { $0.id == id }) else {
                try await server.setStatus("failed", for: action, result: ["error": "That task is gone."])
                return
            }
            task.dueAt = action.payload.due
            edit(task)
            await save(id)
            try await server.setStatus("done", for: action, result: ["item_id": id])
        case "reminder.reschedule":
            guard let id = action.payload.targetID else {
                try await server.setStatus("failed", for: action, result: ["error": "That reminder is gone."])
                return
            }
            try await calendarReader.setReminderDue(id: id, due: action.payload.due)
            try await server.setStatus("done", for: action, result: ["reminder_id": id])
            await reloadAgenda()
        case "reminder.complete", "reminder.delete":
            guard let id = action.payload.targetID else {
                try await server.setStatus("failed", for: action, result: ["error": "That reminder is gone."])
                return
            }
            do {
                if action.kind == "reminder.delete" {
                    try await calendarReader.deleteReminder(id: id)
                } else {
                    try await calendarReader.updateReminder(id: id, completed: true)
                }
                try await server.setStatus("done", for: action, result: ["reminder_id": id])
                await reloadAgenda()
            } catch {
                try? await server.setStatus("failed", for: action, result: ["error": error.localizedDescription])
                throw error
            }
        case "task.add":
            let task = create(.task, title: action.payload.reminder ?? action.title, due: action.payload.due,
                              space: Space.known(action.payload.spaceID, in: spaces))
            try await server.setStatus("done", for: action, result: ["item_id": task.id])
        case "reminder.add":
            do {
                let id = try await calendarReader.addReminder(action.payload.reminder ?? action.title, due: action.payload.due)
                try await server.setStatus("done", for: action, result: ["reminder_id": id])
            } catch {
                // Approved but not done: say so in the log rather than leave it looking approved.
                try? await server.setStatus("failed", for: action, result: ["error": error.localizedDescription])
                throw error
            }
        case "post.draft":
            // From chat: the idea and the platforms the owner named; the drafts land in Content (and the Space's canvas).
            let platforms = (action.payload.platforms ?? []).compactMap(ContentPiece.Platform.init(rawValue:))
            guard let idea = action.payload.note, !platforms.isEmpty else {
                try await server.setStatus("failed", for: action, result: ["error": "The post had no idea or platform."])
                return
            }
            while drafting { try await Task.sleep(for: .milliseconds(300)) } // another post is being written; wait for it
            if await draft(idea: idea, platforms: platforms, plannedFor: action.payload.postOn,
                           space: Space.known(action.payload.spaceID, in: spaces)) {
                try await server.setStatus("done", for: action, result: [:])
            } else {
                let problem = contentProblem ?? "Couldn't write the drafts."
                actionProblem = problem
                try? await server.setStatus("failed", for: action, result: ["error": problem])
            }
        case "mail.compose":
            // From chat ("send the reply to Sam on the 15th"): write or reuse the draft, then show it for review.
            if !emails.contains(where: { $0.id == action.payload.emailID }) { await loadMail() }
            guard let message = emails.first(where: { $0.id == action.payload.emailID }) else {
                try await server.setStatus("failed", for: action, result: ["error": "That email isn't in Blink anymore."])
                return
            }
            try await server.setStatus("done", for: action, result: ["email_id": message.id])
            await reviewReply(to: message, note: action.payload.note ?? "", sendAt: action.payload.sendAt)
        default:
            break
        }
    }

    // MARK: Notes and tasks
    // shortcut: online only, no local cache; add SwiftData + delta sync by rev (§17, §36.1) when offline capture or the iPhone app needs it.

    var notes: [BlinkItem] { items.filter { $0.type == .note }.sorted { $0.updatedAt > $1.updatedAt } }

    /// One search result: what it is, and where it opens in the window (a page key as in `openPage`, maybe a note).
    struct SearchHit: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let pageKey: String
        var noteID: String?
    }

    /// Notes, tasks, reminders, posts and spaces matching the words, for ⌘K in the window and ⌃⌥K in the notch.
    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        func has(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(q) }
        var list: [SearchHit] = []
        list += spaces.filter { has($0.title) || has($0.goal) }
            .map { SearchHit(id: "s" + $0.id, symbol: $0.icon, title: $0.title, detail: "Space", pageKey: "space:\($0.id)") }
        list += notes.filter { has($0.title) || has($0.body) }
            .map { SearchHit(id: "n" + $0.id, symbol: "note.text", title: $0.title.isEmpty ? "New note" : $0.title,
                             detail: "Note · " + $0.body.prefix(80).replacingOccurrences(of: "\n", with: " "), pageKey: "notes", noteID: $0.id) }
        list += items.filter { $0.type == .task && $0.status != .archived && has($0.title) }
            .map { SearchHit(id: "t" + $0.id, symbol: $0.status == .done ? "checkmark.circle.fill" : "circle", title: $0.title,
                             detail: $0.status == .done ? "Task · done" : "Task", pageKey: $0.spaceID.map { "space:\($0)" } ?? "tasks") }
        list += allReminders.filter { has($0.title) }
            .map { SearchHit(id: "r" + $0.id, symbol: "bell", title: $0.title, detail: "Apple Reminder", pageKey: "tasks") }
        list += content.filter { has($0.body) || has($0.idea) || $0.parts.contains(where: has) }
            .map { SearchHit(id: "c" + $0.id, symbol: "megaphone", title: $0.hook.isEmpty ? $0.idea : $0.hook,
                             detail: "\($0.platform.name) post · \($0.status.rawValue)", pageKey: "content") }
        return Array(list.prefix(40))
    }
    var openTasks: [BlinkItem] { items.filter { $0.type == .task && $0.status == .open } }
    /// Open tasks with a due time, for the notch's cues and status line.
    var dueTasks: [DueItem] { openTasks.compactMap { t in t.dueAt.map { DueItem(id: t.id, title: t.title, due: $0) } } }
    var doneTasks: [BlinkItem] { items.filter { $0.type == .task && $0.status == .done } }

    func loadItems() async {
        guard let server, email != nil else { return }
        for id in unsaved { await save(id) } // retry anything a failed save left behind
        // Anything unsaved when the fetch started keeps its local copy: a save landing mid-fetch is newer than `fresh`.
        let wasUnsaved = unsaved
        guard let fresh = try? await server.items() else { return }
        onServer = Set(fresh.map(\.id))
        items = BlinkItem.merge(server: fresh, local: items, unsaved: wasUnsaved.union(unsaved))
    }

    @discardableResult
    func create(_ type: BlinkItem.Kind, title: String, body: String = "", due: Date? = nil, space: String? = nil) -> BlinkItem {
        let item = BlinkItem(id: UUID().uuidString.lowercased(), type: type, title: title, body: body, dueAt: due, spaceID: space)
        items.insert(item, at: 0)
        unsaved.insert(item.id)
        Task { await save(item.id) }
        return item
    }

    /// Applies an edit locally; call `save` to send it (the note editor waits for a pause in typing).
    func edit(_ item: BlinkItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var changed = item
        changed.updatedAt = .now
        items[index] = changed
        unsaved.insert(item.id)
    }

    func save(_ id: String) async {
        guard let server, let item = items.first(where: { $0.id == id }) else { return }
        do {
            if onServer.contains(id) {
                try await server.save(item)
            } else {
                try await server.save(new: item)
                // Deleted while the first save was on its way (a blank note left at once): don't let it come back.
                guard items.contains(where: { $0.id == id }) else { try? await server.delete(item); return }
                onServer.insert(id)
            }
            // Only clear if nothing was typed while saving.
            if items.first(where: { $0.id == id }) == item { unsaved.remove(id) }
            if unsaved.isEmpty { saveProblem = nil }
        } catch is BlinkServer.RowGone {
            onServer.remove(id)
            await save(id) // once more, as new: the edits are kept
        } catch {
            saveProblem = "Not saved yet. Blink will try again on your next change."
        }
    }

    /// Several at once from Select mode: tasks by id, reminders by id. One Undo brings them all back.
    func completeAll(tasks: [BlinkItem], reminders: [AgendaReminder]) async {
        let open = tasks.filter { $0.status != .done }
        for task in open { await toggle(task, offeringUndo: false) }
        for reminder in reminders {
            agenda.reminders.removeAll { $0.id == reminder.id }
            allReminders.removeAll { $0.id == reminder.id }
            await writeReminder(reload: false) { try await calendarReader.updateReminder(id: reminder.id, completed: true) }
        }
        if !reminders.isEmpty { await reloadAgenda() } // once, not per reminder
        let count = open.count + reminders.count
        guard count > 0 else { return }
        offerUndo(count == 1 ? "Done: \((open.first?.title ?? reminders.first?.title) ?? "")" : "\(count) done") { [weak self] in
            for task in open { await self?.reopen(task.id) }
            for reminder in reminders { await self?.reopen(reminder) }
        }
    }

    // MARK: Undo (Done ∩∩ + Undo chip, tokens hold.undoChip)

    struct UndoChip: Identifiable {
        let id = UUID()
        let text: String
        var count = 1
        let undo: @MainActor () async -> Void
    }

    /// The last thing marked done, undoable for a few seconds in the window and the notch.
    private(set) var undoChip: UndoChip?

    func offerUndo(_ text: String, undo: @escaping @MainActor () async -> Void) {
        // Several things done at once (one answer, quick commands in a row): one chip undoes them all.
        let chip = if let earlier = undoChip {
            UndoChip(text: "\(earlier.count + 1) changes", count: earlier.count + 1) { await undo(); await earlier.undo() } // newest first
        } else {
            UndoChip(text: text, undo: undo)
        }
        undoChip = chip
        Task {
            try? await Task.sleep(for: .seconds(Tokens.Hold.undoChip))
            if undoChip?.id == chip.id { undoChip = nil }
        }
    }

    /// True while an Undo is still being carried out (the chip is already gone).
    private(set) var undoing = false

    func undo() async {
        guard let chip = undoChip else { return }
        undoChip = nil
        undoing = true
        defer { undoing = false }
        await chip.undo()
    }

    /// Ticks off a task or reminder from the notch or the timeline by id.
    func complete(id: String) async {
        if let task = openTasks.first(where: { $0.id == id }) {
            await toggle(task)
        } else if let reminder = allReminders.first(where: { $0.id == id }) ?? agenda.reminders.first(where: { $0.id == id }) {
            await complete(reminder)
        }
    }

    /// Later: a new due time for a task or reminder by id (from the notch), with Undo.
    func moveLater(id: String, to date: Date) async {
        let label = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        if let task = openTasks.first(where: { $0.id == id }) {
            let before = task.dueAt
            var changed = task
            changed.dueAt = date
            edit(changed)
            await save(id)
            offerUndo("Moved to \(label): \(task.title)") { [weak self] in
                guard let self, var current = self.items.first(where: { $0.id == id }) else { return }
                current.dueAt = before
                self.edit(current)
                await self.save(id)
            }
        } else if let reminder = allReminders.first(where: { $0.id == id }) ?? agenda.reminders.first(where: { $0.id == id }) {
            await setDue(reminder, to: date)
            offerUndo("Moved to \(label): \(reminder.title)") { [weak self] in await self?.setDue(reminder, to: reminder.due) }
        }
    }

    private func reopen(_ taskID: String) async {
        guard let task = items.first(where: { $0.id == taskID }), task.status == .done else { return }
        await toggle(task, offeringUndo: false)
    }

    private func reopen(_ reminder: AgendaReminder) async {
        await writeReminder { try await calendarReader.updateReminder(id: reminder.id, completed: false) }
    }

    func deleteAll(tasks: [BlinkItem], reminders: [AgendaReminder]) async {
        for task in tasks { await delete(task) }
        for reminder in reminders {
            agenda.reminders.removeAll { $0.id == reminder.id }
            allReminders.removeAll { $0.id == reminder.id }
            await writeReminder(reload: false) { try await calendarReader.deleteReminder(id: reminder.id) }
        }
        if !reminders.isEmpty { await reloadAgenda() }
    }

    func saveIfNeeded(_ id: String) async {
        if unsaved.contains(id) { await save(id) }
    }

    /// A small, quiet "pop" when something's done (Settings › General can turn it off).
    static let finishSoundKey = "sound.finish"

    private func playFinishSound() {
        #if os(macOS)
        guard UserDefaults.standard.object(forKey: Self.finishSoundKey) as? Bool ?? true else { return }
        NSSound(named: "Pop")?.play()
        #endif
    }

    func toggle(_ task: BlinkItem, offeringUndo: Bool = true) async {
        var changed = task
        changed.status = task.status == .done ? .open : .done
        edit(changed)
        if changed.status == .done { playFinishSound() }
        if offeringUndo && changed.status == .done {
            offerUndo("Done: \(task.title)") { [weak self] in await self?.reopen(task.id) }
        }
        await save(task.id)
    }

    /// Deleting by hand (a task or note's Delete): gone at once, with Undo to bring it back as it was.
    func deleteWithUndo(_ item: BlinkItem) async {
        await delete(item)
        guard !items.contains(where: { $0.id == item.id }) else { return } // the delete failed; nothing to undo
        offerUndo("Deleted: \(item.title.isEmpty ? (item.type == .note ? "note" : "task") : item.title)") { [weak self] in
            guard let self, let server else { return }
            do {
                try await server.restore(item)
                items.insert(item, at: 0)
                onServer.insert(item.id)
            } catch {
                saveProblem = "Couldn't bring it back. Check your connection."
            }
        }
    }

    func delete(_ item: BlinkItem) async {
        guard let server, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        guard onServer.contains(item.id) else { unsaved.remove(item.id); return }
        do {
            try await server.delete(item)
            onServer.remove(item.id)
        } catch {
            items.insert(item, at: min(index, items.count)) // put it back rather than lose it silently
            saveProblem = "Couldn't delete. Check your connection and try again."
        }
    }

    // MARK: Habits (§36.2)

    /// Today's habit day: it ends at your wake time.
    var habitToday: Date { HabitDay.day(for: .now, wakeHour: wake.hour, wakeMinute: wake.minute) }

    func isScheduledToday(_ habit: Habit) -> Bool {
        habit.weekdays.contains(Calendar.current.component(.weekday, from: habitToday))
    }

    func answerToday(_ habit: Habit) -> HabitAnswer? { habitAnswers[habit.id]?[HabitDay.key(habitToday)] }

    func progress(_ habit: Habit) -> HabitProgress {
        habit.progress(answers: habitAnswers[habit.id] ?? [:], today: habitToday)
    }

    /// Wake time ends the habit day; evening time opens the check-in. Kept on the server's profile.
    func setDayTimes(wake: (hour: Int, minute: Int), evening: (hour: Int, minute: Int)) async {
        guard let server else { return }
        let before = (self.wake, self.evening)
        self.wake = wake
        self.evening = evening
        do {
            try await server.setDayTimes(wake: wake, evening: evening)
        } catch {
            (self.wake, self.evening) = before
            saveProblem = "Couldn't save your times. Check your connection and try again."
        }
    }

    func loadHabits() async {
        guard let server, email != nil else { return }
        if let times = try? await server.dayTimes() {
            wake = times.wake
            evening = times.evening
        }
        guard let list = try? await server.habits(),
              let logs = try? await server.habitLogs(since: HabitDay.answersSince(list, today: habitToday)) else { return }
        habits = list
        habitAnswers = Dictionary(grouping: logs, by: \.habitID).mapValues { Dictionary($0.map { ($0.day, $0.status) }) { $1 } }
    }

    func addHabit(_ name: String, weekdays: [Int] = Array(1...7)) async {
        let habit = Habit(id: UUID().uuidString.lowercased(), name: name, weekdays: weekdays)
        habits.append(habit)
        do { try await server?.save(new: habit) } catch {
            habits.removeAll { $0.id == habit.id }
            saveProblem = "Couldn't add that habit. Check your connection and try again."
        }
    }

    func setWeekdays(_ habit: Habit, to weekdays: [Int]) async {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].weekdays = weekdays
        do { try await server?.save(habits[index]) } catch {
            habits[index].weekdays = habit.weekdays
            saveProblem = "Couldn't change that habit. Check your connection and try again."
        }
    }

    func archive(_ habit: Habit) async {
        habits.removeAll { $0.id == habit.id }
        do { try await server?.archive(habit) } catch {
            habits.append(habit)
            saveProblem = "Couldn't remove that habit. Check your connection and try again."
        }
    }

    /// Done / Not today / Skip for today, or nil to clear (answering again undoes it).
    func answer(_ habit: Habit, _ answer: HabitAnswer?) async {
        guard let server else { return }
        let day = HabitDay.key(habitToday)
        let before = habitAnswers[habit.id]?[day]
        habitAnswers[habit.id, default: [:]][day] = answer
        if answer == .done { playFinishSound() }
        do {
            if let answer { try await server.answer(habit, day: day, with: answer) }
            else { try await server.clearAnswer(habit, day: day) }
            if answer == .done && progress(habit).isMilestone { celebrations += 1 }
        } catch {
            habitAnswers[habit.id, default: [:]][day] = before
            saveProblem = "Couldn't save that. Check your connection and try again."
        }
    }

    // MARK: Pomodoro and timers

    func startFocus() { begin(.focus()) }
    func startTimer(minutes: Double) { begin(.timer(minutes: minutes)) }

    func pauseTimer() {
        timer?.pause(now: .now)
        timerWatch?.cancel()
    }

    func resumeTimer() {
        timer?.resume(now: .now)
        watchTimer()
    }

    func addToTimer(minutes: Double) {
        timer?.add(minutes: minutes)
        watchTimer()
    }

    func stopTimer() {
        timerWatch?.cancel()
        timer = nil
        finishedTimer = nil
    }

    /// After a phase ends: start what follows (break after focus, focus after a break).
    func startNextPhase() {
        guard let done = finishedTimer, let next = done.next(now: .now) else { finishedTimer = nil; return }
        begin(next)
    }

    func dismissFinishedTimer() { finishedTimer = nil }

    private func begin(_ new: FocusTimer) {
        finishedTimer = nil
        timer = new
        watchTimer()
    }

    /// Sleeps until the timer's end instead of ticking, so nothing runs in between (idle CPU stays ~0).
    func watchTimer() {
        timerWatch?.cancel()
        guard let timer, !timer.isPaused else { return }
        let left = timer.remaining(now: .now)
        timerWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled, let self, let current = self.timer, current.isFinished(now: .now) else { return }
            self.finishedTimer = current
            self.timer = nil
            self.timersEnded += 1
            #if os(macOS)
            NSSound(named: "Glass")?.play() // the alarm: one system chime, never a loop
            #endif
        }
    }

    private static func savedTimer() -> FocusTimer? {
        UserDefaults.standard.data(forKey: "focusTimer").flatMap { try? JSONDecoder().decode(FocusTimer.self, from: $0) }
    }

    private func saveTimer() {
        if let timer, let data = try? JSONEncoder().encode(timer) {
            UserDefaults.standard.set(data, forKey: "focusTimer")
        } else {
            UserDefaults.standard.removeObject(forKey: "focusTimer")
        }
    }

    // MARK: Evening check-in (§9.4)

    var eveningDue: Bool { EveningCheck.isDue(now: .now, evening: evening, wake: wake, lastDone: lastEvening) }
    var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: habitToday) ?? habitToday }

    /// Open tasks due by the end of today, for the morning brief.
    var tasksDueToday: Int { unfinishedToday.tasks.count }

    /// Tasks and reminders due by the end of today and not done: what "Move to tomorrow" moves.
    var unfinishedToday: (tasks: [BlinkItem], reminders: [AgendaReminder]) {
        // The owner's day, not the calendar's: at 00:30 the evening is still "today".
        let endOfToday = tomorrow
        return (openTasks.filter { ($0.dueAt ?? .distantFuture) < endOfToday },
                allReminders.filter { ($0.due ?? .distantFuture) < endOfToday })
    }

    /// The evening's one click: everything unfinished today moves to tomorrow (same time, or 9:00), with Undo.
    func moveUnfinishedToTomorrow() async {
        let (tasks, reminders) = unfinishedToday
        guard !tasks.isEmpty || !reminders.isEmpty else { return }
        for task in tasks {
            var moved = task
            let time = task.dueAt.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
            // shortcut: a task due at exactly 00:00 counts as day-only, until BlinkItem stores a timed flag.
            moved.dueAt = EveningCheck.movedToTomorrow(task.dueAt, timed: (time?.hour ?? 0, time?.minute ?? 0) != (0, 0), now: habitToday)
            edit(moved)
            await save(moved.id)
        }
        for reminder in reminders {
            await setDue(reminder, to: EveningCheck.movedToTomorrow(reminder.due, timed: reminder.timed, now: habitToday), reload: false)
        }
        if !reminders.isEmpty { await reloadAgenda() } // once, not per reminder
        let count = tasks.count + reminders.count
        offerUndo(count == 1 ? "Moved to tomorrow" : "\(count) moved to tomorrow") { [weak self] in
            guard let self else { return }
            // Only the due date goes back: a task finished or renamed since keeps that change.
            for task in tasks {
                guard var current = items.first(where: { $0.id == task.id }) else { continue }
                current.dueAt = task.dueAt
                edit(current)
                await save(task.id)
            }
            for reminder in reminders { await setDue(reminder, to: reminder.due, reload: false) }
            if !reminders.isEmpty { await reloadAgenda() }
        }
    }

    func finishEvening() {
        lastEvening = .now
        UserDefaults.standard.set(lastEvening, forKey: "lastEvening")
        eveningsDone += 1
    }

    /// Quick replies shown under Blink's question during the evening check-in.
    private(set) var quickReplies: [String] = []

    /// "Plan with Blink": a short conversation first. Blink asks before it proposes anything (owner feedback).
    func planTomorrow() async {
        let day = tomorrow.formatted(.dateTime.weekday(.wide).day().month())
        quickReplies = []
        await ask("""
            Evening check-in for \(day). Before proposing anything, ask me one short question: is there anything to add \
            for tomorrow, or should I keep my usual day? Mention in a few words what tomorrow already holds. \
            Propose nothing until I answer.
            """)
        // The on-device model adds things one at a time; it doesn't plan a whole day, so it doesn't offer to.
        quickReplies = model(for: "chat").id == AIModel.onDeviceID
            ? ["Nothing else, I'm set"] : ["Keep my usual day", "Add something", "Nothing else, I'm set"]
    }

    /// A quick reply: "Nothing else" ends the check-in; the others continue the conversation.
    func quickReply(_ text: String) async {
        quickReplies = []
        if text.hasPrefix("Nothing else") {
            finishEvening()
            return
        }
        if text == "Add something" {
            chat.append(.init(role: .assistant, text: "What should I add? Type it below, e.g. \"gym at 7, call Sam after lunch\"."))
            return
        }
        await ask(text == "Keep my usual day"
                  ? "Keep my usual day: plan tomorrow around my calendar and habits, fit my open tasks in with realistic times, and propose them."
                  : text)
    }

    // MARK: Chat

    /// `context` is what's on screen (an open note, a Space); the server hands it to Claude as data, never as instructions.
    /// The Space the owner is asking from, while a question runs (the on-device model's add_task puts tasks there).
    private(set) var askingSpace: String?

    /// `space`: the Space on screen; the server reads its tasks and notes, and tasks proposed from it go into it.
    func ask(_ text: String, context: String? = nil, space: String? = nil) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !thinking else { return }
        let onDevice = model(for: "chat").id == AIModel.onDeviceID
        guard onDevice || server != nil else { return }
        quickReplies = []
        let history = chat
        chat.append(.init(role: .user, text: message))
        thinking = true
        askingSpace = space
        defer { thinking = false; streaming = nil; askingSpace = nil }
        if onDevice {
            let reply = await OnDeviceChat.answer(message, history: history, context: context, about: self) { self.streaming = $0 }
            chat.append(.init(role: .assistant, text: reply))
            return
        }
        guard let server else { return }
        do {
            // Open reminders go along so Claude can propose finishing or deleting one (they stay on the Mac otherwise).
            let reminders = calendarAccess == .granted ? await calendarReader.openReminders() : []
            var final: String?
            streaming = ""
            for try await event in server.chatStream(message, history: history, timeZone: TimeZone.current.identifier,
                                                     reminders: reminders, context: context, spaceID: space) {
                switch event {
                case .delta(let text): streaming = (streaming ?? "") + text
                case .reset: streaming = "" // a new turn after a tool call: the earlier words were the model thinking aloud
                case .done(let reply, let proposed):
                    final = reply
                    if proposed > 0 { await loadActions() }
                case .failed(let problem):
                    final = problem
                    await loadActions() // an earlier turn may have proposed something before it failed
                }
            }
            if let final {
                chat.append(.init(role: .assistant, text: final))
            } else {
                // Ended without done or error (time limit, a dropped connection): say so, and pick up any proposals.
                let partial = streaming ?? ""
                chat.append(.init(role: .assistant, text: partial.isEmpty ? "Blink couldn't answer. Try again." : partial + " (cut off)"))
                await loadActions()
            }
        } catch let problem as BlinkServer.ChatProblem {
            chat.append(.init(role: .assistant, text: problem.message))
        } catch {
            let signedOut = ServerProblem(error) == .signedOut
            chat.append(.init(role: .assistant, text: signedOut ? "You've been signed out. Sign in again to continue." : "Can't reach your server right now. Try again in a moment."))
        }
    }

    func clearChat() {
        chat = []
        quickReplies = []
    }

    /// Every open Apple Reminder (any date, at most 50), refreshed with the agenda.
    private(set) var allReminders: [AgendaReminder] = []

    // MARK: Content (§36.4): drafts per platform, the owner posts them (copy & open)

    private(set) var content: [ContentPiece] = []
    private(set) var voice = VoiceProfile()
    private(set) var drafting = false
    private(set) var contentProblem: String?
    private var contentUnsaved: Set<String> = []

    func loadContent() async {
        guard let server, email != nil else { return }
        for id in contentUnsaved { await saveContent(id) } // retry what a failed save left behind
        if let list = try? await server.contentPieces() {
            // Keep local text that hasn't reached the server yet (same data-loss guard as notes).
            content = list.map { fresh in contentUnsaved.contains(fresh.id) ? content.first { $0.id == fresh.id } ?? fresh : fresh }
            // Only when the whole list loaded (the server sends at most 200): never delete images of drafts not shown.
            if list.count < 200 {
                let pieces = content
                Task.detached(priority: .background) { PostMedia.prune(keeping: pieces) }
            }
        }
        if let saved = try? await server.voiceProfile() { voice = saved }
    }

    /// Asks Claude for one draft per platform; they arrive saved, at the top of the list.
    func draft(idea: String, platforms: [ContentPiece.Platform], plannedFor: String? = nil, space: String? = nil) async -> Bool {
        guard let server, !drafting else { return false }
        drafting = true
        defer { drafting = false }
        contentProblem = nil
        do {
            questions[idea] = try await server.draftContent(idea: idea, platforms: platforms, spaceID: space, plannedFor: plannedFor)
            await loadContent()
            if !batchingDrafts {
                announce("✍︎ Drafts ready: \(idea.split(separator: "\n").first.map(String.init)?.prefix(40) ?? "your post")")
            }
            return true
        } catch let problem as BlinkServer.ChatProblem {
            contentProblem = problem.message
        } catch {
            contentProblem = "Can't reach your server right now. Try again in a moment."
        }
        announceProblem()
        return false
    }

    /// Something that finished in the background (ideas, drafts, a week plan, a page read): the notch peeks with it,
    /// so the owner doesn't have to open the window to find out.
    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let failed: Bool
    }
    private(set) var notice: Notice?
    /// While Write All runs, one notice at the end instead of one per draft.
    private var batchingDrafts = false

    /// A short notice in the notch ("Added to Blink: …").
    func announce(_ text: String, failed: Bool = false) { notice = Notice(text: text, failed: failed) }
    private func announceProblem() { if let contentProblem { announce(contentProblem, failed: true) } }

    private(set) var ideas: [ContentIdea] = []
    /// Idea → what the model asked to know for a stronger post (shown on the idea's card until answered).
    private(set) var questions: [String: [String]] = [:]

    /// "Redraft with answers": the same idea again, with the owner's answers as facts it may use.
    func redraft(idea: String, answers: String, platforms: [ContentPiece.Platform]) async {
        let trimmed = answers.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        questions[idea] = nil
        _ = await draft(idea: "\(idea)\n\nFacts from the owner, answering your questions: \(trimmed)", platforms: platforms)
    }

    func dismissQuestions(for idea: String) { questions[idea] = nil }
    private(set) var thinkingOfIdeas = false

    func suggestIdeas(theme: String, platforms: [ContentPiece.Platform]) async {
        guard let server, !thinkingOfIdeas else { return }
        thinkingOfIdeas = true
        defer { thinkingOfIdeas = false }
        contentProblem = nil
        do {
            ideas = try await server.contentIdeas(theme: theme, platforms: platforms)
            announce("💡 \(ideas.count) post ideas ready")
            return
        }
        catch let problem as BlinkServer.ChatProblem { contentProblem = problem.message }
        catch { contentProblem = "Can't reach your server right now. Try again in a moment." }
        announceProblem()
    }

    func clearIdeas() async { ideas = [] }

    private(set) var pageRead: PageRead?
    private(set) var readingPage = false

    /// Reads the owner's Instagram page (handle from Voice) and shows what works; nothing changes until they apply it.
    func readPage() async {
        guard let server, !readingPage else { return }
        readingPage = true
        defer { readingPage = false }
        contentProblem = nil
        do {
            pageRead = try await server.readPage()
            await loadContentStats()
            announce("📊 Read \(pageRead?.read ?? 0) posts · stats in Content")
            return
        }
        catch let problem as BlinkServer.ChatProblem { contentProblem = problem.message }
        catch { contentProblem = "Can't reach your server right now. Try again in a moment." }
        announceProblem()
    }

    /// "Use as my voice": the page read's suggestion fills the Voice profile (never-say words are kept).
    func useReadAsVoice() async {
        guard let v = pageRead?.analysis?.voice else { return }
        await saveVoice(VoiceProfile(page: v.page, audience: v.audience, topics: v.topics, notes: v.tone, neverSay: voice.neverSay,
                                     brief: voice.brief))
    }

    func dismissPageRead() { pageRead = nil }

    // MARK: Post images (Cloudflare FLUX; kept on this Mac)

    private(set) var makingImage: Set<String> = []
    /// Drafts the owner asked to design (owner rule: no post design until asked). Kept on this Mac.
    private(set) var designed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "designed") ?? []) {
        didSet { UserDefaults.standard.set(Array(designed), forKey: "designed") }
    }

    func design(_ piece: ContentPiece) { designed.insert(piece.id) }
    /// Bumped when an image is saved, so views reload it from disk.
    private(set) var mediaVersion = 0

    /// One image per draft: a text-free background for a carousel, otherwise a cover.
    func makeImage(for piece: ContentPiece) async {
        guard let server, !makingImage.contains(piece.id) else { return }
        makingImage.insert(piece.id)
        defer { makingImage.remove(piece.id) }
        contentProblem = nil
        do {
            let data = try await server.makeImage(subject: piece.hook.isEmpty ? piece.idea : piece.hook, background: piece.format == "carousel")
            try PostMedia.save(data, for: piece.id)
            designed.insert(piece.id)
            mediaVersion += 1
        } catch let problem as BlinkServer.ChatProblem {
            contentProblem = problem.message
        } catch {
            contentProblem = "Couldn't make or save the image. Try again."
        }
    }

    /// The plan's ideas not written yet (kept on the server, each on its day), soonest first.
    var plannedIdeas: [ContentPiece] {
        content.filter { $0.status == .idea }.sorted { ($0.plannedFor ?? "9") < ($1.plannedFor ?? "9") }
    }

    func planWeek(theme: String, platforms: [ContentPiece.Platform]) async {
        guard let server, !thinkingOfIdeas else { return }
        thinkingOfIdeas = true
        defer { thinkingOfIdeas = false }
        contentProblem = nil
        do {
            let planned = try await server.contentIdeas(theme: theme, platforms: platforms, days: HabitDay.nextDays())
            await loadContent() // the server kept them, each on its day
            announce("📅 Week planned: \(planned.count) posts")
            return
        }
        catch let problem as BlinkServer.ChatProblem { contentProblem = problem.message }
        catch { contentProblem = "Can't reach your server right now. Try again in a moment." }
        announceProblem()
    }

    /// Removes every idea of the plan that isn't written yet (written posts stay).
    func clearPlannedIdeas() async {
        for idea in plannedIdeas { await setStatus(.archived, of: idea) }
    }

    /// Drafts for the given planned ideas, one after another.
    func writeAll(_ list: [ContentPiece]) async {
        batchingDrafts = true
        defer { batchingDrafts = false }
        var written = 0
        for idea in list {
            while drafting { try? await Task.sleep(for: .milliseconds(300)) } // a Write clicked meanwhile
            if await write(idea) { written += 1 }
        }
        if written > 0 { announce("✍︎ \(written) of \(list.count) ideas written for your plan") }
    }

    /// A planned idea becomes drafts on the same day (and Space); the idea goes once they're written.
    @discardableResult
    func write(_ idea: ContentPiece) async -> Bool {
        // The live copy: it may have been written (or removed) since the list was read.
        guard content.contains(where: { $0.id == idea.id && $0.status == .idea }) else { return false }
        guard await draft(idea: "\(idea.idea). Hook: \(idea.hook). Format: \(idea.format.replacingOccurrences(of: "_", with: " ")).",
                       platforms: [idea.platform], plannedFor: idea.plannedFor, space: idea.spaceID) else { return false }
        await setStatus(.archived, of: idea)
        return true
    }

    /// The day a post (or planned idea) goes out; nil takes it off the plan.
    func setDay(_ day: String?, of piece: ContentPiece) async {
        guard var changed = content.first(where: { $0.id == piece.id }), changed.plannedFor != day else { return }
        changed.plannedFor = day
        edit(changed)
        await saveContent(piece.id)
    }

    /// Planned for today and not out yet: the notch and Today show these.
    var postsToday: [ContentPiece] {
        let today = HabitDay.key(.now)
        return content.filter { $0.plannedFor == today && $0.status != .idea && $0.status != .published && $0.status != .archived }
    }

    /// "Write this": one idea becomes drafts for its platform.
    func write(_ idea: ContentIdea) async {
        ideas.removeAll { $0.id == idea.id }
        _ = await draft(idea: "\(idea.title). Hook: \(idea.hook). Format: \(idea.formatName).", platforms: [idea.platform],
                        plannedFor: idea.day)
    }

    /// Applies an edit at once; `saveContent` sends it (the editor waits for a pause in typing).
    func edit(_ piece: ContentPiece) {
        guard let index = content.firstIndex(where: { $0.id == piece.id }) else { return }
        content[index] = piece
        contentUnsaved.insert(piece.id)
    }

    func saveContent(_ id: String) async {
        guard let server, contentUnsaved.contains(id), var piece = content.first(where: { $0.id == id }) else { return }
        piece.lintScore = ContentLint.check(piece, neverSay: voice.neverSay).score
        do {
            try await server.save(piece)
            // Only clear if nothing was typed while saving.
            if let now = content.first(where: { $0.id == id }), now.body == piece.body, now.parts == piece.parts,
               now.status == piece.status, now.plannedFor == piece.plannedFor { contentUnsaved.remove(id) }
            contentProblem = nil
        } catch {
            contentProblem = "Not saved yet. Blink will try again on your next change."
        }
    }

    func setStatus(_ status: ContentPiece.Status, of piece: ContentPiece) async {
        var changed = content.first { $0.id == piece.id } ?? piece
        changed.status = status
        changed.publishedAt = status == .published ? .now : nil
        edit(changed)
        await saveContent(piece.id)
        // Only once the server has it: an unsaved archive stays in the list so the next load retries it.
        if status == .archived && !contentUnsaved.contains(piece.id) { content.removeAll { $0.id == piece.id } }
    }

    func saveVoice(_ new: VoiceProfile) async {
        guard let server else { return }
        let before = voice
        voice = new
        do { try await server.save(new) } catch {
            voice = before
            contentProblem = "Couldn't save your voice. Check your connection and try again."
        }
    }

    // MARK: Quick commands (typed in the notch: "/task Pay rent friday 9am")

    /// Does a typed command at once, on this device, with Undo; no AI. Returns a problem to show, or nil when it worked.
    /// `space`: a task or note typed on a Space page goes into that Space.
    @discardableResult
    func run(_ command: QuickCommand, space: String? = nil) async -> String? {
        let when: (Date?) -> String = { $0.map { " · \($0.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))" } ?? "" }
        switch command {
        case .task(let title, let due):
            let task = create(.task, title: title, due: due, space: space)
            offerUndo("Task added: \(title)\(when(due))") { [weak self] in
                guard let self, let current = self.items.first(where: { $0.id == task.id }) else { return }
                await self.delete(current)
            }
        case .remind(let title, let due):
            guard calendarAccess == .granted else {
                saveProblem = "Turn on Reminders for Blink in System Settings › Privacy & Security › Reminders."
                return saveProblem
            }
            do {
                let id = try await calendarReader.addReminder(title, due: due)
                await reloadAgenda()
                offerUndo("Reminder added: \(title)\(when(due))") { [weak self] in
                    await self?.writeReminder { try await self?.calendarReader.deleteReminder(id: id) }
                }
            } catch {
                saveProblem = "Couldn't add that reminder. Check that Reminders is allowed for Blink."
                return saveProblem
            }
        case .note(let title):
            let note = create(.note, title: title, space: space)
            offerUndo("Note started: \(title)") { [weak self] in
                guard let self, let current = self.items.first(where: { $0.id == note.id }) else { return }
                await self.delete(current)
            }
        case .timer(let minutes):
            startTimer(minutes: minutes)
        case .focus:
            startFocus()
        case .post(let idea):
            let platforms = contentPlatforms
            if await draft(idea: idea, platforms: platforms, space: space) {
                let asked = questions[idea] ?? []
                chat.append(.init(role: .assistant, text: "Wrote drafts for \(platforms.map(\.name).formatted()). Edit and approve them in **Content**."
                    + (asked.isEmpty ? "" : "\nTo make them stronger, answer on the Content page: " + asked.joined(separator: " · "))))
            } else if let problem = contentProblem {
                chat.append(.init(role: .assistant, text: problem))
            }
        case .ideas(let theme):
            await suggestIdeas(theme: theme, platforms: contentPlatforms)
            if let problem = contentProblem { chat.append(.init(role: .assistant, text: problem)) }
        case .clear:
            clearChat()
        case .meet(let title, let start, let guests):
            meetDraft = MeetDraft(title: title, start: start ?? MeetDraft.nextSlot(), guests: guests)
            Task { await loadGoogle() }
        case .spent(let text):
            // Typed on purpose in the notch: sorted and saved at once, with Undo (the Money page lets you check first).
            let drafts = await sortSpends(text)
            if !drafts.isEmpty, let saved = await addSpends(drafts) {
                let total = saved.reduce(Decimal.zero) { $0 + $1.amount }
                offerUndo("Added \(saved.count == 1 ? saved[0].note : "\(saved.count) spends") · \(total.formatted(.currency(code: MoneyMath.currency)))") { [weak self] in
                    for spend in saved { await self?.deleteSpend(spend) }
                }
            } else if let problem = moneyProblem {
                chat.append(.init(role: .assistant, text: problem))
            }
        }
        return nil
    }

    // MARK: Google Meet (/meet): an invite card in the notch, approved with Touch ID, created by the owner's server

    struct MeetDraft: Equatable {
        var title: String
        var start: Date
        var minutes = 30
        var guests: [String]

        /// The next half hour, at least 10 minutes away.
        static func nextSlot(after now: Date = .now) -> Date {
            let half = 30 * 60.0
            return Date(timeIntervalSinceReferenceDate: ((now.timeIntervalSinceReferenceDate + 10 * 60) / half).rounded(.up) * half)
        }
    }

    /// The open /meet card; nil when none.
    var meetDraft: MeetDraft?
    private(set) var googleAccount: String?
    /// Approved but not created yet (lost connection, Google hiccup): Create again retries this one, it doesn't ask twice.
    private var approvedMeet: (draft: MeetDraft, action: BlinkAction)?
    /// Touch ID or the server is working on a meeting; the notch stays open meanwhile.
    private(set) var creatingMeet = false

    func loadGoogle() async {
        guard let server, email != nil else { return }
        googleAccount = (try? await server.googleAccount()) ?? googleAccount
    }

    /// Revokes Blink's Google access and forgets it here. Returns a problem to show, or nil.
    func disconnectGoogle() async -> String? {
        guard let server else { return "Connect to your server first." }
        do {
            try await server.disconnectGoogle()
            googleAccount = nil
            return nil
        } catch { return "Couldn't disconnect. Check your connection and try again." }
    }

    #if os(macOS)
    /// One click: Google's page in the browser, the answer on 127.0.0.1, the token on the owner's server. Nil when done.
    func connectGoogleOneClick() async -> String? {
        guard let server, let client = GoogleSignIn.client else { return "Connect to your server first." }
        do {
            // Blink's client goes to the server like any key, so the server can refresh the token with it later.
            try await server.saveKey("GOOGLE_DESKTOP_CLIENT_ID", value: client.id)
            try await server.saveKey("GOOGLE_DESKTOP_CLIENT_SECRET", value: client.secret)
        } catch {
            // An older server doesn't know these key names yet.
            return "Your server needs an update before Google can connect in one click. Update it in Settings › Server."
        }
        do {
            let answer = try await GoogleSignIn.authorize(clientID: client.id)
            defer { NSApp.activate() } // back from the browser, so the result (or the problem) is seen
            googleAccount = try await server.googleExchange(code: answer.code, verifier: answer.verifier, redirect: answer.redirect)
            return nil
        } catch is CancellationError {
            return nil
        } catch let problem as GoogleSignIn.Problem {
            return problem.message
        } catch let problem as BlinkServer.ChatProblem {
            return problem.message
        } catch {
            return "Couldn't connect Google. Check your connection and try again."
        }
    }
    #endif

    /// Google's consent page, to open in the browser, or a problem to show.
    func googleConnectURL() async -> (url: URL?, problem: String?) {
        guard let server else { return (nil, "Connect to your server first.") }
        do { return (try await server.googleConnectURL(), nil) }
        catch let problem as BlinkServer.ChatProblem { return (nil, problem.message) }
        catch { return (nil, "Couldn't reach your server. Check your connection.") }
    }

    /// People from your mail, newest first, for the invite field.
    var knownPeople: [(name: String, email: String)] {
        var seen = Set<String>()
        return emails.compactMap { mail in
            let key = mail.senderKey
            guard key.contains("@"), seen.insert(key).inserted else { return nil }
            return (mail.fromName, key)
        }
    }

    /// Proposes the meeting, asks for Touch ID, then the server creates it. Returns a problem to show, or nil when done.
    func createMeet(_ draft: MeetDraft) async -> String? {
        guard let server else { return "Connect to your server first." }
        creatingMeet = true
        defer { creatingMeet = false }
        var proposed: BlinkAction?
        do {
            let action: BlinkAction
            if let approved = approvedMeet, approved.draft == draft {
                action = approved.action
            } else {
                // The card changed after an approval that didn't go through: retire that one, ask again for this one.
                if let stale = approvedMeet { try? await server.setStatus("declined", for: stale.action); approvedMeet = nil }
                let new = try await server.proposeMeet(title: draft.title, start: draft.start, minutes: draft.minutes,
                                                       timeZone: TimeZone.current.identifier, guests: draft.guests)
                proposed = new
                try await server.approveRed(new)
                proposed = nil
                approvedMeet = (draft, new)
                action = new
            }
            let result = try await server.createMeet(action)
            approvedMeet = nil
            meetDraft = nil
            if let link = result.meetURL {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
                #else
                UIPasteboard.general.string = link.absoluteString
                #endif
            }
            let when = draft.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            announce("📹 Meet set for \(when)\(result.meetURL == nil ? "" : " · link copied")")
            Task { await reloadAgenda() }
            return nil
        } catch {
            // Not approved (cancelled or failed before Touch ID): drop the proposal so no card is left waiting.
            if let proposed { try? await server.setStatus("declined", for: proposed) }
            if let problem = error as? ApprovalKey.Problem { return problem == .cancelled ? nil : problem.message }
            if let problem = error as? BlinkServer.MeetProblem {
                if problem.spent { approvedMeet = nil }
                return problem.message
            }
            if let problem = error as? BlinkServer.ChatProblem { return problem.message }
            return "That didn't work. Check your connection and try again."
        }
    }

    // MARK: Money (Phase 7, first slice): spends typed in, sorted by the AI, monthly limits per category

    // MARK: Content overview: how the owner's posts perform, and their accounts

    private(set) var pagePosts: [PagePost] = []
    private(set) var socialAccounts: [SocialAccount] = []

    func loadContentStats() async {
        guard let server, email != nil else { return }
        do {
            async let posts = server.pagePosts()
            async let accounts = server.socialAccounts()
            let (p, a) = try await (posts, accounts)
            guard email != nil else { return }
            (pagePosts, socialAccounts) = (p, a)
        } catch {
            // Never show "no posts yet" (and invite a paid re-read) when the list just didn't load.
            contentProblem = "Can't load your page stats right now. Check your connection."
        }
    }

    /// The owner's typed-in followers for a platform (nil = no account there yet).
    func setFollowers(_ followers: Int?, handle: String, on platform: SocialAccount.Platform) async {
        guard let server else { return }
        let account = SocialAccount(platform: platform, handle: handle, followers: followers, updatedAt: .now)
        let before = socialAccounts
        socialAccounts.removeAll { $0.platform == platform }
        socialAccounts.append(account)
        do { try await server.save(account) } catch {
            socialAccounts = before
            contentProblem = "Couldn't save that number. Check your connection."
        }
    }

    private(set) var spends: [Spend] = []
    private(set) var accounts: [MoneyAccount] = []
    /// iPhones (Shortcuts automations) that send Apple Pay taps to the server.
    private(set) var captureTokens: [CaptureToken] = []
    private(set) var budgets: [Budget] = []
    private(set) var moneyProblem: String?
    private(set) var sortingSpends = false
    /// Spending typed in the bar and sorted by Blink, waiting on the Money page to be checked and saved.
    var spendDrafts: [SpendDraft] = []

    /// This month and last, so the page can compare.
    /// A new capture link for one iPhone; the token is shown once (only its hash is stored).
    func makeCaptureLink(name: String) async -> String? {
        guard let server, email != nil else { return nil }
        do {
            let token = try await server.makeCaptureToken(name: name)
            captureTokens = (try? await server.captureTokens()) ?? captureTokens
            return token
        } catch {
            moneyProblem = "Couldn't make a capture link. Check your connection."
            return nil
        }
    }

    func removeCaptureLink(_ token: CaptureToken) async {
        guard let server else { return }
        do {
            try await server.deleteCaptureToken(token)
            captureTokens.removeAll { $0.id == token.id }
        } catch {
            moneyProblem = "Couldn't remove that link. Check your connection."
        }
    }

    var captureEndpoint: URL? { server.map { CaptureToken.endpoint(for: $0.config) } }

    /// Limits reached (80%, then over) and last week's spending, said once each in the notch (Concerned eyes for limits).
    private func tellMoneyNews() {
        let defaults = UserDefaults.standard
        let told = Set(defaults.stringArray(forKey: "money.told") ?? [])
        let month = MoneyMath.month(of: HabitDay.key(.now))
        let alerts = MoneyAlerts.crossed(spends, budgets: budgets, month: month, told: told)
        let week = MoneyAlerts.lastWeek(spends, today: .now).flatMap { told.contains($0.key) ? nil : $0 }
        guard !alerts.isEmpty || week != nil else { return }
        // One notice for all of it: two set back to back could be seen as one.
        let lines = alerts.prefix(2).map(\.text) + (alerts.isEmpty ? [week?.text].compactMap { $0 } : [])
        announce(lines.joined(separator: " "), failed: !alerts.isEmpty)
        // Only what was shown counts as said: a third limit comes on the next sync; the week waits for a day without alerts.
        let said = alerts.prefix(2).map(\.key) + (alerts.isEmpty ? [week?.key].compactMap { $0 } : [])
        defaults.set(MoneyAlerts.remember(told, adding: said, month: month), forKey: "money.told")
    }

    func loadMoney() async {
        guard let server, email != nil else { return }
        do {
            // This month and last for the charts; balances are added up by the server, however old.
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
            let since = MoneyMath.month(of: HabitDay.key(lastMonth)) + "-01"
            async let spent = server.spends(since: since)
            async let limits = server.budgets()
            async let list = server.accounts()
            (spends, budgets, accounts) = try await (spent, limits, list)
            // Optional: a server without the capture table yet (older install) still shows its money.
            captureTokens = (try? await server.captureTokens()) ?? []
            tellMoneyNews()
        } catch {
            // Never show €0 as if nothing was spent.
            moneyProblem = "Can't load your spending right now. Check your connection."
        }
    }

    /// The AI's reading of what was typed; empty (with a problem) when it found nothing.
    func sortSpends(_ text: String) async -> [SpendDraft] {
        guard let server else { return [] }
        sortingSpends = true
        defer { sortingSpends = false }
        moneyProblem = nil
        do { return try await server.sortSpends(text, today: HabitDay.key(.now)) }
        catch let problem as BlinkServer.ChatProblem { moneyProblem = problem.message }
        catch { moneyProblem = "Can't reach your server right now." }
        return []
    }

    @discardableResult
    func addSpends(_ drafts: [SpendDraft]) async -> [Spend]? {
        guard let server else { return nil }
        moneyProblem = nil
        do {
            let saved = try await server.add(drafts)
            spends = (saved + spends).sorted { $0.spentOn > $1.spentOn }
            await reloadAccounts()
            return saved
        } catch {
            moneyProblem = "Couldn't save. Check your connection and try again."
            return nil
        }
    }

    func saveSpend(_ spend: Spend) async {
        guard let server, let i = spends.firstIndex(where: { $0.id == spend.id }) else { return }
        moneyProblem = nil
        let before = spends[i]
        spends[i] = spend
        do { try await server.save(spend); await reloadAccounts() } catch {
            if let j = spends.firstIndex(where: { $0.id == spend.id }) { spends[j] = before }
            moneyProblem = "Couldn't save that change. Check your connection."
        }
    }

    func deleteSpend(_ spend: Spend) async {
        guard let server else { return }
        moneyProblem = nil
        spends.removeAll { $0.id == spend.id }
        do { try await server.delete(spend); await reloadAccounts() } catch {
            spends.append(spend)
            spends.sort { $0.spentOn > $1.spentOn }
            moneyProblem = "Couldn't delete that. Check your connection."
        }
    }

    /// Balances change with every spend; the server adds them up.
    private func reloadAccounts() async {
        guard let server, email != nil, let list = try? await server.accounts() else { return }
        accounts = list
    }

    func addAccount(name: String, kind: MoneyAccount.Kind, balance: Decimal) async {
        guard let server else { return }
        moneyProblem = nil
        do {
            let account = try await server.addAccount(name: name, kind: kind, balance: balance, isDefault: accounts.isEmpty)
            accounts.append(account)
        } catch {
            moneyProblem = "Couldn't add the account. Is the name already used?"
        }
    }

    func setBalance(_ balance: Decimal, of account: MoneyAccount) async {
        guard let server else { return }
        moneyProblem = nil
        do {
            let updated = try await server.setBalance(balance, of: account)
            if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i] = updated }
        } catch {
            moneyProblem = "Couldn't update the balance. Check your connection."
        }
    }

    func makeDefault(_ account: MoneyAccount) async {
        guard let server else { return }
        moneyProblem = nil
        do {
            try await server.makeDefault(account)
            for i in accounts.indices { accounts[i].isDefault = accounts[i].id == account.id }
        } catch {
            moneyProblem = "Couldn't change the default account. Check your connection."
            await reloadAccounts() // the first step may have cleared the old default
        }
    }

    func deleteAccount(_ account: MoneyAccount) async {
        guard let server else { return }
        moneyProblem = nil
        do {
            try await server.deleteAccount(account)
            accounts.removeAll { $0.id == account.id }
            for i in spends.indices where spends[i].accountID == account.id { spends[i].accountID = nil }
        } catch {
            moneyProblem = "Couldn't delete the account. Check your connection."
        }
    }

    /// Sets (or with nil, removes) a category's monthly limit.
    func setLimit(_ limit: Decimal?, for category: SpendCategory) async {
        guard let server else { return }
        moneyProblem = nil
        do {
            try await server.setLimit(limit, for: category)
            budgets.removeAll { $0.category == category }
            if let limit { budgets.append(Budget(category: category, monthlyLimit: limit)) }
        } catch {
            moneyProblem = "Couldn't save the limit. Check your connection."
        }
    }

    /// The platforms picked on the Content page (all three until changed there).
    var contentPlatforms: [ContentPiece.Platform] {
        let saved = UserDefaults.standard.string(forKey: "contentPlatforms") ?? "instagram,linkedin,x"
        let list = saved.split(separator: ",").compactMap { ContentPiece.Platform(rawValue: String($0)) }
        return list.isEmpty ? ContentPiece.Platform.allCases : list
    }

    // MARK: Mail (Phase 5): the server checks every 5 minutes; this reads what it found

    private(set) var emails: [EmailMessage] = []
    private(set) var mailStates: [MailState] = []
    private(set) var mailProblem: String?
    private(set) var syncingMail = false
    private(set) var draftingMail: Set<String> = []
    private var mailWatch: Task<Void, Never>?

    var importantMail: [EmailMessage] { emails.filter { $0.triage == .important } }
    /// Someone wrote personally and expects an answer; not drafted or done yet.
    var awaitingReply: [EmailMessage] { emails.filter { $0.needsReply && ($0.status == .new || $0.status == .seen) } }

    func loadMail() async {
        guard let server, email != nil else { return }
        if let list = try? await server.emails() { emails = list }
        if let states = try? await server.mailStates() { mailStates = states }
        await loadOutbox()
        // Pick up the server's 5-minute checks while the app runs (one small query each time).
        if mailWatch == nil {
            mailWatch = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    await self?.loadMail()
                }
            }
        }
    }

    func syncMail() async {
        guard let server, !syncingMail else { return }
        syncingMail = true
        defer { syncingMail = false }
        mailProblem = nil
        do { try await server.syncMail() }
        catch let problem as BlinkServer.ChatProblem { mailProblem = problem.message }
        catch { mailProblem = "Can't reach your server right now." }
        await loadMail()
    }

    /// A reply open for review before sending; `sendAt` nil means "send now".
    struct Review: Identifiable {
        var draft: MailDraft
        var sendAt: Date?
        let sender: String
        var id: String { draft.messageID }
    }
    var reviewing: Review?
    /// Approved mail waiting for its time, and the one counting down to its send time.
    private(set) var outbox: [BlinkAction] = []
    private(set) var sendingNow: BlinkAction?
    private var sendCountdown: Task<Void, Never>?

    /// Opens the reply for review: Blink's earlier draft if there is one (with edits made in Apple Mail), else a new one.
    /// `reuse: false` always writes a fresh reply into Drafts (it shows in Apple Mail).
    func reviewReply(to message: EmailMessage, note: String = "", sendAt: Date? = nil, reuse: Bool? = nil) async {
        guard let server, !draftingMail.contains(message.id) else { return }
        draftingMail.insert(message.id)
        defer { draftingMail.remove(message.id) }
        mailProblem = nil
        do {
            let draft = try await server.draftReply(to: message, note: note, reuse: reuse ?? (note.isEmpty && message.status == .drafted))
            if let i = emails.firstIndex(where: { $0.id == message.id }) { emails[i].status = .drafted }
            openPage = "inbox"
            #if os(macOS)
            // Approved from the notch: bring the window forward so the review sheet is seen.
            showWindow()
            #endif
            reviewing = Review(draft: draft, sendAt: sendAt.flatMap { $0 > .now ? $0 : nil }, sender: message.sender)
        } catch let problem as BlinkServer.ChatProblem {
            mailProblem = problem.message
        } catch {
            mailProblem = "Can't reach your server right now."
        }
    }

    /// Sends the reviewed reply after Touch ID: now (after a chance to cancel) or at its time. Returns a
    /// problem to show in the review sheet, or nil when it's on its way.
    func send(_ review: Review) async -> String? {
        guard let server else { return "Sign in first." }
        // 20 s, not 10: Touch ID can take a while, and the cancel window counts from this signed time.
        let at = review.sendAt ?? .now.addingTimeInterval(20)
        let when = review.sendAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "now"
        do {
            let action = try await server.proposeSend(review.draft, at: at, title: "Send reply to \(review.sender)?",
                                                       summary: "\(review.draft.subject) · \(when)")
            do {
                try await server.approveRed(action)
            } catch {
                // No half-approved sends left behind: the sheet stays open to try again.
                try? await server.setStatus("declined", for: action)
                if let problem = error as? ApprovalKey.Problem { return problem.message }
                throw error
            }
            reviewing = nil
            if let i = emails.firstIndex(where: { $0.id == review.draft.emailID }) { emails.remove(at: i) }
            await afterSendApproved(action, now: review.sendAt == nil)
            return nil
        } catch {
            return "Couldn't send. Check your connection and try again."
        }
    }

    /// After Touch ID: "Sending… Cancel" until the signed send time, then hand it to the server; scheduled mail just joins the outbox.
    private func afterSendApproved(_ action: BlinkAction, now: Bool = true) async {
        await loadOutbox()
        guard now, let server else { return }
        sendingNow = action
        sendCountdown = Task { [weak self] in
            // The server sends nothing before send_at, so wait for it (plus 1 s for clock drift), however long Touch ID took.
            let wait = (action.payload.sendAt ?? .now).timeIntervalSinceNow + 1
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.sendingNow = nil
            try? await server.sendDueMail()
            await self?.loadOutbox()
            await self?.loadActivity()
        }
    }

    func loadOutbox() async {
        guard let server, email != nil, let list = try? await server.outbox() else { return }
        outbox = list
    }

    /// Stops a send that hasn't gone yet (the countdown or a scheduled one).
    func cancelSend(_ action: BlinkAction) async {
        guard let server else { return }
        if sendingNow?.id == action.id { sendCountdown?.cancel(); sendingNow = nil }
        do {
            if try await !server.cancelSend(action) {
                mailProblem = "Too late to cancel: it's already sending."
            }
        } catch {
            mailProblem = "Couldn't cancel. Check your connection."
        }
        await loadOutbox()
        await loadMail()
    }

    /// What Blink has learned about senders, for Settings › Privacy.
    private(set) var senderRules: [BlinkServer.SenderRule] = []
    private(set) var rulesProblem: String?

    func loadSenderRules() async {
        guard let server else { return }
        do {
            senderRules = try await server.senderRules()
            rulesProblem = nil
        } catch {
            rulesProblem = "Couldn't load what Blink has learned. Check your connection."
        }
    }

    func forget(_ rule: BlinkServer.SenderRule) async {
        guard let server else { return }
        let before = senderRules
        senderRules.removeAll { $0.id == rule.id }
        do { try await server.forget(rule: rule) } catch {
            senderRules = before
            rulesProblem = "Couldn't forget that. Check your connection."
        }
    }

    /// The owner corrects Blink: this mail (and everything later from this sender) is important or not.
    func teach(_ verdict: SenderVerdict, for message: EmailMessage) async {
        guard let server, let i = emails.firstIndex(where: { $0.id == message.id }) else { return }
        let before = emails
        let triage: EmailMessage.Triage = verdict == .important ? .important : .newsletter
        for j in emails.indices where emails[j].senderKey == message.senderKey { emails[j].triage = triage }
        do {
            let earlier = try await server.teach(verdict, for: emails[i])
            offerUndo(verdict == .important ? "Mail from \(message.sender) will show as important" : "Mail from \(message.sender) won't show as important") { [weak self] in
                guard let self else { return }
                // Only this sender's mail goes back to how it was sorted; anything changed since stays.
                let changed = before.filter { $0.senderKey == message.senderKey }
                for old in changed { if let j = emails.firstIndex(where: { $0.id == old.id }) { emails[j].triage = old.triage } }
                do { try await server.forget(senderKey: message.senderKey, restoring: changed, rule: earlier) } catch {
                    mailProblem = "Couldn't undo that. Check your connection."
                }
            }
        } catch {
            emails = before
            mailProblem = "Couldn't save that. Check your connection."
        }
    }

    // shortcut: session-only, so a step saved before a relaunch can be added again; persist when duplicates are reported.
    /// Next steps already saved this session ("<mail id>#<index>"), so a chip shows "Added" instead of adding twice.
    private(set) var savedSteps: Set<String> = []

    /// Turns a next step from a mail into the real thing, at once and with Undo (§36.4 green tier): an event in the
    /// owner's own calendar (never with guests), a reminder, a task or a note. Each one says which mail it came from.
    func save(_ step: MailAction, from message: EmailMessage, index: Int) async {
        let key = "\(message.id)#\(index)"
        guard !savedSteps.contains(key) else { return }
        // Claimed first, so a double tap (or the notch and the window at once) adds it only once.
        savedSteps.insert(key)
        let when: (Date?) -> String = { $0.map { " · \($0.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))" } ?? "" }
        // The call link (Webex, Zoom, Meet, Teams…) from the whole mail: an event gets it as its Join link, a task or note
        // keeps it in its text. Only known call services count; the mail is read now and not kept. No link (or no
        // connection): it's added anyway.
        let join = step.kind == .event || step.kind == .task ? AgendaEvent.meetingLink(in: try? await server?.readMail(message)) : nil
        let from = [message.sourceLine + (message.receivedAt.map { " · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""),
                    join.map { "Join: \($0.absoluteString)" }, message.mailURL.map { "Open the mail: \($0.absoluteString)" }]
            .compactMap { $0 }.joined(separator: "\n")
        switch step.kind {
        case .event:
            guard let start = step.start else {
                savedSteps.remove(key)
                mailProblem = "That date doesn't exist on the calendar. Add the event yourself."
                return
            }
            guard calendarAccess == .granted else {
                savedSteps.remove(key)
                mailProblem = "Turn on Calendars for Blink in System Settings › Privacy & Security › Calendars."
                return
            }
            do {
                let id = try await calendarReader.addEvent(step.title, start: start, end: step.finish, allDay: step.allDay,
                                                           location: step.where, notes: from, url: join ?? message.mailURL)
                await reloadAgenda()
                offerUndo("Added to Calendar: \(step.title)\(when(start))\(join == nil ? "" : " · with Join link")") { [weak self] in
                    do { try await self?.calendarReader.deleteEvent(id: id) } catch {
                        self?.mailProblem = "Couldn't remove that event. Delete it in Calendar."
                    }
                    self?.savedSteps.remove(key)
                    await self?.reloadAgenda()
                }
            } catch {
                savedSteps.remove(key)
                mailProblem = "Couldn't add that to your calendar. Check that Calendars is allowed for Blink."
                return
            }
        case .deadline:
            guard calendarAccess == .granted else {
                savedSteps.remove(key)
                mailProblem = "Turn on Reminders for Blink in System Settings › Privacy & Security › Reminders."
                return
            }
            // A day-only deadline reminds at 9:00 that morning, so it actually rings.
            let due = step.allDay ? step.start.flatMap { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } : step.start
            do {
                let id = try await calendarReader.addReminder(step.title, due: due, notes: from, url: message.mailURL)
                await reloadAgenda()
                offerUndo("Reminder added: \(step.title)\(when(due))") { [weak self] in
                    await self?.writeReminder { try await self?.calendarReader.deleteReminder(id: id) }
                    self?.savedSteps.remove(key)
                }
            } catch {
                savedSteps.remove(key)
                mailProblem = "Couldn't add that reminder. Check that Reminders is allowed for Blink."
                return
            }
        case .task, .note:
            // A note says when it's about, if the mail gave a date; a day-only task is due at 9:00 that morning.
            let about = step.kind == .note ? step.start.map { "When\(when($0))\n" } ?? "" : ""
            let item = create(step.kind == .task ? .task : .note, title: step.title, body: about + from,
                              due: step.kind == .task ? (step.allDay ? step.start.flatMap { Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } : step.start) : nil)
            offerUndo("\(step.kind == .task ? "Task added" : "Saved to Notes"): \(step.title)") { [weak self] in
                guard let self, let current = self.items.first(where: { $0.id == item.id }) else { return }
                await self.delete(current)
                self.savedSteps.remove(key)
            }
        }
    }

    /// The full text for the reading pane; marks the mail seen. Throws a message to show.
    func read(_ message: EmailMessage) async throws -> String {
        guard let server else { throw CancellationError() }
        if message.status == .new { await setStatus(.seen, of: message) }
        return try await server.readMail(message)
    }

    /// Done for one mail or many at once (bulk), with one Undo that puts them all back as they were.
    func finish(_ messages: [EmailMessage]) async {
        guard let server, !messages.isEmpty else { return }
        let ids = Set(messages.map(\.id))
        let before = emails
        emails.removeAll { ids.contains($0.id) }
        do {
            try await server.setStatus(.done, ids: Array(ids))
            offerUndo(messages.count == 1 ? "Cleared: \(messages[0].subject)" : "\(messages.count) emails cleared") { [weak self] in
                guard let self else { return }
                let back = before.filter { ids.contains($0.id) }
                do {
                    for status in Set(back.map(\.status)) {
                        try await server.setStatus(status, ids: back.filter { $0.status == status }.map(\.id))
                    }
                } catch {
                    mailProblem = "Couldn't bring those emails back. Check your connection."
                }
                // Only these come back; anything done or arrived since stays as it is now.
                emails = (emails.filter { !ids.contains($0.id) } + back)
                    .sorted { ($0.receivedAt ?? $0.createdAt) > ($1.receivedAt ?? $1.createdAt) }
            }
        } catch {
            emails = before
            mailProblem = "Couldn't update those emails. Check your connection."
        }
    }

    func setStatus(_ status: EmailMessage.Status, of message: EmailMessage) async {
        guard let server, let i = emails.firstIndex(where: { $0.id == message.id }) else { return }
        let before = emails[i]
        if status == .done { emails.remove(at: i) } else { emails[i].status = status }
        do { try await server.setStatus(status, of: message) } catch {
            if status == .done { emails.insert(before, at: min(i, emails.count)) } else if let j = emails.firstIndex(where: { $0.id == message.id }) { emails[j] = before }
            mailProblem = "Couldn't update that email. Check your connection."
        }
    }

    // MARK: Model choice (Settings, Blink panel, Content page share this)

    /// Feature ("chat", "content") → model id, from the profile on the server.
    private(set) var modelPrefs: [String: String] = [:]
    private(set) var modelProblem: String?

    /// Claude stops for the day at this many dollars (free Groq models keep working); nil = no limit.
    private(set) var dailyCap: Double?

    func loadModelPrefs() async {
        guard let server, email != nil, let prefs = try? await server.modelPrefs() else { return }
        modelPrefs = prefs
        dailyCap = try? await server.dailyCap()
    }

    func setDailyCap(_ cap: Double?) async {
        guard let server else { return }
        let before = dailyCap
        dailyCap = cap
        do { try await server.setDailyCap(cap) } catch {
            dailyCap = before
            modelProblem = "Couldn't change the limit. Check your connection and try again."
        }
    }

    /// A page for the window to show (from the notch's "Open" buttons); MainWindow clears it once shown.
    var openPage: String?
    /// A blink://signin link macOS handed to Blink (the sign-in finished in another browser tab).
    var openedSignin: URL?

    var readyToPost: [ContentPiece] { content.filter { $0.status == .approved } }

    /// Picked "Apple Intelligence · on this Mac" for chat. Kept on this device: the server's chat setting stays a server
    /// model, because mail drafts read it.
    private var onDevicePicked = UserDefaults.standard.bool(forKey: "chat.onDevice") {
        didSet { UserDefaults.standard.set(onDevicePicked, forKey: "chat.onDevice") }
    }

    func model(for feature: String) -> AIModel {
        let id = AIModel.choose(feature: feature, serverPref: modelPrefs[feature], onDevicePicked: onDevicePicked,
                                onDeviceReady: OnDeviceChat.problem == nil,
                                claudeWorks: keyStatus.map { $0["anthropic"] == "ok" }, serverReachable: status != .unreachable)
        return AIModel.all.first { $0.id == id }!
    }

    func setModel(_ id: String, for feature: String) async {
        if feature == "chat" { onDevicePicked = id == AIModel.onDeviceID }
        guard id != AIModel.onDeviceID, let server else { return }
        let before = modelPrefs
        modelPrefs[feature] = id
        do {
            try await server.setModelPrefs(modelPrefs)
            modelProblem = nil
        } catch {
            modelPrefs = before
            modelProblem = "Couldn't change the model. Check your connection and try again."
        }
    }

    // MARK: Spaces (ARCHITECTURE §35)

    private(set) var spaces: [Space] = []

    func loadSpaces() async {
        guard let server, email != nil, let list = try? await server.spaces() else { return }
        spaces = list
    }

    /// Adds the space at once; takes it back out if the server refuses.
    func createSpace(_ space: Space) async {
        guard let server else { return }
        spaces.append(space)
        do {
            try await server.save(new: space)
        } catch {
            spaces.removeAll { $0.id == space.id }
            saveProblem = "Couldn't create the space. Check your connection and try again."
        }
    }

    func saveSpace(_ space: Space) async {
        guard let server, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let before = spaces[index]
        spaces[index] = space
        if before.title != space.title, calendarAccess == .granted {
            try? await calendarReader.renameReminderList(from: before.title, to: space.title)
        }
        do {
            try await server.save(space)
        } catch {
            if let i = spaces.firstIndex(where: { $0.id == space.id }) { spaces[i] = before }
            saveProblem = "Couldn't save the space. Check your connection and try again."
        }
    }

    // MARK: A Space's reminders (its own list in Apple Reminders, named like the Space)

    /// Open reminders per Space id, loaded when its page shows.
    private(set) var spaceReminders: [String: [AgendaReminder]] = [:]

    func loadReminders(for space: Space) async {
        guard calendarAccess == .granted else { return }
        spaceReminders[space.id] = await calendarReader.reminders(inList: space.title)
    }

    /// A reminder in the Space's list (made the first time), with Undo; it syncs to the owner's iPhone like any other.
    /// Returns its id (nil when it couldn't be added).
    @discardableResult
    func addReminder(_ title: String, due: Date?, to space: Space) async -> String? {
        guard calendarAccess == .granted else {
            saveProblem = "Turn on Reminders for Blink in System Settings › Privacy & Security › Reminders."
            return nil
        }
        do {
            let id = try await calendarReader.addReminder(title, due: due, list: space.title)
            await loadReminders(for: space)
            await reloadAgenda()
            offerUndo("Reminder added to \(space.title): \(title)") { [weak self] in
                await self?.writeReminder { try await self?.calendarReader.deleteReminder(id: id) }
                await self?.loadReminders(for: space)
            }
            return id
        } catch {
            saveProblem = "Couldn't add that reminder. Check that Reminders is allowed for Blink."
            return nil
        }
    }

    // MARK: A Space's canvas

    /// The canvas is a large sheet; the project starts in its middle.
    static let canvasSize = CanvasLayout.size
    static let canvasCenter = (x: CanvasLayout.size.width / 2, y: CanvasLayout.size.height / 2)

    private(set) var canvasNodes: [String: [SpaceNode]] = [:]
    private(set) var canvasEdges: [String: [SpaceEdge]] = [:]

    /// Loads the canvas and adds what's missing: the project node, and a node for every task, note and reminder in the
    /// Space that hasn't one yet. Nodes whose thing isn't here are kept, only hidden: the list may just not have
    /// loaded (Reminders off, items still coming), and deleting them would lose their place and links.
    // shortcut: nodes of deleted things stay on the server hidden, a few rows per Space; clean them up when deleting an item if they pile up.
    func loadCanvas(_ space: Space) async {
        guard let server else { return }
        await loadReminders(for: space)
        let loaded: (nodes: [SpaceNode], edges: [SpaceEdge])
        do { loaded = try await server.canvas(of: space.id) } catch {
            saveProblem = serverBehind ? "Update your server (Settings › Update Server) to open this canvas."
                : "Couldn't load this Space's canvas. Check your connection and try again."
            return
        }
        // Keep anything added here while the load was on its way.
        let local = canvasNodes[space.id] ?? []
        let nodes = loaded.nodes + local.filter { node in !loaded.nodes.contains { $0.id == node.id || ($0.ref != nil && $0.ref == node.ref) } }
        let edges = loaded.edges + (canvasEdges[space.id] ?? []).filter { edge in !loaded.edges.contains { $0.id == edge.id } }
        var added: [SpaceNode] = []
        if !nodes.contains(where: { $0.kind == .project }) {
            // The project node's id is the Space's own, so two Macs adding it at once make the same row.
            added.append(SpaceNode(id: space.id, spaceID: space.id, kind: .project, x: Self.canvasCenter.x, y: Self.canvasCenter.y, color: space.color))
        }
        canvasNodes[space.id] = nodes + added
        canvasEdges[space.id] = edges
        for node in added { await canvasWrite { try await server.save(node) } }
        canvasLoaded.insert(space.id)
        await addMissingNodes(space)
    }

    /// Spaces whose canvas has loaded; only those get new nodes added (before, the server's nodes aren't known yet).
    private var canvasLoaded: Set<String> = []

    /// A node for every task, note, reminder and post in the Space that hasn't one yet, e.g. one just approved in chat
    /// or added on another page while the canvas is open.
    func addMissingNodes(_ space: Space, near spot: (x: Double, y: Double) = canvasCenter) async {
        guard canvasLoaded.contains(space.id), let server else { return }
        let nodes = canvasNodes[space.id] ?? []
        let mine = items.filter { $0.spaceID == space.id && $0.status != .archived }
        let posts = content.filter { $0.spaceID == space.id && $0.status != .archived }
        let wanted: [(SpaceNode.Kind, String)] = mine.map { ($0.type == .note ? .note : .task, $0.id) }
            + (spaceReminders[space.id] ?? []).map { (.reminder, $0.id) } + posts.map { (.post, $0.id) }
        var added: [SpaceNode] = []
        for (kind, ref) in wanted where !(nodes + added).contains(where: { $0.ref == ref }) {
            let place = CanvasLayout.onSheet(CanvasLayout.freeSpot(around: spot, taken: nodes + added, radius: 200))
            added.append(SpaceNode(spaceID: space.id, kind: kind, ref: ref, x: place.x, y: place.y, color: kind == .note ? "yellow" : space.color))
        }
        guard !added.isEmpty else { return }
        canvasNodes[space.id] = nodes + added
        do {
            for node in added { try await server.save(node) }
        } catch where BlinkServer.isDuplicate(error) {
            // Another Mac placed it first: take the server's cards instead of showing a problem.
            await loadCanvas(space)
        } catch {
            await canvasWrite { throw error }
        }
    }

    /// A canvas change saved behind the screen; a failure says so instead of quietly snapping back on the next load.
    private func canvasWrite(_ write: () async throws -> Void) async {
        do { try await write() } catch {
            saveProblem = serverBehind ? "Update your server (Settings › Update Server) to save canvas changes."
                : "Couldn't save a change to the canvas. Check your connection and try again."
        }
    }

    /// A new task, note or reminder made on the canvas: the real thing, and its node at `spot` (else the first free spot
    /// near `parent` or the project). It links from `parent`; placed by hand with no parent, it stays on its own.
    @discardableResult
    func addToCanvas(_ kind: SpaceNode.Kind, title: String, due: Date? = nil, in space: Space, linkedFrom parent: SpaceNode? = nil,
                     at spot: (x: Double, y: Double)? = nil) async -> SpaceNode? {
        let ref: String?
        switch kind {
        case .task: ref = create(.task, title: title, due: due, space: space.id).id
        case .note: ref = create(.note, title: title, space: space.id).id
        case .reminder:
            ref = await addReminder(title, due: due, to: space)
        case .project, .image, .post, .heading, .section: ref = nil
        }
        guard let ref else { return nil }
        var nodes = canvasNodes[space.id] ?? []
        let anchor = parent.map { (x: $0.x, y: $0.y) } ?? Self.canvasCenter
        let place = CanvasLayout.onSheet(spot ?? CanvasLayout.freeSpot(around: anchor, taken: nodes, radius: parent == nil ? 300 : 260))
        let node = SpaceNode(spaceID: space.id, kind: kind, ref: ref, x: place.x, y: place.y, color: kind == .note ? "yellow" : space.color)
        nodes.append(node)
        canvasNodes[space.id] = nodes
        await canvasWrite { try await server?.save(node) }
        if let from = parent ?? (spot == nil ? nodes.first(where: { $0.kind == .project }) : nil) { await connect(from, to: node, in: space) }
        return node
    }

    /// Where a node was dropped after dragging; shown at once (no snap back), saved behind.
    func moveNode(_ node: SpaceNode, x: Double, y: Double) {
        guard var nodes = canvasNodes[node.spaceID], let i = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        (nodes[i].x, nodes[i].y) = CanvasLayout.onSheet((x, y))
        canvasNodes[node.spaceID] = nodes
        let moved = nodes[i]
        // shortcut: each drop saves on its own, so two very quick drops can land out of order; queue per node if seen.
        Task { await canvasWrite { try await server?.save(moved) } }
    }

    func recolor(_ node: SpaceNode, to color: String) { change(node) { $0.color = color } }

    /// A section dropped somewhere else, with the cards it carries: the section stays on the sheet and everything shifts
    /// by the same amount, saved in one go so they can't end up split between old and new places.
    func moveSection(_ section: SpaceNode, carrying carried: [SpaceNode], by dx: Double, _ dy: Double) {
        let spot = CanvasLayout.onSheet((section.x + dx, section.y + dy))
        let (sx, sy) = (spot.x - section.x, spot.y - section.y)
        let ids = Set(([section] + carried).map(\.id))
        guard var nodes = canvasNodes[section.spaceID] else { return }
        for i in nodes.indices where ids.contains(nodes[i].id) { (nodes[i].x, nodes[i].y) = (nodes[i].x + sx, nodes[i].y + sy) }
        canvasNodes[section.spaceID] = nodes
        let moved = nodes.filter { ids.contains($0.id) }
        Task { await canvasWrite { try await server?.save(moved) } }
    }

    /// A sticky or image dragged to a new size, its top-left corner staying put.
    func resize(_ node: SpaceNode, width: Double, height: Double) {
        var size = SpaceNode.clamped(width: width, height: height)
        // A heading's height follows its text size; only its width is dragged.
        if node.kind == .heading { size.height = node.size.height }
        let centre = CanvasLayout.onSheet((node.x + (size.width - node.size.width) / 2, node.y + (size.height - node.size.height) / 2))
        let keepsHeight = node.kind == .heading
        change(node) {
            ($0.w, $0.x, $0.y) = (size.width, centre.x, centre.y)
            if !keepsHeight { $0.h = size.height }
        }
    }

    // Standard is stored as 1, not nil: an upsert leaves nil out, so the old size would stay on the server.
    func setTextScale(_ node: SpaceNode, to scale: Double) { change(node) { $0.textScale = scale } }

    /// A heading's text or a section's title, edited in place.
    func relabel(_ node: SpaceNode, to label: String) {
        // 200 as the database counts (code points), so a title of emoji can't pass here and fail there.
        let clean = label.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let text = String(String.UnicodeScalarView(clean.unicodeScalars.prefix(200)))
        change(node) { $0.label = text }
    }

    /// A new heading or section at `spot`, ready to name.
    func addMark(_ kind: SpaceNode.Kind, in space: Space, at spot: (x: Double, y: Double)) async -> SpaceNode {
        let place = CanvasLayout.onSheet(spot)
        let node = SpaceNode(spaceID: space.id, kind: kind, x: place.x, y: place.y, color: kind == .section ? space.color : "gray",
                             label: kind == .section ? "Section" : "Heading")
        canvasNodes[space.id, default: []].append(node)
        await canvasWrite { try await server?.save(node) }
        return node
    }

    /// A change to how a node looks: shown at once, saved behind.
    private func change(_ node: SpaceNode, _ edit: (inout SpaceNode) -> Void) {
        guard var nodes = canvasNodes[node.spaceID], let i = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        edit(&nodes[i])
        canvasNodes[node.spaceID] = nodes
        let changed = nodes[i]
        Task { await canvasWrite { try await server?.save(changed) } }
    }

    #if os(macOS)
    /// Pictures already fetched for the canvas, by their path on the server.
    private(set) var canvasImages: [String: NSImage] = [:]

    func loadCanvasImage(_ path: String) async {
        guard canvasImages[path] == nil, let server else { return }
        // shortcut: pictures stay in memory while Blink runs; cache them on disk if Spaces get heavy with images.
        if let data = try? await server.canvasImage(path), let image = NSImage(data: data) { canvasImages[path] = image }
    }

    /// A picture added to the canvas (from a file chosen or dropped): made small and stripped of its metadata, stored on the
    /// owner's server, and placed at `spot`.
    func addImage(from file: URL, in space: Space, at spot: (x: Double, y: Double)) async {
        guard let server else { return }
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        // Huge files are refused before they're read; the picture is shrunk far below this anyway.
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // Read and shrink off the main thread, so a drop of big photos doesn't freeze the window.
        let ready = bytes > 60_000_000 ? nil : await Task.detached(operation: { (try? Data(contentsOf: file)).flatMap { CanvasImage.jpeg(from: $0) } }).value
        guard let ready else {
            saveProblem = bytes > 60_000_000 ? "That picture is too big. Pictures up to 60 MB work." : "That file isn't a picture Blink can read."
            return
        }
        let path: String
        do { path = try await server.uploadCanvasImage(ready.data, space: space.id) } catch {
            saveProblem = "Couldn't upload the picture. Check your connection and try again."
            return
        }
        canvasImages[path] = NSImage(data: ready.data)
        let size = CanvasImage.size(width: ready.width, height: ready.height)
        let place = CanvasLayout.onSheet(spot)
        let node = SpaceNode(spaceID: space.id, kind: .image, ref: path, x: place.x, y: place.y, w: size.width, h: size.height)
        canvasNodes[space.id, default: []].append(node)
        await canvasWrite { try await server.save(node) }
    }
    #endif

    /// Takes a picture, heading or section off the canvas with its links, with Undo (a section's cards stay); a
    /// picture's file goes once Undo has passed.
    func removeNode(_ node: SpaceNode) async {
        guard let server else { return }
        let links = canvasEdges[node.spaceID]?.filter { $0.from == node.id || $0.to == node.id } ?? []
        do { try await server.delete(node) } catch {
            saveProblem = "Couldn't remove that. Check your connection and try again."
            return
        }
        canvasNodes[node.spaceID]?.removeAll { $0.id == node.id }
        canvasEdges[node.spaceID]?.removeAll { links.contains($0) }
        let what = switch node.kind { case .heading: "a heading"; case .section: "a section"; default: "a picture" }
        offerUndo("Removed \(what)") { [weak self] in
            guard let self else { return }
            canvasNodes[node.spaceID, default: []].append(node)
            canvasEdges[node.spaceID, default: []] += links
            await canvasWrite {
                try await server.save(node)
                for edge in links { try await server.save(edge) }
            }
        }
        guard node.kind == .image, let path = node.ref else { return }
        try? await Task.sleep(for: .seconds(Tokens.Hold.undoChip + 5))
        // A later action can keep the same Undo chip up longer; wait it out.
        while undoChip != nil || undoing { try? await Task.sleep(for: .seconds(1)) }
        guard canvasNodes[node.spaceID]?.contains(where: { $0.id == node.id }) != true else { return }
        // shortcut: a file whose removal fails (or Blink quits first) stays in the bucket unseen; sweep files with no node if storage grows.
        try? await server.removeCanvasImage(path)
    }

    func connect(_ from: SpaceNode, to: SpaceNode, in space: Space) async {
        guard from.id != to.id else { return }
        let edges = canvasEdges[space.id] ?? []
        guard !edges.contains(where: { ($0.from == from.id && $0.to == to.id) || ($0.from == to.id && $0.to == from.id) }) else { return }
        let edge = SpaceEdge(spaceID: space.id, from: from.id, to: to.id)
        canvasEdges[space.id] = edges + [edge]
        await canvasWrite { try await server?.save(edge) }
    }

    func disconnect(_ edge: SpaceEdge) async {
        canvasEdges[edge.spaceID]?.removeAll { $0.id == edge.id }
        await canvasWrite { try await server?.delete(edge) }
    }

    func complete(_ reminder: AgendaReminder, in space: Space) async {
        spaceReminders[space.id]?.removeAll { $0.id == reminder.id }
        await complete(reminder)
    }

    /// Deletes the space; its tasks and notes stay, outside any space.
    func deleteSpace(_ space: Space) async {
        guard let server, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces.remove(at: index)
        do {
            try await server.delete(space)
            for i in items.indices where items[i].spaceID == space.id { items[i].spaceID = nil }
        } catch {
            spaces.insert(space, at: min(index, spaces.count))
            saveProblem = "Couldn't delete the space. Check your connection and try again."
        }
    }

    func move(_ item: BlinkItem, to spaceID: String?) async {
        var changed = item
        changed.spaceID = spaceID
        edit(changed)
        await save(item.id)
    }

    // MARK: Apple Reminders

    /// Ticks off a reminder. It leaves the list at once; the change reaches Apple Reminders straight after.
    func complete(_ reminder: AgendaReminder, offeringUndo: Bool = true) async {
        agenda.reminders.removeAll { $0.id == reminder.id }
        allReminders.removeAll { $0.id == reminder.id }
        playFinishSound()
        if offeringUndo { offerUndo("Done: \(reminder.title)") { [weak self] in await self?.reopen(reminder) } }
        await writeReminder { try await calendarReader.updateReminder(id: reminder.id, completed: true) }
    }

    func rename(_ reminder: AgendaReminder, to title: String) async {
        await writeReminder { try await calendarReader.updateReminder(id: reminder.id, title: title) }
    }

    func setDue(_ reminder: AgendaReminder, to due: Date?, reload: Bool = true) async {
        await writeReminder(reload: reload) { try await calendarReader.setReminderDue(id: reminder.id, due: due, timed: reminder.timed) }
    }

    private func writeReminder(reload: Bool = true, _ write: () async throws -> Void) async {
        do {
            try await write()
            saveProblem = nil
        } catch {
            saveProblem = "Couldn't change that reminder. It may have been deleted in Reminders."
        }
        if reload { await reloadAgenda() } // show what Reminders really holds now
    }

    // MARK: Calendar

    /// Asked only when the user taps Connect Calendar, never at launch.
    func connectCalendar() async {
        let access = await calendarReader.requestAccess()
        // Load the agenda before saying "granted", so nothing shows "no meetings" while it loads.
        if access == .granted { await startCalendar() }
        calendarAccess = access
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
        // One at a time: overlapping uploads could land out of order and bring back a deleted event.
        // Changes that arrive meanwhile get exactly one more pass.
        guard !reloading else { reloadAgain = true; return }
        reloading = true
        defer { reloading = false }
        repeat {
            reloadAgain = false
            let window = CalendarReader.window(from: .now)
            let read = await calendarReader.agenda(in: window)
            calendarEvents = read.events
            agenda = read
            showMeetings()
            allReminders = await calendarReader.openReminders() // the Tasks page shows every open reminder
            guard let server, email != nil else { continue }
            // The device is the source of truth; a failed upload is simply retried by the next reload.
            try? await server.uploadCalendar(calendarEvents, window: window)
        } while reloadAgain
    }

    /// Marks a meeting done (left early, or finished): it leaves the notch and Today until the calendar drops it. Undo-able.
    /// Every timed meeting in `window` from this Mac's calendars, for the Calendar page's week and month.
    func events(in window: DateInterval) async -> [AgendaEvent] {
        guard calendarAccess == .granted else { return [] }
        return await calendarReader.agenda(in: window).events
    }

    func finishMeeting(_ event: AgendaEvent) {
        doneMeetings.insert(event.id)
        showMeetings()
        offerUndo("Meeting done: \(event.title)") { [weak self] in self?.reopenMeeting(event) }
    }

    /// Brings a meeting marked done back (Undo, or "Not done" on the Calendar page after a wrong tap).
    func reopenMeeting(_ event: AgendaEvent) {
        doneMeetings.remove(event.id)
        showMeetings()
    }

    /// Applies `doneMeetings` to the agenda, forgetting old ones (Agenda.hidingDone).
    private func showMeetings() {
        let result = Agenda.hidingDone(calendarEvents, done: doneMeetings, now: .now)
        doneMeetings = result.keep
        UserDefaults.standard.set(Array(doneMeetings), forKey: "meetings.done")
        agenda.events = result.shown
    }

    // MARK: App lock

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            let after = UserDefaults.standard.object(forKey: "lockAfter") as? Double ?? AppLock.defaultRelockAfter
            if AppLock.shouldRelock(awaySince: awaySince, after: after) {
                locked = true
                promptPending = true
            }
            awaySince = nil
        } else if awaySince == nil {
            awaySince = .now
        }
    }

    /// Screen lock and sleep count as away, like leaving the window: on the way back the owner's relock time applies,
    /// so the notch, which never changes the scene phase, can't stay unlocked for whoever sits down next.
    func screenAway() {
        if awaySince == nil { awaySince = .now }
    }

    func screenBack() { scenePhaseChanged(.active) }

    /// Before quitting: sends edits still waiting (a note typed less than a second ago).
    func saveUnsaved() async {
        for id in unsaved { await save(id) }
    }
    var hasUnsaved: Bool { !unsaved.isEmpty }

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
