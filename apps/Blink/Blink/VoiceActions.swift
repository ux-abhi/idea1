// © Pexilim
#if os(macOS)
import AppKit
import AVFAudio
import BlinkKit
import BlinkVoice
import os

/// Does what a voice command asked: opens and quits apps, and opens links in a named browser (or the default one).
/// Only these things; the server has already turned searches and songs into links.
enum VoiceActions {
    private static let speaker = AVSpeechSynthesizer()

    /// Runs the actions in order. Returns a sentence when one couldn't be done (the rest still run).
    static func run(_ actions: [VoiceCommand.Action]) async -> String? {
        var problem: String?
        for action in actions {
            if action.type == "quit_app" {
                if let name = action.app, let why = quit(name) { problem = why }
                continue
            }
            let app = action.app.flatMap(find)
            if action.type == "open_app", app == nil {
                problem = "Couldn't find \(action.app ?? "that app") on this Mac."
                continue
            } // a link whose browser isn't here just opens in the default one
            let configuration = NSWorkspace.OpenConfiguration()
            do {
                switch action.type {
                case "open_app":
                    if let app { _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration) }
                case "open_url":
                    // The server sends web links only; checked again here, at the last step before macOS opens it.
                    guard let link = action.url.flatMap(URL.init(string:)), ["http", "https"].contains(link.scheme?.lowercased()) else { continue }
                    if let app { _ = try await NSWorkspace.shared.open([link], withApplicationAt: app, configuration: configuration) }
                    else { NSWorkspace.shared.open(link) }
                default: continue
                }
            } catch {
                problem = "Couldn't open \(action.app ?? "that"): \(error.localizedDescription)"
            }
        }
        return problem
    }

    /// Quits a running app by its name, the way ⌘Q does (it can still ask to save). A sentence when it can't.
    private static func quit(_ spoken: String) -> String? {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.localizedName != nil }
        guard let name = AppMatch.best(spoken, among: running.compactMap(\.localizedName)),
              let app = running.first(where: { $0.localizedName == name }) else { return "\(spoken) isn't open." }
        let asked = app.terminate()
        shortcutLog.info("voice: quit \(name, privacy: .public) → \(asked)")
        return asked ? nil : "macOS didn't let Blink quit \(name)."
    }

    /// Settings › Shortcuts › "Say replies out loud", and the natural voice picked there.
    static let speaksKey = "voice.speaks"
    static let naturalVoiceKey = "voice.natural"

    #if DEBUG
    /// `-voice.selftest YES` at launch (Debug builds): download the natural voice if needed and say one sentence,
    /// logging how long it took, so the voice can be checked without clicking through Settings.
    static func selfTestIfAsked() {
        guard UserDefaults.standard.bool(forKey: "voice.selftest") else { return }
        Task { @MainActor in
            let start = Date.now
            if NaturalVoice.shared.state != .ready { await NaturalVoice.shared.download() }
            shortcutLog.info("voice selftest: model \(String(describing: NaturalVoice.shared.state), privacy: .public) after \(Date.now.timeIntervalSince(start))s")
            let spoke = Date.now
            NaturalVoice.shared.speak("Hi, I'm Blink. This is my new natural voice.", voice: "af_heart")
            shortcutLog.info("voice selftest: speak called \(Date.now.timeIntervalSince(spoke))s")
        }
    }
    #endif

    /// Says the reply out loud, in the best voice installed for the Mac's language (a Premium or Enhanced one when the
    /// owner has downloaded it; the built-in compact voices sound robotic).
    static func say(_ text: String) {
        guard UserDefaults.standard.object(forKey: speaksKey) as? Bool ?? true else { return }
        speaker.stopSpeaking(at: .immediate)
        // The natural voice when it's downloaded; the Mac's own voice otherwise.
        let natural = UserDefaults.standard.string(forKey: naturalVoiceKey) ?? "af_heart"
        // Kokoro speaks English only: a Hindi (or German) reply keeps the Mac's voice, which knows the language.
        let english = (MeetingRecorder.language.language.languageCode?.identifier ?? "en") == "en"
        if english, NaturalVoice.shared.speak(text, voice: natural) { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice
        speaker.speak(utterance)
    }

    /// The highest-quality voice for the language the owner speaks to Blink in (English if none).
    static var bestVoice: AVSpeechSynthesisVoice? {
        let language = MeetingRecorder.language.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: nil)
    }

    /// The installed app a spoken name means, from the usual app folders.
    private static func find(_ spoken: String) -> URL? {
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        var byName: [String: URL] = [:]
        for folder in folders {
            for item in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where item.hasSuffix(".app") {
                byName[String(item.dropLast(4))] = byName[String(item.dropLast(4))] ?? URL(filePath: folder).appending(path: item)
            }
        }
        let match = AppMatch.best(spoken, among: Array(byName.keys))
        shortcutLog.info("voice: \(byName.count) apps seen, \(spoken, privacy: .public) → \(match ?? "none", privacy: .public)")
        return match.flatMap { byName[$0] }
    }
}
#endif
