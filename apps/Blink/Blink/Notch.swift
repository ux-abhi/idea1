// © Pexilim
#if os(macOS)
import AppKit
import Carbon.HIToolbox
import BlinkKit
import SwiftUI

/// The notch's three levels (ARCHITECTURE §5) and what they show.
@Observable
final class NotchModel {
    enum Level { case rest, peek, open }

    var level = Level.rest
    var mood = Mood.idle
    /// The pointer is over the notch: a soft blue glow rises from its bottom edge, like the app icon.
    var hovering = false
    /// The hardware notch, measured from the screen.
    var notchSize = CGSize(width: 200, height: 32)
    /// The glance content's measured height; the open shape fits it.
    var glanceHeight: CGFloat = 60
    static let openWidth: CGFloat = 420
    static let chatWidth: CGFloat = 500
    /// The chat's input splits off below the notch as its own bubble.
    /// Wider than the goo's merge distance, so at rest the bubble sits cleanly apart from the notch.
    static let inputGap: CGFloat = 22
    static let inputHeight: CGFloat = 46
    var inputOut: Bool { level == .open && chatting }
    /// The tallest the open shape can get; the panel is sized for it.
    static let maxGlanceHeight: CGFloat = 240
    /// The morning brief is showing.
    var briefing = false
    /// The open notch shows the chat (⌃⌥Space) instead of the glance.
    var chatting = false
    /// The evening nudge is showing ("Plan tomorrow?").
    var evening = false
    /// The open notch shows the clipboard history (⌃⌥V).
    var clipboarding = false
    /// The open notch shows search (⌃⌥K): notes, tasks, reminders, posts and spaces.
    var searching = false
    /// The open notch shows the /meet invite card.
    var meeting = false
    /// What's typed in the chat bubble; the panel above previews a "/" command from it.
    var input = ""
    /// A one-line announcement for the peek (e.g. important mail), instead of the day's status line.
    var peekNote: String?
    /// After the evening check-in the eyes stay Sleepy until the owner's wake time.
    var sleepyUntil: Date?

    /// Ears beside the camera stay slim at rest so long app menus are never covered (§36.2).
    static let ear: CGFloat = 24
    /// While a timer runs the ears widen so the right one can show the countdown.
    static let timerEar: CGFloat = 58
    var timerShown = false
    var earWidth: CGFloat { timerShown ? Self.timerEar : Self.ear }

    func size(for level: Level) -> CGSize {
        let rest = CGSize(width: notchSize.width + 2 * earWidth, height: notchSize.height)
        switch level {
        case .rest: return rest
        case .peek: return CGSize(width: max(rest.width, 320), height: rest.height + 36)
        // Eyes row, 8 pt gap, the measured content, 20 pt to breathe at the bottom.
        case .open: return CGSize(width: max(rest.width, chatting || searching || meeting ? Self.chatWidth : Self.openWidth),
                                  height: rest.height + 8 + min(glanceHeight, Self.maxGlanceHeight) + 20)
        }
    }
}

/// Borderless, transparent, non-activating; key only after a click on the notch (§36.1).
final class NotchPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}

