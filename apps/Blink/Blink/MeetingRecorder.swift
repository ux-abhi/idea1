// © Pexilim
#if os(macOS)
import AVFAudio
import BlinkKit
import CoreMedia
import FoundationModels
import ScreenCaptureKit
import Speech

/// Meeting notes, all on this Mac: the owner's mic ("You") and the call's sound ("Others") are each turned into text by
/// Apple's speech model as the meeting goes; the sound itself is never stored. Stopping returns the lines; `summarize`
/// asks Apple's on-device model for a summary, decisions and next steps. Nothing here goes to a server.
@Observable
final class MeetingRecorder {
    private(set) var isRunning = false
    /// Between "take notes" and listening (the first time, a language download): a second start waits for this one.
    private(set) var isStarting = false
    private(set) var startedAt: Date?
    /// Paused: the sound still arrives (the Mac's mic light stays on) but none of it is turned into text.
    private(set) var isPaused = false
    /// The meeting being noted, if the calendar had one now.
    private(set) var meeting: AgendaEvent?

    private var stream: SCStream?
    private var feeds: [SpeechFeed] = []
    private var watcher: StopWatcher?
    private var lines: [TranscriptLine] = []
    private let queue = DispatchQueue(label: "blink.notes.audio")

    /// The language meetings are in (Settings › Meeting notes); the Mac's own language when nothing is picked.
    static let languageKey = "notes.language"
    static let languages: [(id: String, name: String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("en-IN", "English (India), also for Hinglish"),
        ("de-DE", "German"), ("hi-IN", "Hindi"),
    ]
    static var language: Locale {
        Locale(identifier: UserDefaults.standard.string(forKey: languageKey) ?? Locale.current.identifier(.bcp47))
    }

    /// Starts listening. Returns why it couldn't, in a sentence the owner can act on. `stopped` runs if capture ends on
    /// its own (screen unplugged, permission withdrawn), so the notes are saved and the red dot goes.
    func start(meeting: AgendaEvent?, language: Locale, stopped: @escaping @MainActor () -> Void) async -> String? {
        guard !isRunning, !isStarting else { return nil }
        isStarting = true
        defer { isStarting = false }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language) else {
            return "Speech-to-text on this Mac doesn't know \(language.identifier) yet. Pick another language in Settings › Meeting Notes."
        }
        lines = []
        let begin = Date.now
        // Both feeds time their audio from this moment on the host clock (the capture's own clock), so "You" and
        // "Others" lines interleave correctly even across silences.
        let origin = CMClockGetTime(CMClockGetHostTimeClock())
        var made: [SpeechFeed] = [] // every feed made so far, so a failure part-way ends them all
        func giveUp(_ reason: String) async -> String {
            for feed in made { await feed.finish() }
            return reason
        }
        do {
            let you = try await SpeechFeed(speaker: "You", locale: locale, origin: origin) { [weak self] in self?.lines.append($0) }
            made.append(you)
            let others = try await SpeechFeed(speaker: "Others", locale: locale, origin: origin) { [weak self] in self?.lines.append($0) }
            made.append(others)
            // The call's sound comes through screen capture (audio only: the picture is 2×2 once a second and unused).
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                return await giveUp("Blink couldn't find a screen to listen through.")
            }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true // Blink's own chimes stay out of the notes
            config.sampleRate = 48_000
            config.channelCount = 1
            config.captureMicrophone = true
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let watcher = StopWatcher(stopped: stopped)
            let stream = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []),
                                  configuration: config, delegate: watcher)
            try stream.addStreamOutput(others, type: .audio, sampleHandlerQueue: queue)
            // The 2×2 picture needs somewhere to go, or macOS logs "Dropping frame" every second; the feed ignores it.
            try stream.addStreamOutput(others, type: .screen, sampleHandlerQueue: queue)
            try stream.addStreamOutput(you, type: .microphone, sampleHandlerQueue: queue)
            try await stream.startCapture()
            (self.stream, self.watcher, feeds, startedAt, self.meeting, isRunning) = (stream, watcher, made, begin, meeting, true)
            return nil
        } catch let error as SCStreamError where error.code == .userDeclined {
            return await giveUp("Allow Blink in System Settings › Privacy & Security › Screen & System Audio Recording, so it can hear the call.")
        } catch {
            return await giveUp("Couldn't start the notes: \(error.localizedDescription)")
        }
    }

    /// Pauses or resumes: while paused nothing said is written down, and the transcript just has a gap.
    func setPaused(_ paused: Bool) {
        guard isRunning, paused != isPaused else { return }
        isPaused = paused
        let feeds = feeds
        queue.async { for feed in feeds { feed.paused = paused } }
    }

    /// Stops listening and returns every line heard, in time order.
    func stop() async -> [TranscriptLine] {
        guard isRunning else { return [] }
        (isRunning, isPaused) = (false, false)
        try? await stream?.stopCapture()
        (stream, watcher) = (nil, nil)
        for feed in feeds { await feed.finish() } // the last words are written out before this returns
        feeds = []
        return lines.sorted { $0.at < $1.at }
    }

    // MARK: Summary, on this Mac

    @Generable
    struct Digest {
        @Guide(description: "Two to four sentences: what the meeting was about and where it ended.")
        var summary: String
        @Guide(description: "What was decided, one short line each. Empty if nothing was decided.")
        var decisions: [String]
        @Guide(description: "Who does what next, one short line each, starting with the person's name if said. Empty if none.")
        var actions: [String]
    }

    /// The summary from Apple's on-device model, piece by piece (its window is small), then joined. Nil and a reason
    /// when it can't (Apple Intelligence off, the language unsupported, or the model refused).
    static func summarize(_ transcript: String, language: Locale) async -> (MeetingDigest?, String?) {
        if let problem = OnDeviceChat.problem { return (nil, "No summary: \(problem)") }
        // Hindi comes out of speech-to-text in Latin letters (Hinglish), which the model can't write yet: it summarises
        // in English instead (tested 2026-11-06: the gist comes through, some words stay untranslated), and says so.
        let native = (try? await SystemLanguageModel.default.supportsLocale(language)) == true
        let rules = """
        You take meeting notes. Read the transcript ("You" is the owner, "Others" is everyone else on the call) and \
        write \(native ? "in the transcript's language" : "in English (the transcript may be Hindi in Latin letters)"). \
        Only use what was said; never invent names, dates or numbers. Decisions are what was agreed; next steps are \
        tasks someone will do. Don't repeat a decision as a next step.
        """
        // shortcut: 6,000 characters per piece fits the ~4,000-token window for English and German; Hindi uses more
        // tokens per character, so a long Hindi piece can still overflow (skipped below). Measure and shrink if it does.
        // A piece the model refuses or can't fit is skipped, not the whole summary.
        var partial: [Digest] = []
        var lastError: Error?
        for piece in MeetingNotes.chunks(transcript, size: 6_000) {
            do { partial.append(try await LanguageModelSession(instructions: rules).respond(to: "Transcript:\n\(piece)", generating: Digest.self).content) }
            catch { lastError = error }
        }
        guard !partial.isEmpty else {
            return (nil, "No summary: Apple's on-device model couldn't write one (\(lastError?.localizedDescription ?? "no text")). The transcript is below.")
        }
        var caveat = native ? nil : "Summary in English, written on this Mac from a language it's still learning: check it against the transcript."
        if lastError != nil { caveat = [caveat, "Part of the meeting couldn't be summarised; the transcript has all of it."].compactMap { $0 }.joined(separator: " ") }
        guard partial.count > 1 else { return (partial.first.map(digest), caveat) }
        let parts = partial.map(\.summary)
        let joined = parts.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        // A very long meeting's parts may not fit one more call: then the parts themselves are the summary.
        let whole = (try? await LanguageModelSession(instructions: rules)
            .respond(to: "Write one summary of the whole meeting from these parts, in order:\n\(joined)", generating: Digest.self).content.summary)
            ?? parts.joined(separator: "\n\n")
        return (MeetingDigest(summary: whole, decisions: partial.flatMap(\.decisions), actions: partial.flatMap(\.actions)), caveat)
    }

    private static func digest(_ d: Digest) -> MeetingDigest {
        MeetingDigest(summary: d.summary, decisions: d.decisions, actions: d.actions)
    }
}

