// © Pexilim
#if os(macOS)
import Carbon.HIToolbox

/// ⌃⌥Space (§36.2) through Carbon's RegisterEventHotKey, which needs no Accessibility permission (§36.1).
/// shortcut: fixed shortcut; make it changeable with conflict detection in Settings › Blink & Notch (§36.2).
final class GlobalHotkey {
    nonisolated(unsafe) private static var action: (@MainActor () -> Void)?
    private var ref: EventHotKeyRef?

    init(action: @escaping @MainActor () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x424C_4E4B), id: 1) // "BLNK"
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
#endif
