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
    /// Rows in the glance (events + reminders, at most 4); sets the open height.
    var glanceRows = 0
    static let maxGlanceRows = 4

    /// Ears beside the camera stay slim at rest so long app menus are never covered (§36.2).
    static let ear: CGFloat = 24

    func size(for level: Level, rows: Int? = nil) -> CGSize {
        let rest = CGSize(width: notchSize.width + 2 * Self.ear, height: notchSize.height)
        switch level {
        case .rest: return rest
        case .peek: return CGSize(width: max(rest.width, 320), height: rest.height + 36)
        // Title plus one 22 pt line per row; an empty glance shows a two-line message.
        case .open: return CGSize(width: max(rest.width, 420), height: rest.height + 56 + CGFloat(max(rows ?? glanceRows, 2)) * 22)
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
                guard event.keyCode == 53, self?.model.level == .open else { return event } // Esc
                self?.close()
                return nil
            },
        ].compactMap { $0 }
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
        let size = model.size(for: .open, rows: NotchModel.maxGlanceRows)
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
        panel.contentView = NotchHostingView(rootView: NotchView(model: model, app: app, open: { [weak self] in self?.open() }))
        return panel
    }

    /// The shape's current rectangle in screen coordinates.
    private func shapeRect() -> NSRect {
        guard let frame = panel?.frame else { return .zero }
        let size = model.size(for: model.level)
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Clicks pass through everywhere except the shape; hover peeks after 150 ms and closes 350 ms after leaving (§36.2).
    /// shortcut: fast pointer passes aren't filtered (only the 150 ms delay) and this has no test; add both if peeks fire by accident.
    private func pointerMoved() {
        let inside = shapeRect().contains(NSEvent.mouseLocation)
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
            guard model.level == .peek, leaveTask == nil else { return }
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Tokens.Motion.hoverGraceOut))
                guard let self, !Task.isCancelled else { return }
                self.leaveTask = nil
                if self.model.level == .peek { self.set(.rest) }
            }
        }
    }

    func open() {
        guard model.level != .open, let panel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        set(.open)
        panel.allowsKey = true
        panel.makeKey() // for Esc; the panel never activates Blink
    }

    func close() {
        guard let panel else { return }
        set(.rest)
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
    }
}

struct NotchView: View {
    let model: NotchModel
    let app: AppModel
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Once a minute, never per frame: keeps the countdown current at ~0 CPU.
        TimelineView(.everyMinute) { context in
            shape(statusLine: app.agenda.statusLine(now: context.date), now: context.date)
                .onChange(of: GlanceView.rows(agenda: app.agenda, now: context.date), initial: true) { _, rows in
                    model.glanceRows = rows
                }
        }
    }

    private func shape(statusLine: String, now: Date) -> some View {
        let size = model.size(for: model.level)
        let radius = model.level == .rest ? Tokens.Radius.notchRest : Tokens.Radius.notchOpen
        return VStack(spacing: 8) {
            BlinkEyes(mood: model.mood, notchGap: model.notchSize.width)
                .frame(width: model.size(for: .rest).width, height: model.notchSize.height)
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
                GlanceView(statusLine: statusLine, agenda: app.agenda, access: app.calendarAccess, now: now)
                    .transition(contentTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black) // notch.hardware: always pure black
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
        .accessibilityValue(statusLine)
        .accessibilityAction(named: "Open", open)
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

/// Level 2: today's remaining events and reminders.
/// Not gated by the app lock yet; gate it when the Mac lock policy for the notch is decided (§36.5).
struct GlanceView: View {
    let statusLine: String
    let agenda: Agenda
    let access: CalendarReader.Access
    let now: Date

    static func rows(agenda: Agenda, now: Date) -> Int {
        min(min(agenda.today(now: now).count, 3) + agenda.reminders.count, NotchModel.maxGlanceRows)
    }

    var body: some View {
        let events = Array(agenda.today(now: now).prefix(3))
        let reminders = Array(agenda.reminders.prefix(max(0, NotchModel.maxGlanceRows - events.count)))
        VStack(alignment: .leading, spacing: 6) {
            Text(statusLine)
                .font(.title3.weight(.semibold))
            if access != .granted {
                Text("Your next meeting and today's reminders show here once Calendar is connected.")
                    .foregroundStyle(.white.opacity(0.7))
            } else if events.isEmpty && reminders.isEmpty {
                Text("Nothing else on your calendar today.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(events) { event in
                HStack(spacing: 8) {
                    Text(event.start, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.mint) // mood.headsUp: time
                    Text(event.title).lineLimit(1)
                }
            }
            ForEach(reminders) { reminder in
                Label(reminder.title, systemImage: "circle").lineLimit(1)
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}
#endif
