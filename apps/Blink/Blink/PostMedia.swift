// © Pexilim
import Foundation

/// A draft's image, kept on this Mac in the app's container (one JPEG per draft id).
/// shortcut: local only; move to a Supabase Storage bucket when posts publish through the platforms' APIs (§36.4).
enum PostMedia {
    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Blink/media", directoryHint: .isDirectory) }

    static func url(for id: String) -> URL { folder.appending(path: "\(id).jpg") }

    static func exists(for id: String) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    static func save(_ data: Data, for id: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: [.atomic, .completeFileProtection])
    }
}