/// A click on the notch should act even though the panel isn't key.
final class NotchHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the notch panel: placement, hover, open and close.
final class NotchController {
    private let model = NotchModel()
    private let app: AppModel
    private let clipboard: ClipboardStore
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    /// Each cue speaks once per event (§7: one reaction per event, never nags).
    private var spoken: [AgendaEvent.ID: Set<String>] = [:]
    private var cueWake: Task<Void, Never>?
    private var autoClose: Task<Void, Never>?
    private var autoPeeking = false
    private var autoOpened = false
    private var hotkeys: [GlobalHotkey] = []
    private var eveningShown: String? // habit day the evening nudge last appeared
    private var spendNudgeShown: String? // day the "anything I missed?" money nudge last appeared
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(app: AppModel, clipboard: ClipboardStore) {
        self.app = app
        self.clipboard = clipboard
        place()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved),
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { moved($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // Not while Touch ID or the server works on a meeting: its sheet's buttons count as "outside".
                if self?.model.level == .open, self?.app.creatingMeet == false { self?.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.model.level == .open else { return event }
                if event.keyCode == 53 { // Esc
                    self.close()
                    return nil
                }
                // ⌘⏎ approves; never a bare ⏎ (§36.2).
                // Not on the /meet card, where ⌘⏎ is Create & Invite.
                if event.keyCode == 36, event.modifierFlags.contains(.command), !self.app.locked, !self.model.meeting,
                   let first = self.app.pending.first {
                    Task { await self.app.approve(first) }
                    return nil
                }
                return event
            },
        ].compactMap { $0 }

        // Re-plan the cues whenever the agenda changes; sleep until the next cue in between.
        Task { [weak self] in
            guard let app = self?.app else { return }
            // Calendar, reminders and tasks all feed the cues.
            for await _ in Observations({ (app.agenda, app.items) }) { self?.scheduleCues() }
        }
        // The owner can let screenshots and recordings show the notch (for a demo); hidden otherwise.
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await shown in Observations({ app.notchInRecordings }) { self?.panel?.sharingType = shown ? .readOnly : .none }
        }
        // Locking closes the notch, so nothing shows past "Blink is locked".
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await locked in Observations({ app.locked }) where locked {
                if self?.model.level == .open { self?.close() }
            }
        }
        hotkeys = [
            GlobalHotkey(id: 1, keyCode: kVK_Space) { [weak self] in self?.toggleChat() },
            GlobalHotkey(id: 2, keyCode: kVK_ANSI_V) { [weak self] in self?.toggleClipboard() },
            GlobalHotkey(id: 3, keyCode: kVK_ANSI_K) { [weak self] in self?.toggleSearch() },
        ]

        // Thinking while Claude works, then Done for 2 s (§7).
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await thinking in Observations({ app.thinking }) {
                guard let self else { return }
                if thinking {
                    self.model.mood = .thinking
                } else if self.model.mood == .thinking {
                    self.model.mood = .done
                    try? await Task.sleep(for: .seconds(Tokens.Hold.done))
                    if self.model.mood == .done { self.evaluateCue() }
                }
            }
        }

        // Something ticked off (here or in the window): Done ∩∩ for a moment, then back to what's next.
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await chip in Observations({ app.undoChip?.id }) where chip != nil {
                guard let self else { return }
                guard self.model.mood != .thinking else { continue }
                self.model.mood = .done
                try? await Task.sleep(for: .seconds(Tokens.Hold.done))
                if self.model.mood == .done { self.evaluateCue() }
            }
        }

        // Timer running: widen the ears for the countdown. Timer ended: open with Done eyes (the chime already played).
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await running in Observations({ app.timer != nil }) {
                guard let self else { return }
                withAnimation(self.reduceMotion ? nil : Tokens.Motion.peek.animation) { self.model.timerShown = running }
            }
        }
        Task { [weak self] in
            guard let app = self?.app else { return }
            var seen = app.timersEnded
            for await count in Observations({ app.timersEnded }) where count != seen {
                seen = count
                guard let self else { return }
                self.model.mood = .done
                if self.model.level != .open { self.show(.open, closingAfter: 60) }
                AccessibilityNotification.Announcement("\(app.finishedTimer?.label ?? "Timer") done").post()
                try? await Task.sleep(for: .seconds(Tokens.Hold.done))
                self.evaluateCue()
            }
        }

        // Evening check-in finished: Sleepy until the wake time that ends this habit day (§7, §9.4).
        Task { [weak self] in
            guard let app = self?.app else { return }
            var seen = app.eveningsDone
            for await count in Observations({ app.eveningsDone }) where count != seen {
                seen = count
                guard let self else { return }
                let cal = Calendar.current
                let nextDay = cal.date(byAdding: .day, value: 1, to: app.habitToday) ?? .now
                self.model.sleepyUntil = cal.date(bySettingHour: app.wake.hour, minute: app.wake.minute, second: 0, of: nextDay)
                self.model.evening = false
                if self.model.level != .rest { self.close() }
                self.scheduleCues()
            }
        }

        // Important mail (P1, §8): the eyes go Important and the notch peeks with who and why, once per message.
        Task { [weak self] in
            guard let app = self?.app else { return }
            var announced = Set(app.importantMail.map(\.id))
            for await fresh in Observations({ app.importantMail.filter { $0.status == .new }.map(\.id) }) {
                guard let self else { return }
                let new = fresh.filter { !announced.contains($0) }
                announced.formUnion(fresh)
                guard let first = new.first, let message = app.importantMail.first(where: { $0.id == first }),
                      self.model.level == .rest else { continue }
                self.model.mood = .important
                self.model.peekNote = new.count == 1 ? "✉︎ \(message.sender): \(message.reason.isEmpty ? message.subject : message.reason)"
                                                     : "✉︎ \(new.count) important emails"
                self.show(.peek, closingAfter: 8)
                try? await Task.sleep(for: .seconds(8))
                self.model.peekNote = nil
                if self.model.mood == .important { self.evaluateCue() }
            }
        }

        // Background work finished (ideas, drafts, week plan, page read): say so in the notch, so the owner needn't
        // open the window. If the notch is open right then, results wait and peek one by one as soon as it closes.
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await notice in Observations({ app.notice }) {
                guard let self, let notice else { continue }
                self.notices.append(notice)
                self.showNotices()
            }
        }

        // The on-device model prepared a meeting: show its /meet card in the open notch.
        Task { [weak self] in
            guard let app = self?.app else { return }
            for await draft in Observations({ app.meetDraft }) {
                guard let self else { return }
                guard draft != nil, !self.model.meeting else { continue }
                self.model.chatting = false
                self.model.meeting = true
                if self.model.level != .open { self.open() }
            }
        }

        // 7 / 30 / 100-day habit streaks: Celebrate for 3 s, then back to whatever the cues say (§7).
        Task { [weak self] in
            guard let app = self?.app else { return }
            var seen = app.celebrations
            for await count in Observations({ app.celebrations }) where count != seen {
                seen = count
                self?.model.mood = .celebrate
                try? await Task.sleep(for: .seconds(Tokens.Hold.celebrate))
                self?.evaluateCue()
            }
        }
        // Started at login: the first unlock already happened, so the brief comes now (once a day, like on unlock). Only in
        // the morning: Blink opened at 15:00 (an update, a restart) shouldn't say good morning.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3)) // let the window and the calendar settle first
            guard Calendar.current.component(.hour, from: .now) < 12 else { return }
            self?.morningBriefIfFirstToday()
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.morningBriefIfFirstToday() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = Task { await self?.app.reloadAgenda(); self?.scheduleCues() }
            }
        }
    }

    // MARK: Speaking first

    /// Once a day from 10:00: how many emails wait for a reply (opening the notch lists them, with Review).
    private func replyDigest() {
        let shown = UserDefaults.standard.string(forKey: "replyDigestShown")
        let waiting = app.awaitingReply.count
        guard ReplyDigest.due(now: .now, shownOn: shown, waiting: waiting), !model.briefing else { return }
        UserDefaults.standard.set(HabitDay.key(.now), forKey: "replyDigestShown")
        let text = ReplyDigest.text(waiting)
        model.mood = .headsUp
        model.peekNote = text
        show(.peek, closingAfter: 8)
        AccessibilityNotification.Announcement(text).post()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.model.peekNote == text { self?.model.peekNote = nil }
            self?.evaluateCue()
        }
    }

    /// The money nudge comes this long before the evening check-in (20:45 with the default 21:30, §21).
    private static let spendLead: TimeInterval = 45 * 60

    /// Once a day, in the 45 minutes before the evening check-in, if the owner keeps track of money: what was already
    /// caught today (Apple Pay, receipts, typed), and a reminder that /spent adds the rest.
    private func spendNudge(day: String) {
        let opens = EveningCheck.opens(now: .now, evening: app.evening, wake: app.wake)
        let usesMoney = !app.accounts.isEmpty || !app.captureTokens.isEmpty || !app.spends.isEmpty
        guard usesMoney, spendNudgeShown != day, Date.now >= opens.addingTimeInterval(-Self.spendLead), Date.now < opens else { return }
        // Apple Pay taps and receipts since the last sync are on the server: fetch them before saying what's caught.
        // Marked shown only once it really shows, so a peek or an open notch at that moment just delays it.
        Task { [weak self] in
            await self?.app.loadMoney()
            self?.showSpendNudge(day: day)
        }
    }

    private func showSpendNudge(day: String) {
        guard model.level == .rest, spendNudgeShown != day else { return }
        spendNudgeShown = day
        // The habit day, like the once-a-day guard: past midnight, "today" is still the evening before.
        let today = app.spends.filter { $0.spentOn == day }
        let total = today.reduce(Decimal.zero) { $0 + $1.amount }
        let text = today.isEmpty
            ? "Spent anything today? Type /spent 8 lunch"
            : "Today \(total.formatted(.currency(code: MoneyMath.currency))): \(today.prefix(3).map(\.note).joined(separator: ", ")). Missed any? /spent"
        model.mood = .headsUp
        model.peekNote = text
        show(.peek, closingAfter: 10)
        AccessibilityNotification.Announcement(text).post()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if self?.model.peekNote == text { self?.model.peekNote = nil }
            self?.evaluateCue() // back to the eyes the hour calls for
        }
    }

    private func scheduleCues() {
        cueWake?.cancel()
        // Done meetings count as known, so Undo right after Done doesn't announce the meeting again.
        // Due items are spoken as "<id>@<due>" (MeetingCue.id), so keep those keys, not the plain ids.
        let ids = Set(app.agenda.events.map(\.id) + app.doneMeetings
                      + app.agenda.dueItems(adding: app.dueTasks).map { "\($0.id)@\(Int($0.due.timeIntervalSince1970))" })
        spoken = spoken.filter { ids.contains($0.key) } // forget meetings that are gone
        evaluateCue()
        let eveningOpens = EveningCheck.opens(now: .now, evening: app.evening, wake: app.wake)
        let spendAt = eveningOpens.addingTimeInterval(-Self.spendLead)
        let candidates = [app.agenda.nextCueChange(after: .now, tasks: app.dueTasks),
                          eveningOpens > .now ? eveningOpens : nil, spendAt > .now ? spendAt : nil,
                          ReplyDigest.nextTime(after: .now), model.sleepyUntil].compactMap { $0 }
        guard let next = candidates.min() else { return }
        cueWake = Task { [weak self] in
            // ContinuousClock keeps counting while the Mac sleeps, so an overdue cue fires on wake.
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.5))
            guard !Task.isCancelled else { return }
            self?.scheduleCues()
        }
    }

    /// T−10 peeks once with mint eyes; T−3 opens the card once without taking focus (§9.3, §36.2).
    /// shortcut: ignores screen sharing and full-screen apps (§8 asks to hold pop-outs); add with display contexts.
    private func evaluateCue() {
        let cue = app.agenda.cue(now: .now, tasks: app.dueTasks)
        if let until = model.sleepyUntil, Date.now >= until { model.sleepyUntil = nil }
        if !model.briefing {
            model.mood = cue != nil ? .headsUp
                : model.sleepyUntil != nil ? .sleepy
                : app.eveningDue ? .evening
                : .idle
        }
        // 21:30: one evening nudge per day (§9.4), only when nothing else is speaking.
        let day = HabitDay.key(app.habitToday)
        if cue == nil, app.eveningDue, eveningShown != day, model.level == .rest {
            eveningShown = day
            model.evening = true
            show(.peek, closingAfter: 10)
            AccessibilityNotification.Announcement("Plan tomorrow?").post()
        }
        if cue == nil, model.level == .rest { spendNudge(day: day); replyDigest() }
        guard let cue else {
            if autoOpened && model.level == .open { close() }
            return
        }
        let kind = switch cue {
        case .headsUp, .dueSoon: "headsUp"
        case .imminent: "imminent"
        case .due: "due"
        }
        guard spoken[cue.id, default: []].insert(kind).inserted else { return }
        switch cue {
        case .headsUp, .dueSoon: if model.level == .rest { show(.peek, closingAfter: 8) }
        // P0: open without focus; closes 5 min later or on a click elsewhere.
        case .imminent, .due: if model.level != .open { show(.open, closingAfter: nil) }
        }
        // Only P0/P1 speak (§36.2); the notch itself is out of VoiceOver's reach.
        AccessibilityNotification.Announcement(app.agenda.statusLine(now: .now, tasks: app.dueTasks)).post()
    }

    /// First unlock of the day: Good morning eyes and today's brief (§9.2).
    /// Fires on screen unlock, and once when Blink starts (at login, if the owner turned that on).
    private func morningBriefIfFirstToday() {
        guard app.calendarAccess == .granted else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if let last = UserDefaults.standard.object(forKey: "lastBrief") as? Date, last >= today { return }
        UserDefaults.standard.set(Date.now, forKey: "lastBrief")
        Task {
            await app.reloadAgenda()
            model.sleepyUntil = nil
            model.briefing = true
            model.mood = .morning
            show(.open, closingAfter: 60)
            AccessibilityNotification.Announcement("Good morning. \(app.agenda.briefLine(now: .now))").post()
        }
    }

    /// Opens a level by itself: never key, so typing stays in the user's app.
    private func show(_ level: NotchModel.Level, closingAfter seconds: Double?) {
        set(level)
        autoPeeking = level == .peek
        autoOpened = level == .open
        autoClose?.cancel()
        guard let seconds else { return }
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.model.level == level,
                  !self.shapeRect().contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
    }

    /// Puts the panel over the built-in display's notch, sized for the largest level. With no notch anywhere (an external
    /// display, or the lid closed), Blink draws its own small black notch at the top of the main screen's menu bar.
    /// shortcut: one screen at a time (the notched one, else the menu bar screen); follow the active screen when asked.
    private func place() {
        let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        guard let screen = notched ?? NSScreen.screens.first else {
            panel?.orderOut(nil)
            return
        }
        if notched != nil {
            let side = (screen.auxiliaryTopLeftArea?.width ?? 0) + (screen.auxiliaryTopRightArea?.width ?? 0)
            model.notchSize = CGSize(width: screen.frame.width - side, height: screen.safeAreaInsets.top)
        } else {
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            model.notchSize = CGSize(width: Self.drawnNotchWidth, height: menuBar)
        }
        let size = CGSize(width: max(model.size(for: .rest).width, NotchModel.chatWidth),
                          height: model.notchSize.height + 8 + NotchModel.maxGlanceHeight + 20
                              + NotchModel.inputGap + NotchModel.inputHeight + 12)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// The notch Blink draws on screens without one: about a MacBook notch's width, over the empty middle of the menu bar.
    private static let drawnNotchWidth: CGFloat = 185

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = app.notchInRecordings ? .readOnly : .none // hidden from screen capture and sharing (§36.1) unless the owner allows it
        panel.contentView = NotchHostingView(rootView: NotchView(model: model, app: app, clipboard: clipboard,
                                                                      open: { [weak self] in self?.openChat() },
                                                                      plan: { [weak self] in self?.planTomorrow() },
                                                                      close: { [weak self] in self?.close() }))
        return panel
    }

    /// The shape's current rectangle in screen coordinates.
    private func shapeRect() -> NSRect {
        guard let frame = panel?.frame else { return .zero }
        let size = model.size(for: model.level)
        var rect = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        if model.inputOut {
            rect = rect.union(NSRect(x: rect.minX, y: rect.minY - NotchModel.inputGap - NotchModel.inputHeight,
                                     width: rect.width, height: NotchModel.inputGap + NotchModel.inputHeight))
        }
        return rect
    }

    /// Clicks pass through everywhere except the shape; hover peeks after 150 ms and closes 350 ms after leaving (§36.2).
    /// shortcut: fast pointer passes aren't filtered (only the 150 ms delay) and this has no test; add both if peeks fire by accident.
    private func pointerMoved() {
        // With a hidden rest style there is nothing to hover at rest.
        let restVisible = model.level != .rest || RestStyle.current == .ears
        let inside = restVisible && shapeRect().contains(NSEvent.mouseLocation)
        panel?.ignoresMouseEvents = !inside
        if model.hovering != inside { model.hovering = inside }
        if inside {
            leaveTask?.cancel()
            leaveTask = nil
            guard model.level == .rest, hoverTask == nil else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Tokens.Motion.hoverIntentIn))
                guard let self, !Task.isCancelled, self.model.level == .rest else { return }
                self.set(.peek)
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
            guard model.level == .peek, !autoPeeking, leaveTask == nil else { return }
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Tokens.Motion.hoverGraceOut))
                guard let self, !Task.isCancelled else { return }
                self.leaveTask = nil
                if self.model.level == .peek { self.set(.rest) }
            }
        }
    }

    /// ⌃⌥Space or "Ask Blink…": opens the chat with the keyboard in it; again closes it.
    /// ⌃⌥V or "Clipboard…": the history with the keyboard in its search field; again closes it.
    func toggleClipboard() {
        guard !showLockInstead() else { return }
        if model.level == .open && model.clipboarding { close(); return }
        model.chatting = false
        model.searching = false
        model.meeting = false
        model.clipboarding = true
        if model.level == .open, let panel {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            open()
        }
    }

    /// ⌃⌥K or "Search…": search with the keyboard in it; again closes it.
    func toggleSearch() {
        guard !showLockInstead() else { return }
        if model.level == .open && model.searching { close(); return }
        model.chatting = false
        model.clipboarding = false
        model.meeting = false
        model.searching = true
        if model.level == .open, let panel {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            open()
        }
    }

    func toggleChat() {
        guard !showLockInstead() else { return }
        if model.level == .open && model.chatting { close(); return }
        model.clipboarding = false
        model.searching = false
        model.meeting = false
        model.chatting = true
        if model.level == .open, let panel {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            open()
        }
    }

    /// A click on the notch: the chat, with the keyboard in its box (the day shows above it until something is asked).
    /// Already open on the day view: switches to the chat. Cards like the Meet invite or the clipboard stay as they are.
    func openChat() {
        guard !showLockInstead(), !model.meeting, !model.clipboarding, !model.searching else { return }
        if model.level == .open && model.chatting { return }
        model.chatting = true
        if model.level == .open, let panel {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            open()
        }
    }

    func open() {
        guard !showLockInstead(), model.level != .open, let panel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        set(.open)
        Task { await app.loadActions() }
        panel.allowsKey = true
        panel.makeKey() // for Esc; the panel never activates Blink
    }

    /// Evening card's "Plan with Blink": switch the open notch to the chat and ask Claude for tomorrow's plan.
    func planTomorrow() {
        model.evening = false
        if !(model.level == .open && model.chatting) { toggleChat() }
        Task { await app.planTomorrow() }
    }

    /// While Blink is locked the notch stays shut; the window comes forward with its unlock prompt instead.
    private func showLockInstead() -> Bool {
        guard app.locked else { return false }
        app.showWindow()
        return true
    }

    /// Finished jobs not yet shown (they arrived while the notch was open, or during another notice's peek).
    private var notices: [AppModel.Notice] = []
    private var showingNotices = false

    /// Peeks each waiting notice in turn; stops while the owner has the notch open (close() picks up the rest).
    private func showNotices() {
        guard !showingNotices else { return }
        showingNotices = true
        Task { [weak self] in
            while let self, self.model.level != .open, !self.notices.isEmpty {
                await self.announce(self.notices.removeFirst())
            }
            self?.showingNotices = false
        }
    }

    /// Peeks with a finished job ("💡 6 post ideas ready"), Done eyes (or Concerned when it failed), for 6 seconds.
    private func announce(_ notice: AppModel.Notice) async {
        model.mood = notice.failed ? .concerned : .done
        model.peekNote = notice.text
        show(.peek, closingAfter: 6)
        AccessibilityNotification.Announcement(notice.text).post()
        try? await Task.sleep(for: .seconds(6))
        if model.peekNote == notice.text { model.peekNote = nil }
        evaluateCue()
    }

    func close() {
        guard let panel else { return }
        autoClose?.cancel()
        set(.rest)
        // Finished while the notch was open: say it now, once it has closed.
        if !notices.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.showNotices()
            }
        }
        model.chatting = false
        model.clipboarding = false
        model.searching = false
        model.meeting = false
        app.meetDraft = nil
        model.evening = false
        panel.allowsKey = false
        // Hand the keyboard back to the app that had it (§36.2).
        if let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
        previousApp = nil
        pointerMoved()
    }

    private func set(_ level: NotchModel.Level) {
        // The app lock covers the notch too: cues and the morning brief can't open it over the lock (§36.5).
        if level == .open && app.locked { return }
        let m = Tokens.Motion.self
        let spring = switch level {
        case .rest: m.close
        case .peek: m.peek
        case .open: m.open
        }
        // Reduce Motion: the shape snaps and only the content fades (tokens: spring rm).
        withAnimation(reduceMotion ? nil : spring.animation) {
            model.level = level
        }
        if level != .peek { autoPeeking = false }
        if level != .open { autoOpened = false }
        // The shape changed under a still pointer: no glow on a notch the pointer has left.
        if model.hovering && !shapeRect().contains(NSEvent.mouseLocation) { model.hovering = false }
        if level == .rest && model.briefing {
            model.briefing = false // brief seen: Morning → Idle (§7)
            evaluateCue()
        }
    }
}

