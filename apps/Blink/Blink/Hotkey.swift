// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import Carbon.HIToolbox
import SwiftUI

/// Blink's global shortcuts, each changeable in Settings › Shortcuts. Stored per action; a cleared one is empty data.
enum BlinkShortcut: String, CaseIterable, Identifiable {
    case ask, clipboard, search, notes, dictate

    var id: Self { self }
    /// Posted when a shortcut changes (the notch registers them again) and while one is being recorded (`pausing`).
    static let changed = Notification.Name("blink.shortcuts.changed")
    static let pausing = Notification.Name("blink.shortcuts.pausing")
    /// Dictation by pressing fn twice (needs Accessibility, so it's off until turned on).
    static let fnTwiceKey = "dictation.fnTwice"

    var title: String {
        switch self {
        case .ask: "Ask Blink"
        case .clipboard: "Clipboard history"
        case .search: "Search everything"
        case .notes: "Take or stop meeting notes"
        case .dictate: "Dictate (start, then type it)"
        }
    }

    var standard: KeyCombo? {
        let both = KeyCombo.control | KeyCombo.option
        return switch self {
        case .ask: KeyCombo(keyCode: UInt32(kVK_Space), modifiers: both, key: "Space")
        case .clipboard: KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: both, key: "V")
        case .search: KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: both, key: "K")
        case .notes, .dictate: nil
        }
    }

    var defaultsKey: String { "shortcut." + rawValue }

    var combo: KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return standard }
        return try? JSONDecoder().decode(KeyCombo.self, from: data) // cleared: empty data, no shortcut
    }

    func set(_ combo: KeyCombo?) {
        UserDefaults.standard.set(combo.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: defaultsKey)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// The live keys for a row of the shared shortcut list: "⌃⌥K", what the owner changed it to, or "Off".
    static func liveKeys(_ listed: String) -> String {
        allCases.first { $0.standard?.label == listed }.map { $0.combo?.label ?? "Off" } ?? listed
    }
}

extension KeyCombo {
    /// From a key press in the recorder: the key's name as macOS menus write it.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        let mods = [(NSEvent.ModifierFlags.control, KeyCombo.control), (.option, KeyCombo.option),
                    (.shift, KeyCombo.shift), (.command, KeyCombo.command)]
            .filter { flags.contains($0.0) }.reduce(0) { $0 | $1.1 }
        let named: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←",
                                    kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2",
                                    kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
                                    kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        let key = named[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, key: key)
    }

    /// The same keys for a SwiftUI menu item; nil for keys a menu can't show (arrows, F-keys).
    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        if key == "Space" { equivalent = .space } else if key.count == 1, let c = key.lowercased().first { equivalent = KeyEquivalent(c) } else { return nil }
        let mods: SwiftUI.EventModifiers = [(KeyCombo.control, SwiftUI.EventModifiers.control), (KeyCombo.option, .option),
                                    (KeyCombo.shift, .shift), (KeyCombo.command, .command)]
            .filter { modifiers & $0.0 != 0 }.reduce(SwiftUI.EventModifiers()) { $0.union($1.1) }
        return KeyboardShortcut(equivalent, modifiers: mods)
    }
}

/// One global shortcut through Carbon's RegisterEventHotKey, which needs no Accessibility permission (§36.1).
/// Unregistered when released, so changing a shortcut in Settings takes effect at once.
final class GlobalHotkey {
    nonisolated(unsafe) private static var actions: [UInt32: @MainActor () -> Void] = [:]
    nonisolated(unsafe) private static var installed = false
    private let id: UInt32
    nonisolated(unsafe) private var ref: EventHotKeyRef?

    init(id: UInt32, combo: KeyCombo, action: @escaping @MainActor () -> Void) {
        self.id = id
        Self.actions[id] = action
        if !Self.installed {
            Self.installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let id = pressed.id
                Task { @MainActor in GlobalHotkey.actions[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x424C_4E4B), id: id) // "BLNK"
        RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }
}

/// Watches fn (🌐) anywhere for dictation: two quick presses start it, one ends it, Esc cancels. Seeing keys in other
/// apps needs Accessibility; without it nothing arrives and nothing happens. The keys still reach the app as usual.
final class FnMonitor {
    private var monitors: [Any] = []
    private var taps = FnTaps()

    init(tapped: @escaping @MainActor (FnTaps.Tap) -> Void, escape: @escaping @MainActor () -> Void) {
        let handle: @MainActor (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .flagsChanged:
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let others = flags.subtracting([.function, .capsLock, .numericPad])
                if Int(event.keyCode) == kVK_Function {
                    // fn with ⌘, ⌥, ⌃ or ⇧ held is someone's shortcut, not a dictation press.
                    if !others.isEmpty { self.taps.otherKey() }
                    if let tap = self.taps.fn(down: flags.contains(.function), at: event.timestamp) { tapped(tap) }
                } else {
                    self.taps.otherKey()
                }
            case .keyDown:
                self.taps.otherKey()
                if Int(event.keyCode) == kVK_Escape { escape() }
            default: break
            }
        }
        let kinds: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { event in MainActor.assumeIsolated { handle(event) } }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { event in
            MainActor.assumeIsolated { handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    isolated deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }
}
#endif
