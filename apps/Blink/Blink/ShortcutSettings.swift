// © Pexilim
#if os(macOS)
import ApplicationServices
import AVFAudio
import BlinkKit
import Carbon.HIToolbox
import SwiftUI

/// Settings › Shortcuts: Blink's global shortcuts, each recorded by pressing it; dictation with fn twice; then every
/// other shortcut, for reference.
struct ShortcutSettings: View {
    @AppStorage(BlinkShortcut.fnTwiceKey) private var fnTwice = false
    @AppStorage(BlinkShortcut.twiceKeyKey) private var twiceKey = kVK_Function
    @AppStorage(Dictation.groqKey) private var groq = false
    @AppStorage(VoiceActions.speaksKey) private var speaks = true
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                ForEach(BlinkShortcut.allCases.filter { $0 != .dictate }) { shortcut in
                    LabeledContent(shortcut.title) { ShortcutRecorder(shortcut: shortcut) }
                }
            } header: {
                Text("Anywhere on your Mac")
            } footer: {
                Text("Click a shortcut, then press the new keys: with ⌃ or ⌥, or ⌘⇧, or an F-key alone. Delete clears it, Esc keeps it.")
            }

            Section {
                // Dictation's own shortcut lives here, with the key-twice option, not in the list above.
                LabeledContent("Shortcut") { ShortcutRecorder(shortcut: .dictate) }
                Toggle("Or press a key twice", isOn: $fnTwice)
                    .onChange(of: fnTwice) { _, on in
                        if on, !AXIsProcessTrusted() { CGRequestPostEventAccess() } // the one macOS question, asked here
                        NotificationCenter.default.post(name: BlinkShortcut.changed, object: nil)
                    }
                if fnTwice {
                    Picker("Key", selection: $twiceKey) {
                        ForEach(BlinkShortcut.twiceKeys, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .onChange(of: twiceKey) { NotificationCenter.default.post(name: BlinkShortcut.changed, object: nil) }
                }
                if fnTwice, twiceKey == kVK_Function {
                    // A sandboxed app can't change this for the owner: macOS's own fn action has to be turned off there.
                    LabeledContent("Emoji picker or input switch opens too?") {
                        Button("Open Keyboard Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                }
                Toggle("Say replies out loud", isOn: $speaks)
                if speaks, (VoiceActions.bestVoice?.quality ?? .default) == .default {
                    // Only the robotic compact voices are installed: point to Apple's free natural ones.
                    LabeledContent {
                        Button("Open Accessibility") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!)
                        }
                    } label: {
                        Text("For a natural voice: Accessibility › Read & Speak (or Spoken Content) › System voice › Manage Voices, then download a Premium one, like Zoe or Ava.")
                            .font(.callout)
                    }
                }
                Picker("Speech to text", selection: $groq) {
                    Text("Groq Whisper: best for Hindi and Hinglish").tag(true)
                    Text("This Mac only: private, works offline").tag(false)
                }
                if !trusted { // typing into other apps needs it, whichever way dictation starts
                    LabeledContent {
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    } label: {
                        Text("Allow Blink in Accessibility, so it can hear the key and type for you.")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text("Press the key twice (or the shortcut), speak, then press it again to type it where your cursor is. Esc drops it. The 🎤 key belongs to macOS. With Groq, the recording goes through your server to Groq (your key, free tier) and isn't kept; the Mac's own text is used if that fails. Language: General › Meeting Notes. With fn, set Keyboard › “Press 🌐 key to” to “Do Nothing” so the emoji picker stays shut, or pick a right-hand key instead.")
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
    /// The modifiers held so far while recording ("⌃⌥"), so the owner sees the keys arrive.
    @State private var held = ""
    @AppStorage(BlinkShortcut.takenKey) private var taken = ""

    var body: some View {
        HStack(spacing: 8) {
            if !recording, problem == nil, taken.split(separator: ",").contains(Substring(shortcut.rawValue)) {
                Text("Taken by another app: pick other keys").font(.caption).foregroundStyle(.orange)
            }
            if let problem {
                // Wraps instead of being cut off next to the button.
                Text(problem).font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            Button(recording ? (held.isEmpty ? "Press keys…" : held + "…") : combo?.label ?? "Record Shortcut") {
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
        // Another app took the keys (⇧⌘4 for a screenshot, say): stop, so the held keys don't stay stuck on the button.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        problem = nil
        held = ""
        recording = true
        NotificationCenter.default.post(name: BlinkShortcut.pausing, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated { event.type == .flagsChanged ? modifiersChanged(event) : record(event) }
            return nil // the keys are the shortcut, not typing
        }
    }

    /// Modifiers alone make no shortcut: show them as they're held, and say what to do about fn.
    private func modifiersChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        held = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
        if Int(event.keyCode) == kVK_Function, flags.contains(.function) {
            problem = shortcut == .dictate ? "Use “Press a key twice” below" : "fn can't be a shortcut"
        }
    }

    private func record(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: stop() // Esc: keep what it was
        case 51, 117: save(nil); stop() // Delete: no shortcut
        default:
            let pressed = KeyCombo(event)
            guard pressed.isUsable else {
                problem = "Add ⌃ or ⌥, or ⌘⇧ (or use an F-key)"
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
        held = ""
        guard recording else { return }
        recording = false
        NotificationCenter.default.post(name: BlinkShortcut.changed, object: nil) // the shortcuts come back on
    }
}
#endif