struct NotchView: View {
    let model: NotchModel
    let app: AppModel
    let clipboard: ClipboardStore
    let open: () -> Void
    let plan: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(RestStyle.key) private var restStyle = RestStyle.ears

    var body: some View {
        // Once a minute, never per frame: keeps the countdown current at ~0 CPU.
        TimelineView(.everyMinute) { context in
            let statusLine = app.agenda.statusLine(now: context.date, tasks: app.dueTasks)
            shape(statusLine: statusLine, now: context.date)
                // A hidden copy keeps the glance's real height current, so the shape opens straight to the right size.
                .background(alignment: .top) {
                    glance(statusLine: statusLine, now: context.date)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: model.size(for: .open).width)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { model.glanceHeight = $0 }
                }
        }
    }

    @ViewBuilder
    private func glance(statusLine: String, now: Date) -> some View {
        if model.meeting, let draft = app.meetDraft {
            MeetPanel(app: app, done: close, shown: draft)
        } else if model.chatting && app.chat.isEmpty && model.input.isEmpty && app.ideas.isEmpty && !app.drafting && !app.thinkingOfIdeas && !app.thinking {
            // Clicked open with nothing typed yet: the day, with the box below ready for a question or "remind me to…".
            GlanceView(app: app, statusLine: statusLine, agenda: app.agenda, tasks: app.dueTasks, access: app.calendarAccess, now: now,
                       briefing: model.briefing, done: close,
                       card: app.pending.first.map { CardView(action: $0, count: app.pending.count, problem: app.actionProblem, app: app) })
        } else if model.chatting {
            ChatPanel(app: app, input: model.input, pick: { [model] in model.input = $0 }, today: { [model] in model.chatting = false })
        } else if model.clipboarding {
            ClipboardPanel(store: clipboard, done: close)
        } else if model.searching {
            SearchPanel(app: app, done: close)
        } else if app.timer != nil || app.finishedTimer != nil {
            TimerCard(app: app)
        } else if model.evening || app.eveningDue {
            EveningView(app: app, plan: plan)
        } else {
            GlanceView(app: app, statusLine: statusLine, agenda: app.agenda, tasks: app.dueTasks, access: app.calendarAccess, now: now,
                       briefing: model.briefing, done: close,
                       card: app.pending.first.map { CardView(action: $0, count: app.pending.count, problem: app.actionProblem, app: app) })
        }
    }

    private func shape(statusLine: String, now: Date) -> some View {
        let size = model.size(for: model.level)
        let radius = model.level == .rest ? Tokens.Radius.notchRest : Tokens.Radius.notchOpen
        return VStack(spacing: 8) {
            let timerEars = app.timer != nil && model.level != .open && model.mood.letsTimerShow
            ZStack {
                // A running timer takes both ears: the eyes close to a line and fade, then the ring and clock come in.
                BlinkEyes(mood: model.mood, notchGap: model.notchSize.width)
                    .scaleEffect(y: timerEars && !reduceMotion ? 0.08 : 1)
                    .opacity(timerEars ? 0 : 1)
                    .animation(reduceMotion ? .easeInOut(duration: Tokens.Motion.eyeShapeReduceMotion.dur)
                                            : Tokens.Motion.eyeShape.animation, value: timerEars)
                if timerEars, let timer = app.timer {
                    TimerEars(timer: timer, gap: model.notchSize.width)
                        .transition(contentTransition)
                }
            }
                .frame(width: model.size(for: .rest).width, height: model.notchSize.height)
                .overlay(alignment: .bottomTrailing) {
                    // Waiting for you: a small dot in the right ear (§4).
                    if !app.pending.isEmpty {
                        Circle().fill(.orange).frame(width: 5, height: 5).padding(.trailing, 4).padding(.bottom, 5)
                    }
                }
                .accessibilityHidden(true)
            switch model.level {
            case .rest:
                EmptyView()
            case .peek:
                Text(model.peekNote ?? (model.evening ? "Plan tomorrow?" : statusLine))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .transition(contentTransition)
            case .open:
                glance(statusLine: statusLine, now: now)
                    .transition(contentTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            // notch.hardware: always pure black. The hover glow sits under the content, so text keeps its contrast.
            ZStack {
                Color.black
                HoverGlow(active: model.hovering && !app.thinking)
            }
        }
        .overlay {
            // Inside the notch only (tokens: glow.rule).
            ThinkingGlow(active: app.thinking && model.level == .open)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .contentShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Start Focus (25 min)") { app.startFocus() }
            Menu("Timer") {
                ForEach([5, 10, 15, 30, 60], id: \.self) { m in Button("\(m) min") { app.startTimer(minutes: Double(m)) } }
            }
            if app.timer != nil { Button("Stop Timer") { app.stopTimer() } }
            Divider()
            Button("Open Blink") {
                app.showWindow()
            }
            Button("Settings…") { app.openSettings() }
            Button("Quit Blink") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Blink")
        .accessibilityValue([
            app.timer.map { "\($0.label) \($0.isPaused ? "paused, " : "")\(FocusTimer.clock($0.remaining(now: now))) left" },
            statusLine,
            app.pending.isEmpty ? nil : "\(app.pending.count) waiting for you",
        ].compactMap(\.self).joined(separator: ". "))
        .accessibilityAction(named: "Open", open)
        .opacity(model.level == .rest && restStyle != .ears ? 0 : 1)
        // Behind the notch, so the droplet's hidden sliver never covers what the notch shows.
        .background(alignment: .top) {
            SplitInput(app: app, notch: model, progress: model.inputOut ? 1 : 0, notchBottom: size.height,
                       notchWidth: size.width, width: model.size(for: .open).width - 24)
                // Opening: the shape first, then the bubble pulls free with a little wobble. Closing: it tucks back in first.
                .animation(reduceMotion ? nil : (model.inputOut
                    ? .spring(response: 0.62, dampingFraction: 0.62).delay(Tokens.Motion.contentDelay)
                    : .spring(response: 0.34, dampingFraction: 0.92)), value: model.inputOut)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Content follows the shape: in after a short delay, out quickly before the shape closes (tokens: choreography).
    private var contentTransition: AnyTransition {
        let m = Tokens.Motion.self
        let move: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
        return .asymmetric(
            insertion: move.animation(m.content.animation.delay(m.contentDelay)),
            removal: .opacity.animation(.easeIn(duration: m.contentOut.dur))
        )
    }
}

/// Level 2: the brief or today's remaining events and reminders, with Join for an imminent meeting.
/// Not gated by the app lock yet; gate it when the Mac lock policy for the notch is decided (§36.5).
struct GlanceView: View {
    var app: AppModel?
    let statusLine: String
    let agenda: Agenda
    let tasks: [DueItem]
    let access: CalendarReader.Access
    let now: Date
    let briefing: Bool
    let done: () -> Void
    /// The first Ask-First card, shown above the agenda.
    let card: CardView?

    var body: some View {
        let events = Array(agenda.today(now: now).prefix(3))
        // Reminders and tasks due today, after the meetings; four lines at most.
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let due = Array(agenda.dueItems(adding: tasks).filter { $0.due < endOfToday }.prefix(max(0, 4 - events.count)))
        VStack(alignment: .leading, spacing: 8) {
            if let card {
                card
                Divider().overlay(.white.opacity(0.2))
            }
            Text(briefing ? "Good morning" : statusLine)
                .font(.title3.weight(.semibold))
            if briefing {
                Text(agenda.briefLine(now: now)).foregroundStyle(.white.opacity(0.7))
            }
            if let app {
                ForEach(app.importantMail.filter { $0.status != .drafted }.prefix(2)) { message in
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.badge").foregroundStyle(.red)
                        Text("\(message.sender): \(message.reason.isEmpty ? message.subject : message.reason)").lineLimit(1)
                            .onTapGesture { if let url = message.mailURL { NSWorkspace.shared.open(url); done() } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "Open in Apple Mail") { if let url = message.mailURL { NSWorkspace.shared.open(url); done() } }
                            .help("Open in Apple Mail")
                        Spacer(minLength: 8)
                        // The mail's first next step ("Add to Calendar"), else Draft when someone waits for an answer.
                        if let step = message.nextSteps.first {
                            let saved = app.savedSteps.contains("\(message.id)#0")
                            Button(saved ? "Added" : NextStepChips.verb(step.kind)) { Task { await app.save(step, from: message, index: 0) } }
                                .buttonStyle(.plain).foregroundStyle(saved ? .green : .mint)
                                .disabled(saved)
                                .help(NextStepChips.text(step))
                                .accessibilityLabel(saved ? "Added: \(step.title)" : "\(NextStepChips.verb(step.kind)): \(NextStepChips.text(step))")
                        } else if message.needsReply {
                            Button("Draft") { Task { await app.reviewReply(to: message, reuse: false) } }
                                .buttonStyle(.plain).foregroundStyle(.mint)
                                .disabled(app.draftingMail.contains(message.id))
                        }
                        Button("Clear") { Task { await app.finish([message]) } }
                            .help("Clear this mail from Blink. Anything you added from it stays.")
                            .buttonStyle(.plain).foregroundStyle(.mint)
                    }
                }
            }
            if let app {
                // Waiting for a reply, beyond the important ones shown above: one line, Review opens the Inbox.
                let shownImportant = Set(app.importantMail.filter { $0.status != .drafted }.prefix(2).map(\.id))
                let waiting = app.awaitingReply.filter { !shownImportant.contains($0.id) }
                if !waiting.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.mint)
                        Text(waiting.count == 1 ? "\(waiting[0].sender) is waiting for your reply" : "\(waiting.count) emails are waiting for your reply").lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Review") {
                            app.openPage = "inbox"
                            app.showWindow()
                            done()
                        }
                        .buttonStyle(.plain).foregroundStyle(.mint)
                    }
                    .accessibilityElement(children: .combine)
                }
                // Planned for today but not approved yet: a nudge to review it.
                ForEach(app.postsToday.filter { $0.status == .drafted }.prefix(1)) { piece in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                        Text("Today's post: \(piece.hook.isEmpty ? piece.idea : piece.hook)").lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Review") {
                            app.openPage = "content"
                            app.showWindow()
                            done()
                        }
                        .buttonStyle(.plain).foregroundStyle(.mint)
                    }
                }
            }
            if let app, !app.readyToPost.isEmpty {
                // Morning card (§3): approved posts waiting for you to put them out, postable from here.
                ForEach(app.readyToPost.prefix(2)) { piece in
                    HStack(spacing: 8) {
                        Image(systemName: "megaphone.fill").foregroundStyle(.orange)
                        Text("\(piece.platform.name): \(piece.hook.isEmpty ? piece.body : piece.hook)").lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Copy & Open") {
                            app.copyAndOpen(piece)
                            done()
                        }
                        .buttonStyle(.plain).foregroundStyle(.mint)
                    }
                }
                if app.readyToPost.count > 2 {
                    Button("\(app.readyToPost.count - 2) more ready in Content") {
                        app.openPage = "content"
                        app.showWindow()
                        done()
                    }
                    .buttonStyle(.plain).foregroundStyle(.mint)
                }
            }
            if access != .granted {
                Text("Your next meeting and today's reminders show here once Calendar is connected.")
                    .foregroundStyle(.white.opacity(0.7))
            } else if events.isEmpty && due.isEmpty && !briefing {
                Text("Nothing else on your calendar today.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(events) { event in
                HStack(spacing: 8) {
                    Text(event.start, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.mint) // mood.headsUp: time
                    Text(event.title).lineLimit(1)
                    if event.joinable(at: now) || event.start <= now { Spacer(minLength: 8) }
                    if event.joinable(at: now), let url = event.joinURL {
                        Button("Join") {
                            NSWorkspace.shared.open(url)
                            done()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    // Once it has started: the owner can say it's over, so the notch stops counting "started 16 min ago".
                    if event.start <= now, let app {
                        Button("Done") { app.finishMeeting(event) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Mark \(event.title) as done")
                            .accessibilityInputLabels(["Done", "Mark \(event.title) as done"])
                    }
                }
            }
            ForEach(due) { item in
                HStack(spacing: 8) {
                    Text(item.due, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(item.due < now ? .orange : .mint)
                    if let app {
                        Button { Task { await app.complete(id: item.id) } } label: { Image(systemName: "circle") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark \(item.title) as done")
                    }
                    Text(item.title).lineLimit(1)
                    if let app {
                        Spacer(minLength: 6)
                        Menu {
                            ForEach(Later.choices(now: now), id: \.title) { choice in
                                Button(choice.title) { Task { await app.moveLater(id: item.id, to: choice.date) } }
                            }
                        } label: { Image(systemName: "clock.arrow.circlepath") }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Later")
                            .accessibilityLabel("Later: \(item.title)")
                    }
                }
            }
            if let app { UndoChipRow(app: app) }
            if let app { TimerQuickStarts(app: app).padding(.top, 2) }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}
/// The conversation inside the notch: your question as a quiet line, Blink's answer as clear text, any card it
/// proposed. Typing happens in the bubble below (SplitInput).
struct ChatPanel: View {
    let app: AppModel
    /// What's being typed below; a "/" command (or plain words like "remind me to…") shows its preview here.
    var input = ""
    /// Fills the box (a tapped "/" suggestion).
    var pick: (String) -> Void = { _ in }
    /// Back to the day view.
    var today: () -> Void = {}

    private var commandShown: Bool {
        input.trimmingCharacters(in: .whitespaces).hasPrefix("/") || QuickCommand.parse(input) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UndoChipRow(app: app)
            // Chat needs a working AI key; say so here, where it's tried, with the way to fix it. "/" commands still work.
            if app.aiKeyMissing, !commandShown, let step = app.setupSteps.first(where: { $0.id == .aiKey }) {
                NeedsSetup(step: step, model: app)
            }
            if app.drafting || app.thinkingOfIdeas {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(app.drafting ? "Writing drafts…" : "Thinking of ideas…").foregroundStyle(.white.opacity(0.6))
                }
                .font(.callout)
            }
            if !app.ideas.isEmpty && !commandShown {
                NotchIdeas(app: app)
            } else if commandShown {
                CommandHint(input: input, pick: pick)
            } else if app.chat.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask Blink").font(.title3.weight(.semibold))
                    Text("“What's left today?” · “Plan my afternoon”")
                        .font(.callout).foregroundStyle(.white.opacity(0.55))
                    Text("Or just say it: “remind me to call Sam at 4pm” · “task send invoice friday” · “timer 10 min”")
                        .font(.callout).foregroundStyle(.white.opacity(0.55))
                }
            } else {
                if !app.thinking {
                    HStack {
                        Button("Today", systemImage: "chevron.left", action: today)
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.55))
                            .help("Back to your day")
                        Spacer()
                        Button("Clear") { app.clearChat() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.55))
                            .help("Clear this chat (/clear)")
                            .accessibilityLabel("Clear chat")
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(app.chat.suffix(6)) { turn in line(turn).id(turn.id) }
                            if app.thinking {
                                if let words = app.streaming, !words.isEmpty {
                                    line(.init(role: .assistant, text: words)).id("thinking")
                                } else {
                                    Text("Thinking…").font(.callout).foregroundStyle(.white.opacity(0.5)).id("thinking")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: app.chat.count) {
                        withAnimation { proxy.scrollTo(app.chat.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: app.streaming) { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
            if !app.quickReplies.isEmpty && !app.thinking {
                HStack(spacing: 6) {
                    ForEach(app.quickReplies, id: \.self) { reply in
                        Button(reply) { Task { await app.quickReply(reply) } }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.12), in: .capsule)
                    }
                }
            }
            if let card = app.pending.first {
                CardView(action: card, count: app.pending.count, problem: app.actionProblem, app: app)
                    .padding(12)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func line(_ turn: BlinkServer.ChatTurn) -> some View {
        if turn.role == .user {
            Label(turn.text, systemImage: "arrow.turn.down.right")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
        } else {
            Text(Self.markdown(turn.text))
                .font(.body)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }

    /// Claude writes light Markdown (bold, italics, links); show it formatted rather than as ** marks.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// /ideas in the notch: each idea with Write, which turns it into drafts in Content.
struct NotchIdeas: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ideas for your page").font(.callout.weight(.semibold))
                Spacer()
                Button("Clear") { Task { await app.clearIdeas() } }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(app.ideas) { idea in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(idea.platform.name) · \(idea.formatName)").font(.caption).foregroundStyle(.white.opacity(0.5))
                                Text(idea.title).font(.callout).lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Button("Write") { Task { await app.write(idea) } }
                                .buttonStyle(.plain).foregroundStyle(.mint)
                                .disabled(app.drafting)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .foregroundStyle(.white)
    }
}

/// "✓ Task added: Pay rent · Undo" for a few seconds after something is added or ticked off (tokens: hold.undoChip).
struct UndoChipRow: View {
    let app: AppModel

    var body: some View {
        if let chip = app.undoChip {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(chip.text).lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { Task { await app.undo() } }.buttonStyle(.plain).foregroundStyle(.mint)
            }
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: .capsule)
        }
    }
}

/// What a "/" command will do before Return: the parsed title and date, or the commands that match and an example.
struct CommandHint: View {
    let input: String
    /// Puts a command in the box when its row is clicked.
    var pick: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let command = QuickCommand.parse(input) {
                Label(title(command), systemImage: symbol(command))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(detail(command)).font(.callout).foregroundStyle(.white.opacity(0.7))
                Text("Return to do it now").font(.caption).foregroundStyle(.white.opacity(0.45))
            } else {
                let name = input.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace }.lowercased()
                let matches = QuickCommand.suggestions(for: input)
                let rows = matches.isEmpty ? QuickCommand.all.filter { $0.name == name } : matches
                if rows.isEmpty {
                    Text("No command “\(name)”. Try /task, /remind, /note, /timer or /focus.")
                        .font(.callout).foregroundStyle(.orange)
                }
                ForEach(rows, id: \.name) { row in
                    Button { pick(row.name + " ") } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(.callout.monospaced().weight(.semibold)).foregroundStyle(.mint)
                            Text("\(row.about), e.g. \(row.example)").font(.callout).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.name): \(row.about)")
                }
                if !matches.isEmpty { Text("Click one, or Tab to complete").font(.caption).foregroundStyle(.white.opacity(0.45)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain) // the rows are buttons
    }

    private func title(_ command: QuickCommand) -> String {
        switch command {
        case .task(let title, _): "Task: \(title)"
        case .remind(let title, _): "Reminder: \(title)"
        case .note(let title): "Note: \(title)"
        case .timer(let minutes): "Timer: \(minutes.formatted()) min"
        case .focus: "Focus: 25 min"
        case .post(let idea): "Post: \(idea)"
        case .ideas(let theme): theme.isEmpty ? "Ideas for your page" : "Ideas: \(theme)"
        case .spent(let text): "Spent: \(text)"
        case .clear: "Clear this chat"
        case .meet(let title, _, _): title.isEmpty ? "New Google Meet" : "Meet: \(title)"
        }
    }

    private func symbol(_ command: QuickCommand) -> String {
        switch command {
        case .task: "checkmark.circle"
        case .remind: "bell"
        case .note: "note.text"
        case .timer: "timer"
        case .focus: "brain.head.profile"
        case .post: "megaphone"
        case .ideas: "lightbulb"
        case .spent: "eurosign.circle"
        case .clear: "trash"
        case .meet: "video"
        }
    }

    private func detail(_ command: QuickCommand) -> String {
        switch command {
        case .task(_, let due), .remind(_, let due):
            guard let due else { return "No date. Add one at the end, like “tomorrow 9am” or “fri 4pm”." }
            return "Due \(due.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))"
        case .note: return "Starts a note you can finish in Blink › Notes."
        case .timer: return "Counts down in the notch, with one chime at the end."
        case .focus: return "Then a 5-minute break; a long break after every fourth."
        case .post: return "Drafts for your platforms from Content, saved there to edit and approve."
        case .ideas: return "Six ideas for your page; Write turns one into drafts."
        case .spent: return "Blink sorts each amount into a category and saves it to Money, with Undo."
        case .clear: return "Removes this conversation from this Mac. Cards waiting for your OK stay."
        case .meet(_, let start, let guests):
            let when = start.map { $0.formatted(.dateTime.weekday(.wide).day().month().hour().minute()) } ?? "the next half hour"
            return "Opens the invite card: \(when)\(guests.isEmpty ? "" : ", with \(guests.formatted())"). You check it, then Touch ID."
        }
    }
}

/// The input that splits off the notch like a droplet. A sliver of the notch's bottom and the bubble are drawn
/// blurred and then cut at an alpha threshold (the "gooey" metaball technique), so while they are close a smooth
/// liquid neck joins them and it pinches off by itself as the bubble moves away. `progress` 0 = inside the notch,
/// 1 = its own bubble below.
struct SplitInput: View, Animatable {
    let app: AppModel
    let notch: NotchModel
    var progress: Double
    let notchBottom: CGFloat
    let notchWidth: CGFloat
    let width: CGFloat
    @FocusState private var focused: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let goo: CGFloat = 9 // blur radius: shapes closer than about this merge

    var body: some View {
        let p = max(progress, 0) // may overshoot past 1 on the spring: that's the wobble
        // First a small round drop pulls down from the middle of the notch and pinches off; then it stretches wide.
        let drop: CGFloat = 0.55
        let stretch = p < drop ? 0 : min((p - drop) / (1 - drop), 1)
        let eased = 1 - pow(1 - stretch, 3)
        let dropSize = 26 + 14 * min(p / drop, 1)
        let w = dropSize + (width - dropSize) * eased
        let h = dropSize + (NotchModel.inputHeight - dropSize) * eased
        let start = notchBottom - h - 2 // fully tucked inside the notch's bottom edge
        let top = start + (NotchModel.inputGap + h + 2) * min(p / drop, 1) + max(p - 1, 0) * 30
        let canvasHeight = notchBottom + NotchModel.inputGap + NotchModel.inputHeight + 24

        ZStack(alignment: .top) {
            Canvas { context, size in
                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: Self.goo))
                context.drawLayer { layer in
                    let cx = size.width / 2
                    // Kept clear of the notch's rounded corners so nothing shows outside them.
                    let sliver = min(max(notchWidth - 2 * Tokens.Radius.notchOpen - 24, 60), 150) // pull from the middle
                    layer.fill(Path(CGRect(x: cx - sliver / 2, y: notchBottom - 40, width: sliver, height: 40)),
                               with: .color(.black))
                    layer.fill(Path(roundedRect: CGRect(x: cx - w / 2, y: top, width: w, height: h), cornerRadius: h / 2),
                               with: .color(.black))
                }
            }
            .frame(height: canvasHeight)

            // The crisp parts sit on the goo once the bubble is out.
            RoundedRectangle(cornerRadius: h / 2, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.2 : 0.1))
                .frame(width: w, height: h)
                .offset(y: top)
                .opacity(p > 0.9 ? 1 : 0)
            field
                .frame(width: w, height: h)
                .offset(y: top)
                .opacity(p > 0.8 ? min((p - 0.8) * 5, 1) : 0)
        }
        .frame(maxWidth: .infinity)
        .opacity(p > 0.01 ? 1 : 0)
        .allowsHitTesting(p > 0.9)
        .onChange(of: p > 0.9) { _, out in if out { focused = true } }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("Ask Blink, or “remind me to…”", text: Bindable(notch).input)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(send)
                // Tab finishes a command name: "/re" → "/remind ".
                .onKeyPress(.tab) {
                    guard let match = QuickCommand.suggestions(for: notch.input).first else { return .ignored }
                    notch.input = match.name + " "
                    return .handled
                }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
    }

    private var canSend: Bool {
        let text = notch.input.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("/") { return QuickCommand.parse(text) != nil } // the panel says what's still missing
        return !app.thinking && !text.isEmpty
    }

    private func send() {
        guard canSend else { return }
        let message = notch.input
        notch.input = ""
        if let command = QuickCommand.parse(message) {
            if case .meet = command { notch.chatting = false; notch.meeting = true } // the invite card takes the notch
            Task { await app.run(command) }
        } else {
            Task { await app.ask(message) }
        }
    }
}

/// Hovered: a soft blue glow rising from inside the bottom edge, like the app icon. It doesn't move, so it costs
/// nothing while shown; it only fades in and out.
struct HoverGlow: View {
    let active: Bool

    var body: some View {
        // A hint, not a light: well under the glow token, close to the edge.
        EllipticalGradient(colors: [.blue.opacity(Tokens.Glow.alpha * 0.4), .clear], center: .bottom, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .blur(radius: Tokens.Glow.blur)
            .opacity(active ? 1 : 0)
            .animation(.easeInOut(duration: Tokens.Motion.moodTint.dur), value: active)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// While Claude thinks: a soft blue and light-red glow inside the notch's bottom edge, drifting side to side.
/// 30 fps at most and fully paused otherwise (tokens: fps.ambient); still under Reduce Motion.
struct ThinkingGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Tokens.Motion.ambientFPS, paused: !active || reduceMotion)) { context in
            let drift = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 4) * 0.3
            LinearGradient(colors: [.blue, .red.opacity(0.6), .blue],
                           startPoint: UnitPoint(x: -0.3 + drift, y: 0.5), endPoint: UnitPoint(x: 1.3 + drift, y: 0.5))
                .frame(height: 30)
                .blur(radius: 16)
                .opacity(0.8)
                .offset(y: 14) // half of it below the edge, so it reads as light along the bottom
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The rest notch while a timer runs: the left ear drains a ring, the right ear rolls the clock.
/// Ticks once a second (digits roll, the ring steps), so nothing animates per frame between ticks.
struct TimerEars: View {
    let timer: FocusTimer
    let gap: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wound = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(now: context.date)
            let left = 1 - timer.progress(now: context.date)
            // Last minute of a running timer turns orange so the end never surprises you.
            let tint: Color = remaining <= 60 && !timer.isPaused ? .orange : timer.kind == .focus ? .mint : timer.kind == .timer ? .cyan : .green
            GeometryReader { geo in
                let ear = max((geo.size.width - gap) / 2, 0), h = geo.size.height
                HStack(spacing: gap) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: wound ? left : 0)
                            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if timer.isPaused {
                            Image(systemName: "pause.fill").font(.system(size: 6, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(width: h * 0.44, height: h * 0.44)
                    .frame(width: ear, height: h)

                    Text(FocusTimer.clock(remaining))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                        .animation(reduceMotion ? nil : Tokens.Motion.content.animation, value: Int(remaining.rounded(.up)))
                        .frame(width: ear, height: h)
                }
                .opacity(timer.isPaused ? 0.5 : 1)
                .animation(.easeInOut(duration: Tokens.Motion.moodTint.dur), value: tint)
            }
        }
        // The ring winds up once when the timer appears (tokens: ringTrim), then only steps.
        .onAppear { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6).delay(Tokens.Motion.contentDelay)) { wound = true } }
    }
}

