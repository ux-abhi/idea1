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

    /// This session's chat with Blink (not stored). shortcut: history lives in memory; persist it with Chat history (§36.2).
    private(set) var chat: [BlinkServer.ChatTurn] = []
    private(set) var thinking = false

    /// The running Pomodoro phase or timer; kept on disk so it survives a restart.
    private(set) var timer: FocusTimer? = AppModel.savedTimer() {
        didSet { saveTimer() }
    }
    /// A phase that just ended, waiting for "Start break" / "Skip".
    private(set) var finishedTimer: FocusTimer?
    /// Bumped when a timer ends; the notch opens.
    private(set) var timersEnded = 0
    private var timerWatch: Task<Void, Never>?

    private(set) var agenda = Agenda.empty
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
            await loadItems()
            await loadSpaces()
            await loadModelPrefs()
            await loadContent() // the brief and Today show posts ready
            await loadHabits()
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

    func loadActivity() async {
        guard let server, email != nil, let recent = try? await server.recentActivity() else { return }
        activity = recent
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
            await loadActivity()
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
            guard let id = action.payload.targetID else { return }
            try await calendarReader.setReminderDue(id: id, due: action.payload.due)
            try await server.setStatus("done", for: action, result: ["reminder_id": id])
            await reloadAgenda()
        case "reminder.complete", "reminder.delete":
            guard let id = action.payload.targetID else { return }
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
            let task = create(.task, title: action.payload.reminder ?? action.title, due: action.payload.due)
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
        default:
            break
        }
    }

    // MARK: Notes and tasks
    // shortcut: online only, no local cache; add SwiftData + delta sync by rev (§17, §36.1) when offline capture or the iPhone app needs it.

    var notes: [BlinkItem] { items.filter { $0.type == .note }.sorted { $0.updatedAt > $1.updatedAt } }
    var openTasks: [BlinkItem] { items.filter { $0.type == .task && $0.status == .open } }
    /// Open tasks with a due time, for the notch's cues and status line.
    var dueTasks: [DueItem] { openTasks.compactMap { t in t.dueAt.map { DueItem(id: t.id, title: t.title, due: $0) } } }
    var doneTasks: [BlinkItem] { items.filter { $0.type == .task && $0.status == .done } }

    func loadItems() async {
        guard let server, email != nil else { return }
        for id in unsaved { await save(id) } // retry anything a failed save left behind
        guard let fresh = try? await server.items() else { return }
        onServer = Set(fresh.map(\.id))
        items = BlinkItem.merge(server: fresh, local: items, unsaved: unsaved)
    }

    @discardableResult
    func create(_ type: BlinkItem.Kind, title: String, due: Date? = nil, space: String? = nil) -> BlinkItem {
        let item = BlinkItem(id: UUID().uuidString.lowercased(), type: type, title: title, dueAt: due, spaceID: space)
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
                onServer.insert(id)
            }
            // Only clear if nothing was typed while saving.
            if items.first(where: { $0.id == id }) == item { unsaved.remove(id) }
            if unsaved.isEmpty { saveProblem = nil }
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
        let undo: @MainActor () async -> Void
    }

    /// The last thing marked done, undoable for a few seconds in the window and the notch.
    private(set) var undoChip: UndoChip?

    func offerUndo(_ text: String, undo: @escaping @MainActor () async -> Void) {
        let chip = UndoChip(text: text, undo: undo)
        undoChip = chip
        Task {
            try? await Task.sleep(for: .seconds(Tokens.Hold.undoChip))
            if undoChip?.id == chip.id { undoChip = nil }
        }
    }

    func undo() async {
        guard let chip = undoChip else { return }
        undoChip = nil
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

    func toggle(_ task: BlinkItem, offeringUndo: Bool = true) async {
        var changed = task
        changed.status = task.status == .done ? .open : .done
        edit(changed)
        if offeringUndo && changed.status == .done {
            offerUndo("Done: \(task.title)") { [weak self] in await self?.reopen(task.id) }
        }
        await save(task.id)
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
        // 120 days covers a long streak's rules and "kept N of 7".
        let since = HabitDay.key(Calendar.current.date(byAdding: .day, value: -120, to: habitToday) ?? habitToday)
        guard let list = try? await server.habits(), let logs = try? await server.habitLogs(since: since) else { return }
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
        quickReplies = ["Keep my usual day", "Add something", "Nothing else, I'm set"]
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
    func ask(_ text: String, context: String? = nil) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let server, !message.isEmpty, !thinking else { return }
        quickReplies = []
        let history = chat
        chat.append(.init(role: .user, text: message))
        thinking = true
        defer { thinking = false }
        do {
            // Open reminders go along so Claude can propose finishing or deleting one (they stay on the Mac otherwise).
            let reminders = calendarAccess == .granted ? await calendarReader.openReminders() : []
            let answer = try await server.chat(message, history: history, timeZone: TimeZone.current.identifier,
                                               reminders: reminders, context: context)
            chat.append(.init(role: .assistant, text: answer.reply))
            if answer.proposed > 0 { await loadActions() }
        } catch let problem as BlinkServer.ChatProblem {
            chat.append(.init(role: .assistant, text: problem.message))
        } catch {
            chat.append(.init(role: .assistant, text: "Can't reach your server right now. Try again in a moment."))
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
        }
        if let saved = try? await server.voiceProfile() { voice = saved }
    }

    /// Asks Claude for one draft per platform; they arrive saved, at the top of the list.
    func draft(idea: String, platforms: [ContentPiece.Platform]) async -> Bool {
        guard let server, !drafting else { return false }
        drafting = true
        defer { drafting = false }
        contentProblem = nil
        do {
            try await server.draftContent(idea: idea, platforms: platforms)
            await loadContent()
            return true
        } catch let problem as BlinkServer.ChatProblem {
            contentProblem = problem.message
        } catch {
            contentProblem = "Can't reach your server right now. Try again in a moment."
        }
        return false
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
               now.status == piece.status { contentUnsaved.remove(id) }
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
        if status == .archived { content.removeAll { $0.id == piece.id } }
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

    var readyToPost: [ContentPiece] { content.filter { $0.status == .approved } }

    func model(for feature: String) -> AIModel {
        AIModel.all.first { $0.id == modelPrefs[feature] } ?? AIModel.all.first { $0.id == AIModel.defaultID }!
    }

    func setModel(_ id: String, for feature: String) async {
        guard let server else { return }
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
        do {
            try await server.save(space)
        } catch {
            if let i = spaces.firstIndex(where: { $0.id == space.id }) { spaces[i] = before }
            saveProblem = "Couldn't save the space. Check your connection and try again."
        }
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
        if offeringUndo { offerUndo("Done: \(reminder.title)") { [weak self] in await self?.reopen(reminder) } }
        await writeReminder { try await calendarReader.updateReminder(id: reminder.id, completed: true) }
    }

    func rename(_ reminder: AgendaReminder, to title: String) async {
        await writeReminder { try await calendarReader.updateReminder(id: reminder.id, title: title) }
    }

    func setDue(_ reminder: AgendaReminder, to due: Date?) async {
        await writeReminder { try await calendarReader.setReminderDue(id: reminder.id, due: due) }
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
        // One at a time: overlapping uploads could land out of order and bring back a deleted event.
        // Changes that arrive meanwhile get exactly one more pass.
        guard !reloading else { reloadAgain = true; return }
        reloading = true
        defer { reloading = false }
        repeat {
            reloadAgain = false
            let window = CalendarReader.window(from: .now)
            agenda = await calendarReader.agenda(in: window)
            allReminders = await calendarReader.openReminders() // the Tasks page shows every open reminder
            guard let server, email != nil else { continue }
            // The device is the source of truth; a failed upload is simply retried by the next reload.
            try? await server.uploadCalendar(agenda.events, window: window)
        } while reloadAgain
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
