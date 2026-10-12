// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import Observation
import UniformTypeIdentifiers

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
        syncTimer()
        // Pause lives in UserDefaults (Settings and the notch both flip it), so follow it from there.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTimer() }
        }
    }

    /// No polling while history is paused; resuming skips whatever was copied meanwhile.
    private func syncTimer() {
        if UserDefaults.standard.bool(forKey: Self.pausedKey) {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            lastChange = NSPasteboard.general.changeCount
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard !UserDefaults.standard.bool(forKey: Self.pausedKey),
              ClipboardHistory.shouldRecord(types: board.types?.map(\.rawValue) ?? []) else { return }
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let text = board.string(forType: .string)
        // One image file copied in Finder is kept as the picture (Finder's own image on the clipboard is only the
        // file's icon). The pasteboard lends Blink read access to the file; unreadable files stay file items.
        if urls.count == 1, UTType(filenameExtension: urls[0].pathExtension)?.conforms(to: .image) == true,
           FileManager.default.isReadableFile(atPath: urls[0].path) {
            let url = urls[0]
            record(name: url.deletingPathExtension().lastPathComponent) { NSImage(contentsOf: url) }
            return
        }
        switch ClipItem.pick(files: urls.map(\.path), text: text, hasImage: NSImage.canInit(with: board)) {
        case .file:
            history.add(ClipItem(kind: .file, text: urls.map(\.lastPathComponent).joined(separator: ", "), files: urls.map(\.path)))
        case .text, .link:
            let rich = board.data(forType: .rtf).flatMap { $0.count <= Self.maxRich ? $0 : nil }
            history.add(.text(text ?? "", rich: rich))
        case .image:
            // Only the raw bytes are read here; decoding happens off the main thread.
            guard let type = board.availableType(from: NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }),
                  let data = board.data(forType: type) else { return }
            record(name: "Image") { NSImage(data: data) }
            return
        case nil:
            return
        }
        save()
    }

    /// Decoding and PNG encoding a big photo takes long, so it runs off the main thread; the item lands when it's ready.
    private func record(name: String, load: @escaping @Sendable () -> NSImage?) {
        Task.detached { [weak self] in
            // The list shows a 34 × 24 thumbnail, so a small preview keeps the history file light.
            guard let image = load(), let preview = Self.png(image, maxSide: 240) else { return }
            let full = Self.png(image, maxSide: nil).flatMap { $0.count <= Self.maxImage ? $0 : nil }
            await self?.add(ClipItem(kind: .image, text: name, image: preview), original: full)
        }
    }

    private func add(_ item: ClipItem, original: Data?) {
        history.add(item)
        save(original: original.map { (Self.original(item), $0) })
    }

    static let maxRich = 1_000_000
    nonisolated static let maxImage = 25_000_000

    /// The full-size image if it was kept, else the preview.
    private func image(_ item: ClipItem) -> NSImage? {
        NSImage(contentsOf: Self.original(item)) ?? item.image.flatMap(NSImage.init(data:))
    }

    /// For dragging an item out of the notch into any app.
    func dragItem(_ item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            // shortcut: drags the first file only (SwiftUI's onDrag takes one provider); copy puts them all back. Upgrade
            // to an AppKit dragging session with one item per file when dragging a multi-file copy out is needed.
            return NSItemProvider(object: URL(filePath: item.files?.first ?? "") as NSURL)
        case .image:
            let provider = FileManager.default.fileExists(atPath: Self.original(item).path)
                ? NSItemProvider(contentsOf: Self.original(item)) ?? NSItemProvider()
                : image(item).map { NSItemProvider(object: $0) } ?? NSItemProvider()
            provider.suggestedName = item.text
            return provider
        case .link:
            let provider = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
            provider.registerObject(item.text as NSString, visibility: .all)
            return provider
        case .text:
            let provider = NSItemProvider(object: item.text as NSString)
            if let rich = item.rich {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { done in
                    done(rich, nil)
                    return nil
                }
            }
            return provider
        }
    }

    /// Puts an item back on the clipboard; Blink's own copy is not recorded again.
    func copy(_ item: ClipItem) {
        let board = NSPasteboard.general
        board.clearContents()
        switch item.kind {
        case .image:
            if let image = image(item) { board.writeObjects([image]) }
        case .file:
            board.writeObjects((item.files ?? []).map { URL(filePath: $0) as NSURL })
        case .text, .link:
            board.setString(item.text, forType: .string)
            if let rich = item.rich { board.setData(rich, forType: .rtf) }
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

    private static var images: URL {
        URL.applicationSupportDirectory.appending(path: "Blink/clips", directoryHint: .isDirectory)
    }

    private static func original(_ item: ClipItem) -> URL {
        images.appending(path: "\(item.id.uuidString).png")
    }

    private static func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: file),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else { return ClipboardHistory() }
        return history
    }

    @ObservationIgnored private var lastSave: Task<Void, Never>?

    /// Writes off the main thread, one save after another, so copying never stutters and the newest history lands last.
    /// `original` is a full-size image to write beside the history, before old ones are pruned.
    private func save(original: (url: URL, data: Data)? = nil) {
        let snapshot = history
        let file = Self.file, images = Self.images
        // Full-size originals for the newest few images only; older ones keep their preview (caps disk use).
        let kept = Set(snapshot.items.filter { $0.kind == .image }.prefix(Self.keptOriginals).map { Self.original($0).lastPathComponent })
        lastSave = Task.detached { [previous = lastSave] in
            await previous?.value
            // shortcut: plain JSON in the sandbox container (FileVault protects it at rest); encrypt with a Keychain key if
            // the history ever leaves this Mac or holds more than 50 items.
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtection])
            // The original sits beside the history so pasting or dragging it back keeps full quality.
            if let original {
                try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
                try? original.data.write(to: original.url, options: [.atomic, .completeFileProtection])
            }
            for url in (try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)) ?? []
            where !kept.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static let keptOriginals = 10

    /// PNG of the image, shrunk so its longest side is at most `maxSide` points (nil keeps full size).
    nonisolated private static func png(_ image: NSImage, maxSide: CGFloat?) -> Data? {
        if maxSide == nil, let rep = image.representations.first as? NSBitmapImageRep {
            return rep.representation(using: .png, properties: [:])
        }
        let scale = min(1, (maxSide ?? .infinity) / max(image.size.width, image.size.height, 1))
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