/// Clipboard history in the notch: search, recent copies, click to copy back (then ⌘V where you want it).
/// ⌃⌥K: search everything from the notch; picking a result opens it in the Blink window.
struct SearchPanel: View {
    let app: AppModel
    let done: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = app.search(query)
        let current = min(selected, max(results.count - 1, 0))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search notes, tasks, reminders, posts and spaces", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if results.indices.contains(current) { open(results[current]) } }
                    .onKeyPress(.downArrow) { selected = min(current + 1, results.count - 1); return .handled }
                    .onKeyPress(.upArrow) { selected = max(current - 1, 0); return .handled }
                    .onChange(of: query) { selected = 0 }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Type a word from a note, task, reminder, post or space.").foregroundStyle(.white.opacity(0.55))
            } else if results.isEmpty {
                Text("Nothing matches “\(query)”.").foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                                Button { open(hit) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: hit.symbol).foregroundStyle(.white.opacity(0.55)).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(hit.title).lineLimit(1)
                                            Text(hit.detail).font(.caption).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(index == current ? Color.white.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(hit.title), \(hit.detail)")
                                .id(hit.id)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .onChange(of: current) { if results.indices.contains(current) { proxy.scrollTo(results[current].id) } }
                }
            }
            Text("↑↓ and Return to open in Blink · ⌘K in the window too").font(.caption).foregroundStyle(.white.opacity(0.4))
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .onAppear { focused = true }
    }

    /// Closes the notch (which hands focus back), then brings the Blink window forward on the result.
    private func open(_ hit: AppModel.SearchHit) {
        done()
        if let note = hit.noteID { app.focusNoteID = note }
        app.openPage = hit.pageKey
        Task {
            try? await Task.sleep(for: .milliseconds(80)) // after close() handed focus back to the previous app
            app.showWindow()
        }
    }
}

