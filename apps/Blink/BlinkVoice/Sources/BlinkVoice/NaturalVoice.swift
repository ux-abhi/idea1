// © Pexilim
import AVFoundation
import CryptoKit
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary
import Observation

/// Blink's natural voice: the Kokoro-82M model speaking on this Mac (nothing leaves it). The 327 MB model is downloaded
/// once, checked against its published checksum, and kept in Application Support; six voices ship with the app.
@MainActor @Observable
public final class NaturalVoice {
    public static let shared = NaturalVoice()

    /// The voices that ship with Blink: id ("af_heart") and the name shown in Settings.
    public static let voices: [(id: String, name: String)] = [
        ("af_heart", "Heart · American, warm"), ("af_bella", "Bella · American"), ("am_michael", "Michael · American"),
        ("am_fenrir", "Fenrir · American, deep"), ("bf_emma", "Emma · British"), ("bm_george", "George · British"),
    ]

    /// Where the model comes from, and what it must hash to: the Apache-2.0 Kokoro-82M weights in MLX form.
    nonisolated static let modelURL = URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors")!
    nonisolated static let modelSHA256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
    nonisolated static let modelBytes: Int64 = 327_115_152

    public enum State: Equatable { case notDownloaded, downloading(Double), ready, failed(String) }
    public private(set) var state: State = .notDownloaded

    @ObservationIgnored private var engine: KokoroTTS?
    @ObservationIgnored private var styles: [String: MLXArray] = [:]
    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: Double(KokoroTTS.Constants.samplingRate), channels: 1)!
    @ObservationIgnored private var speaking: Task<Void, Never>?

    private init() {
        audio.attach(player)
        audio.connect(player, to: audio.mainMixerNode, format: format)
        if FileManager.default.fileExists(atPath: Self.localModel.path) { state = .ready }
    }

    nonisolated static var localModel: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Blink/Voice", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "kokoro-v1_0.safetensors")
    }

    /// Downloads the model once, with progress, and keeps it only if its checksum matches.
    public func download() async {
        guard state != .ready, !state.isDownloading else { return }
        set(.downloading(0))
        let progress = DownloadProgress { [weak self] fraction in
            Task { @MainActor in if self?.state.isDownloading == true { self?.set(.downloading(fraction)) } }
        }
        do {
            let (file, response) = try await URLSession.shared.download(from: Self.modelURL, delegate: progress)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Problem.message("The voice download didn't start. Try again later.") }
            // Checked in 1 MB pieces off the main actor: 327 MB never sits in memory at once.
            let digest = try await Task.detached(priority: .utility) { try Self.sha256(of: file) }.value
            guard digest == Self.modelSHA256 else {
                try? FileManager.default.removeItem(at: file)
                throw Problem.message("The voice download was damaged. Try again.")
            }
            try? FileManager.default.removeItem(at: Self.localModel)
            try FileManager.default.moveItem(at: file, to: Self.localModel)
            set(.ready)
        } catch {
            set(.failed((error as? Problem)?.text ?? "Couldn't download the voice. Check your connection and try again."))
        }
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Removes the downloaded model (Settings › "Remove voice").
    public func remove() {
        stop()
        engine = nil
        try? FileManager.default.removeItem(at: Self.localModel)
        set(.notDownloaded)
    }

    /// Speaks `text` in `voice`, replacing anything still being said. Returns false when the model isn't ready (the
    /// caller then uses the Mac's own voice).
    @discardableResult
    public func speak(_ text: String, voice: String) -> Bool {
        guard state == .ready else { return false }
        stop()
        let sentences = Self.pieces(of: text)
        speaking = Task { [weak self] in
            guard let self, let (tts, style) = await self.prepare(voice: voice) else { return }
            let language: Language = voice.hasPrefix("b") ? .enGB : .enUS
            for sentence in sentences {
                if Task.isCancelled { return }
                // The model runs off the main actor: the notch keeps moving while a sentence is made.
                let job = Speech(tts: tts, style: style, language: language, text: sentence)
                let samples = await Task.detached(priority: .userInitiated) { job.samples() }.value
                guard let samples, !samples.isEmpty, !Task.isCancelled else { continue }
                await self.play(samples)
            }
        }
        return true
    }

    public func stop() {
        speaking?.cancel()
        speaking = nil
        player.stop()
    }

    private func prepare(voice: String) async -> (KokoroTTS, MLXArray)? {
        if engine == nil {
            // Loading 327 MB of weights takes a moment: off the main actor, so the notch never freezes.
            let path = Self.localModel
            engine = await Task.detached(priority: .userInitiated) { Loaded(tts: KokoroTTS(modelPath: path)) }.value.tts
        }
        if styles.isEmpty, let file = Bundle.module.url(forResource: "voices", withExtension: "npz") {
            styles = NpyzReader.read(fileFromPath: file) ?? [:]
        }
        guard let engine, let style = styles[voice + ".npy"] ?? styles["af_heart.npy"] else { return nil }
        return (engine, style)
    }

    private func play(_ samples: [Float]) async {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if !audio.isRunning { try? audio.start() }
        if !player.isPlaying { player.play() }
        await player.scheduleBuffer(buffer)
    }

    /// Sentences short enough for the model (510 phoneme tokens at most): split at sentence ends, then at commas.
    static func pieces(of text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            if s.count <= 300 { out.append(s); return }
            out += s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return out.isEmpty ? [text] : out
    }

    private func set(_ new: State) { state = new }

    enum Problem: Error { case message(String); var text: String { if case .message(let t) = self { t } else { "" } } }
}

/// The model and a voice handed to a background task. MLX isn't marked Sendable; one sentence at a time uses them.
private struct Speech: @unchecked Sendable {
    let tts: KokoroTTS
    let style: MLXArray
    let language: Language
    let text: String
    func samples() -> [Float]? { try? tts.generateAudio(voice: style, language: language, text: text).0 }
}

/// The model, loaded off the main actor and handed back.
private struct Loaded: @unchecked Sendable { let tts: KokoroTTS }

/// Download progress for the model, as a fraction.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : NaturalVoice.modelBytes
        report(Double(totalBytesWritten) / Double(total))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

extension NaturalVoice.State {
    var isDownloading: Bool { if case .downloading = self { true } else { false } }
}
