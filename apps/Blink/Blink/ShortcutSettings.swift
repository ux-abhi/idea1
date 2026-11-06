// © Pexilim
#if os(macOS)
import ApplicationServices
import BlinkKit
import SwiftUI

/// Settings › Shortcuts: Blink's global shortcuts, each recorded by pressing it; dictation with fn twice; then every
/// other shortcut, for reference.
struct ShortcutSettings: View {
    @AppStorage(BlinkShortcut.fnTwiceKey) private var fnTwice = false
    @AppStorage(Dictation.groqKey) private var groq = true
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                ForEach(BlinkShortcut.allCases) { shortcut in
                    LabeledContent(shortcut.title) { ShortcutRecorder(shortcut: shortcut) }
                }
            } header: {
                Text("Anywhere on your Mac")
            } footer: {
                Text("Click a shortcut, then press the new keys (with ⌃ or ⌥, or ⌘⇧). Delete clears it, Esc keeps it.")
            }

            Section {
                Toggle("Press fn twice to dictate", isOn: $fnTwice)
                    .onChange(of: fnTwice) { _, on in
                        if on, !AXIsProcessTrusted() { CGRequestPostEventAccess() } // the one macOS question, asked here
                        NotificationCenter.default.post(name: BlinkShortcut.changed, object: nil)
                    }
                Picker("Speech to text", selection: $groq) {
                    Text("Groq Whisper: best for Hindi and Hinglish").tag(true)
                    Text("This Mac only: private, works offline").tag(false)
                }
                if fnTwice, !trusted {
                    LabeledContent {
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    } label: {
                        Text("Allow Blink in Accessibility, so it can hear fn and type for you.")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text("Speak, then press fn once to type it where your cursor is. Esc drops it. With Groq, the recording goes through your server to Groq (your key, free tier) and isn't kept; the Mac's own text is used if that fails. Language: General › Meeting Notes. If the emoji picker or macOS Dictation also opens, set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing” and turn off the Dictation shortcut there.")
            }

            Section("All shortcuts") {
                ForEach(Shortcuts.all) { group in
                    Text(group.name).font(.headline).padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(group.items) { item in
                        LabeledContent(item.what) { KeysLabel(keys: BlinkShortcut.liveKeys(item.keys)) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Granted in System Settings while this was open: show it when the owner comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
    }
}

/// One shortcut: its keys as a button; click, press the new keys. While recording, Blink's shortcuts are off so
/// pressing one is recorded, not run.
struct ShortcutRecorder: View {
    let shortcut: BlinkShortcut
    @State private var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        HStack(spacing: 8) {
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            Button(recording ? "Press keys…" : combo?.label ?? "Record Shortcut") {
                recording ? stop() : start()
            }
            .font(.callout.monospaced().weight(.medium))
            .accessibilityLabel(recording ? "Recording: press the new shortcut" : "\(shortcut.title): \(combo?.label ?? "none")")
            .accessibilityHint("Click, then press the new keys")
            if !recording, combo != shortcut.standard, shortcut.standard != nil {
                Button("Reset", systemImage: "arrow.uturn.backward") { save(shortcut.standard) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Back to \(shortcut.standard?.label ?? "")")
            }
        }
        .onAppear { combo = shortcut.combo }
        .onDisappear { stop() }
    }

    private func start() {
        problem = nil
        recording = true
        NotificationCenter.default.post(name: BlinkShortcut.pausing, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil // the keys are the shortcut, not typing
        }
    }

    private func record(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: stop() // Esc: keep what it was
        case 51, 117: save(nil); stop() // Delete: no shortcut
        default:
            let pressed = KeyCombo(event)
            guard pressed.isUsable else {
                problem = "Add ⌃ or ⌥, or ⌘⇧"
                return
            }
            if let other = BlinkShortcut.allCases.first(where: { $0 != shortcut && $0.combo == pressed }) {
                problem = "Used by \(other.title)"
                return
            }
            save(pressed)
            stop()
        }
    }

    private func save(_ new: KeyCombo?) {
        combo = new
        problem = nil
        shortcut.set(new)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        NotificationCenter.default.post(name: BlinkShortcut.changed, object: nil) // the shortcuts come back on
    }
}
#endif