struct ClipboardPanel: View {
    let store: ClipboardStore
    let done: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool
    @AppStorage(ClipboardStore.pausedKey) private var paused = false

    var body: some View {
        let items = Array(store.history.search(query).prefix(30))
        let current = min(selected, max(items.count - 1, 0))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search clipboard", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if items.indices.contains(current) { pick(items[current]) } }
                    // ↑ ↓ move through the list, Return copies the highlighted one.
                    .onKeyPress(.downArrow) { selected = min(current + 1, items.count - 1); return .handled }
                    .onKeyPress(.upArrow) { selected = max(current - 1, 0); return .handled }
                    .onChange(of: query) { selected = 0 }
                if paused { Text("Paused").font(.caption).foregroundStyle(.orange) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))

            if items.isEmpty {
                Text(store.history.items.isEmpty ? "Things you copy appear here. Passwords from password managers are never kept."
                                                 : "Nothing matches.")
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item)
                                    .background(index == current ? Color.white.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .onChange(of: current) { if items.indices.contains(current) { proxy.scrollTo(items[current].id) } }
                }
            }
            HStack {
                Text("↑↓ and Return, click, or drag into any app").font(.caption).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button(paused ? "Resume" : "Pause") { paused.toggle() }.buttonStyle(.plain).font(.caption)
                Button("Clear") { store.clear() }.buttonStyle(.plain).font(.caption).foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .onAppear { focused = true }
    }

    private func row(_ item: ClipItem) -> some View {
        // Not a Button: a button swallows the mouse-down, so the row could never be dragged out.
        HStack(spacing: 10) {
                if item.kind == .image, let data = item.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 34, height: 24).clipShape(.rect(cornerRadius: 4))
                } else if item.kind == .file, let path = item.files?.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit().frame(width: 34, height: 24)
                } else {
                    Image(systemName: item.kind == .link ? "link" : item.rich != nil ? "doc.richtext" : "doc.plaintext")
                        .foregroundStyle(.white.opacity(0.5)).frame(width: 34)
                }
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.copiedAt, format: .relative(presentation: .numeric))
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(.rect)
        .onTapGesture { pick(item) }
        .onDrag { store.dragItem(item) }
        .contextMenu { Button("Remove", role: .destructive) { store.remove(item) } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.kind == .image ? "Image, \(item.text)" : item.text)
        .accessibilityHint("Copies it back to the clipboard. You can also drag it into any app.")
        .accessibilityAction { pick(item) }
    }

    private func pick(_ item: ClipItem) {
        store.copy(item)
        done() // focus goes back to the app you were in; press ⌘V there
    }
}

