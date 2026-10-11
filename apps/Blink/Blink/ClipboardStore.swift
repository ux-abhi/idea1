// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import Observation

/// Clipboard history on this Mac only (ARCHITECTURE §31): never sent to the server or to Claude.
/// macOS has no "clipboard changed" notification, so this checks the change count once a second, with
/// tolerance so the system can batch the wakeups. Secrets marked concealed or transient are never recorded.
@Observable
final class ClipboardStore {
    private(set) var history: ClipboardHistory
    static let pausedKey = "clipboardPaused"
    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?

    init() {
        history = Self.load()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard !UserDefaults.standard.bool(forKey: Self.pausedKey),
              ClipboardHistory.shouldRecord(types: board.types?.map(\.rawValue) ?? []) else { return }
        if let text = board.string(forType: .string) {
            history.add(.text(text))
        } else if let image = NSImage(pasteboard: board), let png = Self.thumbnail(image) {
            history.add(ClipItem(kind: .image, text: "Image", image: png))
        } else {
            return
        }
        save()
    }

    /// Puts an item back on the clipboard; Blink's own copy is not recorded again.
    func copy(_ item: ClipItem) {
        let board = NSPasteboard.general
        board.clearContents()
        if item.kind == .image, let data = item.image, let image = NSImage(data: data) {
            board.writeObjects([image])
        } else {
            board.setString(item.text, forType: .string)
        }
        lastChange = board.changeCount
        history.add(item) // moves it to the top
        save()
    }

    func remove(_ item: ClipItem) {
        history.remove(item.id)
        save()
    }

    func clear() {
        history.clear()
        save()
    }

    // MARK: Storage, inside the app's sandbox container

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "Blink/clipboard.json")
    }

    private static func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: file),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else { return ClipboardHistory() }
        return history
    }

    private func save() {
        // shortcut: plain JSON in the sandbox container (FileVault protects it at rest); encrypt with a Keychain key if
        // the history ever leaves this Mac or holds more than 50 items.
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(history).write(to: Self.file, options: [.atomic, .completeFileProtection])
    }

    /// A small PNG (longest side 480 pt) so the history stays light.
    private static func thumbnail(_ image: NSImage) -> Data? {
        let maxSide: CGFloat = 480
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
