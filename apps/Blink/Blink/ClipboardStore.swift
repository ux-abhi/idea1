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
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let text = board.string(forType: .string)
        // One image file copied in Finder is kept as the picture (Finder's own image on the clipboard is only the
        // file's icon). The pasteboard lends Blink read access to the file; unreadable files stay file items.
        if urls.count == 1, UTType(filenameExtension: urls[0].pathExtension)?.conforms(to: .image) == true,
           let image = NSImage(contentsOf: urls[0]) {
            record(image, name: urls[0].deletingPathExtension().lastPathComponent)
            return
        }
        switch ClipItem.pick(files: urls.map(\.path), text: text, hasImage: NSImage.canInit(with: board)) {
        case .file:
            history.add(ClipItem(kind: .file, text: urls.map(\.lastPathComponent).joined(separator: ", "), files: urls.map(\.path)))
        case .text, .link:
            let rich = board.data(forType: .rtf).flatMap { $0.count <= Self.maxRich ? $0 : nil }
            history.add(.text(text ?? "", rich: rich))
        case .image:
            guard let image = NSImage(pasteboard: board) else { return }
            record(image, name: "Image")
            return
        case nil:
            return
        }
        save()
    }

    private func record(_ image: NSImage, name: String) {
        guard let preview = Self.png(image, maxSide: 480) else { return }
        let item = ClipItem(kind: .image, text: name, image: preview)
        // The original sits beside the history so pasting or dragging it back keeps full quality.
        if let full = Self.png(image, maxSide: nil), full.count <= Self.maxImage {
            try? FileManager.default.createDirectory(at: Self.images, withIntermediateDirectories: true)
            try? full.write(to: Self.original(item), options: [.atomic, .completeFileProtection])
        }
        history.add(item)
        save()
    }

    static let maxRich = 1_000_000
    static let maxImage = 25_000_000

    /// The full-size image if it was kept, else the preview.
    private func image(_ item: ClipItem) -> NSImage? {
        NSImage(contentsOf: Self.original(item)) ?? item.image.flatMap(NSImage.init(data:))
    }

    /// For dragging an item out of the notch into any app.
    func dragItem(_ item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            // shortcut: drags the first file only (SwiftUI's onDrag takes one provider); copy puts them all back.
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

    private func save() {
        // shortcut: plain JSON in the sandbox container (FileVault protects it at rest); encrypt with a Keychain key if
        // the history ever leaves this Mac or holds more than 50 items.
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(history).write(to: Self.file, options: [.atomic, .completeFileProtection])
        // Originals of images that fell off the end, were removed or cleared go too.
        let kept = Set(history.items.map { Self.original($0).lastPathComponent })
        for url in (try? FileManager.default.contentsOfDirectory(at: Self.images, includingPropertiesForKeys: nil)) ?? []
        where !kept.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// PNG of the image, shrunk so its longest side is at most `maxSide` points (nil keeps full size).
    private static func png(_ image: NSImage, maxSide: CGFloat?) -> Data? {
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