/// Quick starts at the bottom of the glance: Focus 25 and a few timers.
struct TimerQuickStarts: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer").foregroundStyle(.white.opacity(0.5))
            chip("Focus 25") { app.startFocus() }
            ForEach([5, 15], id: \.self) { m in chip("\(m) min") { app.startTimer(minutes: Double(m)) } }
        }
        .font(.caption)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.white.opacity(0.1), in: .capsule)
            .foregroundStyle(.white)
    }
}

/// The open notch while a timer runs: a big countdown, its progress, and Pause / +5 / Stop.
/// When one ends: "Focus done. Take 5?" with Start break / Skip.
struct TimerCard: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let timer = app.timer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = context.date
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(timer.label).font(.callout).foregroundStyle(.white.opacity(0.6))
                            if timer.kind == .focus || timer.kind == .shortBreak || timer.kind == .longBreak {
                                Text("round \(timer.round % 4 + 1) of 4").font(.caption).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            if timer.isPaused { Text("Paused").font(.caption).foregroundStyle(.orange) }
                        }
                        Text(FocusTimer.clock(timer.remaining(now: now)))
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                        ProgressView(value: timer.progress(now: now))
                            .tint(timer.kind == .focus ? .mint : .green)
                    }
                }
                HStack(spacing: 8) {
                    if timer.isPaused {
                        Button("Resume") { app.resumeTimer() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Pause") { app.pauseTimer() }.buttonStyle(.borderedProminent)
                    }
                    Button("+5 min") { app.addToTimer(minutes: 5) }
                    Button("Stop", role: .destructive) { app.stopTimer() }
                }
                .controlSize(.small)
            } else if let done = app.finishedTimer {
                Text(done.kind == .focus ? "Focus done" : done.kind == .timer ? "Time's up" : "Break's over")
                    .font(.title3.weight(.semibold))
                Text(done.kind == .focus ? "Nice work. Take \((done.next(now: .now)?.duration ?? 300) / 60, specifier: "%.0f") minutes?"
                     : done.kind == .timer ? "Your \(Int(done.duration / 60))-minute timer has finished."
                     : "Ready for another 25 minutes?")
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    switch done.kind {
                    case .focus: Button("Start Break") { app.startNextPhase() }.buttonStyle(.borderedProminent)
                    case .shortBreak, .longBreak: Button("Start Focus") { app.startNextPhase() }.buttonStyle(.borderedProminent)
                    case .timer: Button("+5 min") { app.startTimer(minutes: 5) }.buttonStyle(.borderedProminent)
                    }
                    Button(done.kind == .timer ? "Done" : "Skip") { app.dismissFinishedTimer() }
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

/// The evening check-in (§9.4): tomorrow at a glance, today's unanswered habits, unscheduled tasks,
/// then Plan with Blink or All set.
struct EveningView: View {
    let app: AppModel
    let plan: () -> Void

    var body: some View {
        let habits = app.habits.filter { app.isScheduledToday($0) && app.answerToday($0) == nil }
        let unscheduled = Array(app.openTasks.filter { $0.dueAt == nil }.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tomorrow, \(app.tomorrow.formatted(.dateTime.weekday(.wide).day().month()))")
                    .font(.title3.weight(.semibold))
                Text(app.agenda.dayLine(for: app.tomorrow)).foregroundStyle(.white.opacity(0.6))
            }
            ForEach(habits) { habit in
                HStack {
                    Text(habit.name).lineLimit(1)
                    Spacer()
                    Button("Done") { Task { await app.answer(habit, .done) } }.buttonStyle(.borderedProminent)
                    Button("Skip") { Task { await app.answer(habit, .skipped) } }
                }
                .controlSize(.small)
            }
            if !unscheduled.isEmpty {
                Text("No time yet: " + unscheduled.map(\.title).joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            HStack {
                Button(action: plan) { Label("Plan with Blink", systemImage: "moon.stars") }
                    .buttonStyle(.borderedProminent)
                Button("All set") { app.finishEvening() }
            }
            .controlSize(.small)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

/// One Ask-First card: the question, a preview line, the verb button (⌘⏎) and Dismiss (§6, §36.2).
struct CardView: View {
    let action: BlinkAction
    let count: Int
    let problem: String?
    let app: AppModel
    @State private var working = false

    private var symbol: String {
        switch action.risk {
        case .green: "checkmark.circle"
        case .amber: "clock.badge.checkmark"
        case .red: "touchid"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.orange) // mood.attention: needs you
                Text(action.title).font(.headline).lineLimit(2)
                Spacer(minLength: 4)
                if count > 1 { Text("1 of \(count)").font(.caption).foregroundStyle(.secondary) }
            }
            if let summary = action.payload.summary {
                Text(summary).foregroundStyle(.secondary).lineLimit(1) // adapts: notch (white) or window
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button {
                    Task { working = true; await app.approve(action); working = false }
                } label: {
                    Text(action.payload.verb ?? "Approve")
                }
                .buttonStyle(.borderedProminent)
                .help("⌘⏎")
                Button("Dismiss") { Task { await app.dismiss(action) } }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .disabled(working)
        }
    }
}
#endif