/// Tells the recorder when capture stops on its own. Called by ScreenCaptureKit off the main thread.
nonisolated private final class StopWatcher: NSObject, SCStreamDelegate, Sendable {
    private let stopped: @MainActor () -> Void
    init(stopped: @escaping @MainActor () -> Void) { self.stopped = stopped }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in stopped() }
    }
}

/// One voice source (mic or call sound) turned into text: audio in, finished lines out (to the main actor). Used by
/// meeting notes (ScreenCaptureKit) and dictation (the mic through AVAudioEngine).
/// nonisolated: audio arrives on an audio thread, and a main-actor class would trap there.
nonisolated final class SpeechFeed: NSObject, SCStreamOutput, @unchecked Sendable {
    private let speaker: String
    private let origin: CMTime
    private let analyzer: SpeechAnalyzer
    private let target: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var results: Task<Void, Never>?
    // Touched only on the one thread audio arrives on (the capture queue, or the mic's tap).
    private var converter: AVAudioConverter?
    /// Where the last buffer ended: the analyzer refuses audio that starts before that (conversion rounding would).
    private var nextStart = CMTime.zero
    /// Paused notes: buffers are dropped here, before any speech-to-text.
    var paused = false

    init(speaker: String, locale: Locale, origin: CMTime, heard: @escaping @MainActor (TranscriptLine) -> Void) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // The language model downloads once per language (a short wait the first time).
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await download.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CocoaError(.featureUnsupported)
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        (self.speaker, self.origin, self.target, self.input) = (speaker, origin, format, input)
        analyzer = SpeechAnalyzer(modules: [transcriber])
        super.init()
        try await analyzer.start(inputSequence: stream)
        results = Task { [speaker] in
            do {
                for try await result in transcriber.results where result.isFinal {
                    let line = TranscriptLine(speaker: speaker, at: result.range.start.seconds, text: String(result.text.characters))
                    await heard(line)
                }
            } catch {} // the analyzer finished or was cancelled: what was heard is already delivered
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone, buffer.isValid, let pcm = Self.pcm(buffer) else { return }
        listen(pcm, captured: buffer.presentationTimeStamp)
    }

    /// Audio captured at `captured` on the host clock, into the speech model (dropped while paused).
    func listen(_ pcm: AVAudioPCMBuffer, captured: CMTime) {
        guard !paused, let converted = convert(pcm) else { return }
        let (at, end) = MeetingNotes.bufferTime(captured: captured, origin: origin, frames: Int64(converted.frameLength),
                                                rate: CMTimeScale(target.sampleRate), previousEnd: nextStart)
        nextStart = end
        input.yield(AnalyzerInput(buffer: converted, bufferStartTime: at))
    }

    /// Ends the input and waits for the last words.
    func finish() async {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await results?.value
    }

    /// The sample buffer's audio as a PCM buffer in its own format.
    private static func pcm(_ buffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard var description = buffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &description) else { return nil }
        let frames = AVAudioFrameCount(buffer.numSamples)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(buffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }

    /// Into the format the speech model wants (usually 16 kHz mono); a new converter if the source format changes
    /// (another mic plugged in).
    private func convert(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format == target { return pcm }
        if converter?.inputFormat != pcm.format { converter = AVAudioConverter(from: pcm.format, to: target) }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * target.sampleRate / pcm.format.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var given = false
        let status = converter.convert(to: out, error: nil) { _, state in
            if given { state.pointee = .noDataNow; return nil }
            given = true
            state.pointee = .haveData
            return pcm
        }
        return status == .error ? nil : out
    }
}
#endif
