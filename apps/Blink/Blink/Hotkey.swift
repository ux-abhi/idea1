// © Pexilim
#if os(macOS)
import Carbon.HIToolbox

/// Global shortcuts (⌃⌥Space chat, ⌃⌥V clipboard; §36.2) through Carbon's RegisterEventHotKey,
/// which needs no Accessibility permission (§36.1).
/// shortcut: fixed shortcuts; make them changeable with conflict detection in Settings › Blink & Notch (§36.2).
final class GlobalHotkey {
    nonisolated(unsafe) private static var actions: [UInt32: @MainActor () -> Void] = [:]
    nonisolated(unsafe) private static var installed = false
    private var ref: EventHotKeyRef?

    init(id: UInt32, keyCode: Int, action: @escaping @MainActor () -> Void) {
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
        RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }
}
#endif
