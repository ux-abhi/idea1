// © Pexilim
#if os(macOS)
import ServiceManagement

/// "Open Blink when you log in" (SMAppService), only ever turned on by the owner (onboarding or Settings), so the
/// morning brief is there on the first unlock of the day.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a sentence to show when macOS refused (e.g. turned off in System Settings › General › Login Items).
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "macOS didn't allow that. Check System Settings › General › Login Items."
        }
    }
}
#else
/// iPhone: no login items; the Island and widgets are always there instead.
enum LoginItem {
    static var isOn: Bool { false }
    @discardableResult static func set(_ on: Bool) -> String? { nil }
}
#endif
