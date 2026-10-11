// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// The notch's three levels (ARCHITECTURE §5) and what they show.
@Observable
final class NotchModel {
    enum Level { case rest, peek, open }

    var level = Level.rest
    var mood = Mood.idle
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

    /// Ears beside the camera stay slim at rest so long app menus are never covered (§36.2).
    static let ear: CGFloat = 24

    func size(for level: Level) -> CGSize {
        let rest = CGSize(width: notchSize.width + 2 * Self.ear, height: notchSize.height)
        switch level {
        case .rest: return rest
        case .peek: return CGSize(width: max(rest.width, 320), height: rest.height + 36)
        // Eyes row, 8 pt gap, the measured content, 20 pt to breathe at the bottom.
        case .open: return CGSize(width: max(rest.width, chatting ? Self.chatWidth : Self.openWidth),
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
    private var hotkey: GlobalHotkey?
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(app: AppModel) {
        self.app = app
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
                if self?.model.level == .open { self?.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.model.level == .open else { return event }
                if event.keyCode == 53 { // Esc
                    self.close()
                    return nil
                }
                // ⌘⏎ approves; never a bare ⏎ (§36.2).
                if event.keyCode == 36, event.modifierFlags.contains(.command), let first = self.app.pending.first {
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
        hotkey = GlobalHotkey { [weak self] in self?.toggleChat() }

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

    private func scheduleCues() {
        cueWake?.cancel()
        let ids = Set(app.agenda.events.map(\.id) + app.agenda.dueItems(adding: app.dueTasks).map(\.id))
        spoken = spoken.filter { ids.contains($0.key) } // forget meetings that are gone
        evaluateCue()
        guard let next = app.agenda.nextCueChange(after: .now, tasks: app.dueTasks) else { return }
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
        if !model.briefing { model.mood = cue == nil ? .idle : .headsUp }
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
    /// shortcut: fires on screen unlock only, not when Blink launches at login; add once Blink is a login item (SMAppService).
    private func morningBriefIfFirstToday() {
        guard app.calendarAccess == .granted else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if let last = UserDefaults.standard.object(forKey: "lastBrief") as? Date, last >= today { return }
        UserDefaults.standard.set(Date.now, forKey: "lastBrief")
        Task {
            await app.reloadAgenda()
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

    /// Puts the panel over the built-in display's notch, sized for the largest level.
    private func place() {
        // shortcut: no-notch displays show nothing; add the menu bar icon and black pill (§36.2) with display contexts.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            panel?.orderOut(nil)
            return
        }
        let side = (screen.auxiliaryTopLeftArea?.width ?? 0) + (screen.auxiliaryTopRightArea?.width ?? 0)
        model.notchSize = CGSize(width: screen.frame.width - side, height: screen.safeAreaInsets.top)
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
        panel.sharingType = .none // hidden from screen capture and sharing (§36.1)
        panel.contentView = NotchHostingView(rootView: NotchView(model: model, app: app,
                                                                      open: { [weak self] in self?.open() },
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
    func toggleChat() {
        if model.level == .open && model.chatting { close(); return }
        model.chatting = true
        if model.level == .open, let panel {
            panel.allowsKey = true
            panel.makeKey()
        } else {
            open()
        }
    }

    func open() {
        guard model.level != .open, let panel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        set(.open)
        Task { await app.loadActions() }
        panel.allowsKey = true
        panel.makeKey() // for Esc; the panel never activates Blink
    }

    func close() {
        guard let panel else { return }
        autoClose?.cancel()
        set(.rest)
        model.chatting = false
        panel.allowsKey = false
        // Hand the keyboard back to the app that had it (§36.2).
        if let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
        previousApp = nil
        pointerMoved()
    }

    private func set(_ level: NotchModel.Level) {
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
        if level == .rest && model.briefing {
            model.briefing = false // brief seen: Morning → Idle (§7)
            evaluateCue()
        }
    }
}

struct NotchView: View {
    let model: NotchModel
    let app: AppModel
    let open: () -> Void
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
        if model.chatting {
            ChatPanel(app: app)
        } else {
            GlanceView(statusLine: statusLine, agenda: app.agenda, tasks: app.dueTasks, access: app.calendarAccess, now: now,
                       briefing: model.briefing, done: close,
                       card: app.pending.first.map { CardView(action: $0, count: app.pending.count, problem: app.actionProblem, app: app) })
        }
    }

    private func shape(statusLine: String, now: Date) -> some View {
        let size = model.size(for: model.level)
        let radius = model.level == .rest ? Tokens.Radius.notchRest : Tokens.Radius.notchOpen
        return VStack(spacing: 8) {
            BlinkEyes(mood: model.mood, notchGap: model.notchSize.width)
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
                Text(statusLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .transition(contentTransition)
            case .open:
                glance(statusLine: statusLine, now: now)
                    .transition(contentTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black) // notch.hardware: always pure black
        .overlay {
            // Inside the notch only (tokens: glow.rule).
            ThinkingGlow(active: app.thinking && model.level == .open)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .contentShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Open Blink") {
                NSApp.activate()
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            Button("Quit Blink") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Blink")
        .accessibilityValue(app.pending.isEmpty ? statusLine : "\(statusLine). \(app.pending.count) waiting for you")
        .accessibilityAction(named: "Open", open)
        .opacity(model.level == .rest && restStyle != .ears ? 0 : 1)
        .overlay(alignment: .top) {
            SplitInput(app: app, progress: model.inputOut ? 1 : 0, notchBottom: size.height,
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
            if access != .granted {
                Text("Your next meeting and today's reminders show here once Calendar is connected.")
                    .foregroundStyle(.white.opacity(0.7))
            } else if events.isEmpty && due.isEmpty && !briefing {
                Text("Nothing else on your calendar today.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            let joining = agenda.cue(now: now, tasks: tasks)?.event
            ForEach(events) { event in
                HStack(spacing: 8) {
                    Text(event.start, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.mint) // mood.headsUp: time
                    Text(event.title).lineLimit(1)
                    if event == joining, let url = event.joinURL {
                        Spacer(minLength: 8)
                        Button("Join") {
                            NSWorkspace.shared.open(url)
                            done()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            ForEach(due) { item in
                HStack(spacing: 8) {
                    Text(item.due, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(item.due < now ? .orange : .mint)
                    Label(item.title, systemImage: "circle").lineLimit(1)
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.chat.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask Blink").font(.title3.weight(.semibold))
                    Text("“What's left today?” · “Remind me to call Sam on Friday at 4”")
                        .font(.callout).foregroundStyle(.white.opacity(0.55))
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(app.chat.suffix(6)) { turn in line(turn).id(turn.id) }
                            if app.thinking {
                                Text("Thinking…").font(.callout).foregroundStyle(.white.opacity(0.5)).id("thinking")
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

/// The input that splits off the notch like a droplet. A sliver of the notch's bottom and the bubble are drawn
/// blurred and then cut at an alpha threshold (the "gooey" metaball technique), so while they are close a smooth
/// liquid neck joins them and it pinches off by itself as the bubble moves away. `progress` 0 = inside the notch,
/// 1 = its own bubble below.
struct SplitInput: View, Animatable {
    let app: AppModel
    var progress: Double
    let notchBottom: CGFloat
    let notchWidth: CGFloat
    let width: CGFloat
    @State private var text = ""
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
            TextField("Ask Blink…", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(send)
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

    private var canSend: Bool { !app.thinking && !text.trimmingCharacters(in: .whitespaces).isEmpty }

    private func send() {
        guard canSend else { return }
        let message = text
        text = ""
        Task { await app.ask(message) }
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
