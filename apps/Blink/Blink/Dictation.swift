// © Pexilim
#if os(macOS)
import AppKit
import AVFAudio
import BlinkKit
import Carbon.HIToolbox
import CoreMedia
import Speech

/// Dictation: speak, then Blink types it where you were typing. While you speak, the Mac's own model writes it down
/// and the sound is recorded (AAC, in a temporary file) for Groq's Whisper, which is far better at Hindi and Hinglish;
/// the Mac's text is the fallback when the server can't be reached. The file is deleted once used.
@Observable
final class Dictation {
    private(set) var isListening = false
    /// Groq's Whisper (Settings › Shortcuts), on unless the owner keeps dictation on this Mac.
    static let groqKey = "dictation.groq"
    static var usesGroq: Bool { UserDefaults.standard.object(forKey: groqKey) as? Bool ?? true }
    /// Stopped and waiting for Groq's text.
    var isWriting = false
    private(set) var startedAt: Date?
    private var recording: Recording?
    private var starting = false
    private var engine: AVAudioEngine?
    private var feed: SpeechFeed?
    private var lines: [TranscriptLine] = []

    /// Starts listening to the mic. Returns why it couldn't, in a sentence the owner can act on.
    func start(language: Locale) async -> String? {
        guard !isListening, !starting else { return nil }
        starting = true
        defer { starting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            return "Allow Blink to use the microphone in System Settings › Privacy & Security › Microphone."
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language) else {
            return "Speech-to-text on this Mac doesn't know \(language.identifier) yet. Pick another language in Settings › General."
        }
        lines = []
        var started: SpeechFeed? // ended again if anything after it fails, so its speech model doesn't keep waiting
        do {
            let feed = try await SpeechFeed(speaker: "You", locale: locale, origin: CMClockGetTime(CMClockGetHostTimeClock())) { [weak self] in
                self?.lines.append($0)
            }
            started = feed
            let engine = AVAudioEngine()
            let mic = engine.inputNode
            let format = mic.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                await feed.finish()
                return "Blink can't find a microphone. Check System Settings › Sound › Input."
            }
            let recording = try Recording(format: format)
            // On the audio thread: @Sendable keeps it off the main actor, where it would trap.
            mic.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, time in
                recording.write(buffer)
                feed.listen(buffer, captured: CMClockMakeHostTimeFromSystemUnits(time.hostTime))
            }
            try engine.start()
            (self.engine, self.feed, self.recording, startedAt, isListening) = (engine, feed, recording, .now, true)
            return nil
        } catch {
            await started?.finish()
            return "Couldn't start dictation: \(error.localizedDescription)"
        }
    }

    /// Stops and returns what the Mac heard (filler sounds removed) and the recording (nil if empty); the caller
    /// deletes the recording.
    func stop() async -> (text: String, audio: URL?) {
        guard isListening else { return ("", nil) }
        isListening = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        await feed?.finish() // the last words come out before this returns
        feed = nil
        let audio = recording?.close()
        recording = nil
        return (Dictated.clean(lines.sorted { $0.at < $1.at }.map(\.text).joined(separator: " ")), audio)
    }
}

/// The mic's sound as AAC in a temporary file (about 4 KB a second). Written on the audio thread only.
nonisolated private final class Recording: @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID().uuidString).m4a")
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0

    init(format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 32_000,
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard (try? file?.write(from: buffer)) != nil else { return }
        frames += AVAudioFramePosition(buffer.frameLength)
    }

    /// Finishes the file; nil (and no file) when nothing was recorded.
    func close() -> URL? {
        file = nil // closing writes the end of the file
        guard frames > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}

/// Types text into the app in front by pasting it: the text goes on the clipboard (marked passing, so clipboard
/// history skips it), ⌘V is pressed, and what was on the clipboard comes back.
enum Paster {
    /// False when macOS hasn't allowed Blink to press keys (Accessibility): the text is left on the clipboard instead.
    static func paste(_ text: String) async -> Bool {
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
        let passing = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(), forType: passing)
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let key = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            key?.flags = .maskCommand
            key?.post(tap: .cghidEventTap)
        }
        // The app reads the clipboard when it handles ⌘V, a moment later; then the owner's clipboard comes back.
        try? await Task.sleep(for: .milliseconds(500))
        guard !saved.isEmpty else { return true }
        board.clearContents()
        board.writeObjects(saved.map { pairs in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            item.setData(Data(), forType: passing) // already in history: don't add it again
            return item
        })
        return true
    }
}
#endif
