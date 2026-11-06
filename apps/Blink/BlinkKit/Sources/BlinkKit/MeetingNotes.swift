// © Pexilim
import CoreMedia
import Foundation

/// One finished stretch of speech: who (the owner's mic is "You", the call's sound "Others"), when, and what.
public struct TranscriptLine: Equatable, Sendable {
    public let speaker: String
    /// Seconds from the start of the notes.
    public let at: TimeInterval
    public let text: String

    public init(speaker: String, at: TimeInterval, text: String) {
        (self.speaker, self.at, self.text) = (speaker, at, text)
    }
}

/// What the summary step returns: a few sentences, what was decided, and who does what next.
public struct MeetingDigest: Equatable, Sendable {
    public var summary: String
    public var decisions: [String]
    public var actions: [String]

    public init(summary: String, decisions: [String] = [], actions: [String] = []) {
        (self.summary, self.decisions, self.actions) = (summary, decisions, actions)
    }
}

/// Meeting notes taken on the Mac: the note's title, its text, and the pieces the small on-device model can read.
public enum MeetingNotes {
    /// "Weekly sync · 6 Nov" for a calendar meeting, "Meeting notes · 6 Nov, 14:05" without one.
    public static func title(meeting: String?, start: Date) -> String {
        let day = start.formatted(.dateTime.day().month(.abbreviated))
        guard let meeting = meeting?.trimmingCharacters(in: .whitespacesAndNewlines), !meeting.isEmpty else {
            return "Meeting notes · \(day), \(start.formatted(.dateTime.hour().minute()))"
        }
        return "\(meeting) · \(day)"
    }

    /// The transcript in time order, one paragraph per turn: a speaker's lines in a row are joined.
    /// "You (0:03): Hello there. Shall we start?"
    public static func transcript(_ lines: [TranscriptLine]) -> String {
        var turns: [(speaker: String, at: TimeInterval, text: String)] = []
        for line in lines.sorted(by: { $0.at < $1.at }) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last, last.speaker == line.speaker {
                turns[turns.count - 1].text += " " + text
            } else {
                turns.append((line.speaker, line.at, text))
            }
        }
        return turns.map { "\($0.speaker) (\(clock($0.at))): \($0.text)" }.joined(separator: "\n")
    }

    /// "0:03", "12:40", "1:05:09".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The transcript cut into pieces of at most `size` characters, at line breaks (a single longer line is cut
    /// where it must), so each fits the on-device model's small window.
    public static func chunks(_ text: String, size: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            var rest = Substring(line)
            while rest.count > size { // a very long turn: cut it
                if !current.isEmpty { pieces.append(current); current = "" }
                pieces.append(String(rest.prefix(size)))
                rest = rest.dropFirst(size)
            }
            if !current.isEmpty && current.count + 1 + rest.count > size { pieces.append(current); current = "" }
            current += current.isEmpty ? String(rest) : "\n" + rest
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// When a buffer of `frames` samples (at `rate` a second) starts and ends on the speech analyzer's timeline: from the
    /// capture clock, so a silence leaves a gap, but never before the previous buffer's end (the analyzer refuses
    /// overlapping audio, and format conversion rounding would cause it). Counted in samples, so lengths add up exactly.
    public static func bufferTime(captured: CMTime, origin: CMTime, frames: Int64, rate: CMTimeScale,
                                  previousEnd: CMTime) -> (start: CMTime, end: CMTime) {
        let fromClock = CMTimeConvertScale(CMTimeSubtract(captured, origin), timescale: rate, method: .roundTowardPositiveInfinity)
        let start = CMTimeMaximum(CMTimeMaximum(fromClock, .zero), previousEnd)
        return (start, CMTimeAdd(start, CMTime(value: frames, timescale: rate)))
    }

    /// The note: who was there, a word on the summary if needed, the summary, decisions, next steps, then the transcript.
    public static func body(attendees: [String], digest: MeetingDigest?, noSummary: String?, transcript: String) -> String {
        var parts: [String] = []
        if !attendees.isEmpty { parts.append("With: " + attendees.joined(separator: ", ")) }
        if let noSummary { parts.append(noSummary) } // why there's no summary, or what to check in it
        if let digest {
            parts.append("Summary\n" + digest.summary)
            if !digest.decisions.isEmpty { parts.append("Decided\n" + digest.decisions.map { "• " + $0 }.joined(separator: "\n")) }
            if !digest.actions.isEmpty { parts.append("Next steps\n" + digest.actions.map { "• " + $0 }.joined(separator: "\n")) }
        }
        parts.append("Transcript\n" + (transcript.isEmpty ? "Nothing was heard." : transcript))
        return parts.joined(separator: "\n\n")
    }
}
