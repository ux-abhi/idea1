// © Pexilim
#if os(macOS)
import AppKit
import AVFAudio
import BlinkKit
import Carbon.HIToolbox
import CoreMedia
import Speech
import Synchronization

/// Dictation: speak, then Blink types it where you were typing. While you speak, the Mac's own model writes it down
/// and the sound is recorded (AAC, in a temporary file) for Groq's Whisper, which is far better at Hindi and Hinglish;
/// the Mac's text is the fallback when the server can't be reached. The file is deleted once used.
@Observable
final class Dictation {
    /// Typing what's said, or a voice command ("open Chrome and play Alphas"), which ends on its own after a pause.
    enum Purpose { case type, command }
    private(set) var isListening = false
    private(set) var purpose = Purpose.type
    /// Groq's Whisper (Settings › Shortcuts): off until the owner says yes, asked once on the first dictation.
    static let groqKey = "dictation.groq"
    static var usesGroq: Bool { UserDefaults.standard.object(forKey: groqKey) as? Bool ?? false }

    /// The first time: asks whether the recording may go to Groq (far better at Hindi and Hinglish), before anything is
    /// recorded, and puts the owner back in the app they were typing in.
    static func askGroqOnce() {
        guard UserDefaults.standard.object(forKey: groqKey) == nil else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Use Groq for speech to text?"
        alert.informativeText = "Groq's Whisper understands Hindi, Hinglish and accents far better than this Mac. Your recording goes through your server to Groq (your own key) and isn't kept. With “This Mac only”, nothing you say leaves the Mac. You can change this in Settings › Shortcuts."
        alert.addButton(withTitle: "Use Groq")
        alert.addButton(withTitle: "This Mac Only")
        UserDefaults.standard.set(alert.runModal() == .alertFirstButtonReturn, forKey: groqKey)
        previous?.activate()
    }
    /// Stopped and waiting for Groq's text.
    var isWriting = false
    private(set) var startedAt: Date?
    private var recording: Recording?
    private var starting = false
    private var engine: AVAudioEngine?
    private var feed: SpeechFeed?
    private var lines: [TranscriptLine] = []
    private var silenceWatch: Task<Void, Never>?

    /// Starts listening to the mic. Returns why it couldn't, in a sentence the owner can act on. `quiet` runs once the
    /// owner has spoken and then paused (commands end themselves this way).
    func start(language: Locale, purpose: Purpose = .type, quiet: (@MainActor () -> Void)? = nil) async -> String? {
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
            let level = Loudness()
            // On the audio thread: @Sendable keeps it off the main actor, where it would trap.
            mic.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, time in
                recording.write(buffer)
                level.hear(buffer)
                feed.listen(buffer, captured: CMClockMakeHostTimeFromSystemUnits(time.hostTime))
            }
            try engine.start()
            (self.engine, self.feed, self.recording, startedAt, isListening) = (engine, feed, recording, .now, true)
            self.purpose = purpose
            if let quiet {
                silenceWatch = Task { [weak self] in
                    while !Task.isCancelled, self?.isListening == true {
                        try? await Task.sleep(for: .milliseconds(200))
                        if level.paused(after: .now) { quiet(); return }
                    }
                }
            }
            return nil
        } catch {
            await started?.finish()
            return "Couldn't start dictation: \(error.localizedDescription)"
        }
    }

    /// Stops the mic and returns the recording (nil if empty) at once, so it can be sent while the Mac's own model is
    /// still finishing; the caller deletes the recording.
    func stopRecording() -> URL? {
        guard isListening else { return nil }
        isListening = false
        silenceWatch?.cancel()
        silenceWatch = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let audio = recording?.close()
        recording = nil
        return audio
    }

    /// What the Mac heard (filler sounds removed), once its model has written the last words.
    func macText() async -> String {
        guard let feed else { return "" }
        self.feed = nil // taken first, so a dictation started meanwhile keeps its own
        await feed.finish()
        return Dictated.clean(lines.sorted { $0.at < $1.at }.map(\.text).joined(separator: " "))
    }
}

/// How loud the mic is, to end a voice command once the owner stops talking: spoken, then 2 s quiet (a pause after
/// "Hey Blink" isn't the end); or nothing at all for 8 s. Written on the audio thread, read on the main one.
nonisolated private final class Loudness: Sendable {
    private struct State { var started = Date.now, lastLoud: Date? }
    private let state = Mutex(State())

    func hear(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        guard peak > 0.04 else { return } // about speaking level on a laptop mic; room noise stays under it
        state.withLock { $0.lastLoud = .now }
    }

    func paused(after now: Date) -> Bool {
        state.withLock { s in
            guard let lastLoud = s.lastLoud else { return now.timeIntervalSince(s.started) > 8 }
            return now.timeIntervalSince(lastLoud) > 2
        }
    }
}

/// The mic's sound as mono 16 kHz AAC in a temporary file (what Whisper hears anyway; a few KB a second). Mics can
/// have several channels (a MacBook's has 3), which the encoder can't take at a low rate, so the first one is kept.
/// Written on the audio thread only.
nonisolated private final class Recording: @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID().uuidString).m4a")
    private var file: AVAudioFile?
    private let converter: AVAudioConverter
    private let mono: AVAudioFormat
    private var frames: AVAudioFramePosition = 0

    init(format: AVAudioFormat) throws {
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: mono) else { throw CocoaError(.fileWriteUnknown) }
        (self.mono, self.converter) = (mono, converter)
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * mono.sampleRate / buffer.format.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: capacity) else { return }
        var given = false
        let status = converter.convert(to: out, error: nil) { _, state in
            if given { state.pointee = .noDataNow; return nil }
            given = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0, (try? file?.write(from: out)) != nil else { return }
        frames += AVAudioFramePosition(out.frameLength)
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

/// Types text into the app in front by pasting it: the text goes on the clipboard (and into clipboard history, so it
/// can be found with ⌃⌥V if no text box had the cursor), ⌘V is pressed, and what was on the clipboard comes back.
enum Paster {
    /// False when macOS hasn't allowed Blink to press keys (Accessibility): the text is left on the clipboard instead.
    static func paste(_ text: String) async -> Bool {
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
        let passing = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        board.clearContents()
        board.setString(text, forType: .string)
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
