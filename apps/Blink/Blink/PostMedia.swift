// © Pexilim
import BlinkKit
import Foundation

/// A draft's image, kept on this Mac in the app's container (one JPEG per draft id).
/// shortcut: local only; move to a Supabase Storage bucket when posts publish through the platforms' APIs (§36.4).
enum PostMedia {
    nonisolated static var folder: URL { URL.applicationSupportDirectory.appending(path: "Blink/media", directoryHint: .isDirectory) }

    static func url(for id: String) -> URL { folder.appending(path: "\(id).jpg") }

    static func exists(for id: String) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    static func save(_ data: Data, for id: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: [.atomic, .completeFileProtection])
    }

    /// Deletes images whose draft is gone (archived or deleted) or was posted more than 30 days ago.
    /// Called only after the drafts loaded, so a failed load never empties the folder.
    nonisolated static func prune(keeping pieces: [ContentPiece], now: Date = .now) {
        let keep = Set(pieces.filter { $0.publishedAt.map { now.timeIntervalSince($0) < 30 * 86_400 } ?? true }.map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" && !keep.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
