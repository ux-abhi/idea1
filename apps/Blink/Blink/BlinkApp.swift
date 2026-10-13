// © Pexilim
import BlinkKit
import SwiftUI

@main
struct BlinkApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(RestStyle.key) private var restStyle = RestStyle.ears
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
                .task {
                    #if os(macOS)
                    appDelegate.startNotch(model)
                    #endif
                    await model.load()
                }
        }
        #if os(macOS)
        .defaultSize(width: 920, height: 640)
        #endif

        #if os(macOS)
        Settings {
            SettingsRoot().environment(model).environment(appDelegate.clipboard)
        }
        #endif

        #if os(macOS)
        // VoiceOver can't reach the floating notch panel; the menu bar icon is its entry point (§36.2).
        MenuBarExtra("Blink", systemImage: "eyes", isInserted: .constant(restStyle != .hidden)) {
            MenuBarContent(showNotch: { appDelegate.showNotch() }, ask: { appDelegate.askBlink() },
                           clipboard: { appDelegate.showClipboard() }, search: { appDelegate.showSearch() })
                .environment(model)
        }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    let clipboard = ClipboardStore()

    func startNotch(_ app: AppModel) {
        if notch == nil { notch = NotchController(app: app, clipboard: clipboard) }
    }

    func showNotch() { notch?.open() }
    func askBlink() { notch?.toggleChat() }
    func showClipboard() { notch?.toggleClipboard() }
    func showSearch() { notch?.toggleSearch() }
}

/// The menu bar menu: the notch's status and actions, reachable by VoiceOver and the keyboard.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    let showNotch: () -> Void
    let ask: () -> Void
    let clipboard: () -> Void
    let search: () -> Void

    var body: some View {
        Text(model.agenda.statusLine(now: .now, tasks: model.dueTasks))
        if !model.pending.isEmpty {
            Text(model.pending.count == 1 ? "1 waiting for you" : "\(model.pending.count) waiting for you")
        }
        if let timer = model.timer {
            Text("\(timer.label): \(FocusTimer.clock(timer.remaining(now: .now))) left\(timer.isPaused ? " (paused)" : "")")
        }
        Divider()
        Button("Ask Blink…", action: ask)
            .keyboardShortcut(.space, modifiers: [.control, .option])
        Button("Clipboard…", action: clipboard)
            .keyboardShortcut("v", modifiers: [.control, .option])
        Button("Search…", action: search)
            .keyboardShortcut("k", modifiers: [.control, .option])
        Button("Start Focus (25 min)") { model.startFocus() }
        Menu("Timer") {
            ForEach([5, 10, 15, 30, 60], id: \.self) { m in Button("\(m) min") { model.startTimer(minutes: Double(m)) } }
        }
        if model.timer != nil { Button("Stop Timer") { model.stopTimer() } }
        Divider()
        Button("Sync Now") { Task { await model.refresh() } }
            .disabled(model.status == .checking)
        Button("Show in Notch", action: showNotch)
        Button("Open Blink") {
            model.showWindow()
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Blink") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarding.done") private var onboardingDone = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        content
            #if os(macOS)
            // The notch and setup prompts open Settings through this, even when the window is locked or closed later.
            .onAppear {
                let open = openSettings, window = openWindow
                model.settingsOpener = { open() }
                model.windowOpener = { window(id: "main") }
            }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        // The lock replaces the content rather than covering it, so nothing renders behind it.
        if model.locked {
            LockView()
        } else if model.screen == .home && onboardingDone {
            #if os(macOS)
            MainWindow()
            #else
            NavigationStack { HomeView() }
            #endif
        } else {
            // First run, or signed out: the onboarding owns the window (server, sign-in, calendar, about you).
            OnboardingView()
        }
    }
}
