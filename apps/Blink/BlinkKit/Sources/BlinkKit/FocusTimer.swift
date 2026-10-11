// © Pexilim
import Foundation

/// A running Pomodoro phase or a plain timer. Stored as times, not a ticking count, so it survives a restart.
public struct FocusTimer: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case focus, shortBreak, longBreak, timer }

    public var kind: Kind
    public var label: String
    public var duration: TimeInterval
    /// When it was (re)started; nil while paused.
    public var startedAt: Date?
    /// Time already used before the last start (pauses add up here).
    public var usedBeforeStart: TimeInterval
    /// Completed focus rounds in this Pomodoro run (a long break comes after every 4th).
    public var round: Int

    public static let focusLength: TimeInterval = 25 * 60
    public static let shortBreakLength: TimeInterval = 5 * 60
    public static let longBreakLength: TimeInterval = 15 * 60

    public init(kind: Kind, label: String, duration: TimeInterval, startedAt: Date? = .now, round: Int = 0) {
        self.kind = kind
        self.label = label
        self.duration = duration
        self.startedAt = startedAt
        usedBeforeStart = 0
        self.round = round
    }

    public static func focus(round: Int = 0, now: Date = .now) -> FocusTimer {
        FocusTimer(kind: .focus, label: "Focus", duration: focusLength, startedAt: now, round: round)
    }

    public static func timer(minutes: Double, now: Date = .now) -> FocusTimer {
        FocusTimer(kind: .timer, label: "Timer", duration: minutes * 60, startedAt: now)
    }

    public var isPaused: Bool { startedAt == nil }

    public func used(now: Date) -> TimeInterval {
        usedBeforeStart + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    public func remaining(now: Date) -> TimeInterval { max(duration - used(now: now), 0) }
    public func progress(now: Date) -> Double { duration > 0 ? min(used(now: now) / duration, 1) : 1 }
    public func isFinished(now: Date) -> Bool { remaining(now: now) <= 0 }
    public func endsAt(now: Date) -> Date? { startedAt.map { _ in now.addingTimeInterval(remaining(now: now)) } }

    public mutating func pause(now: Date) {
        guard let startedAt else { return }
        usedBeforeStart += now.timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    public mutating func resume(now: Date) {
        if startedAt == nil { startedAt = now }
    }

    public mutating func add(minutes: Double) { duration += minutes * 60 }

    /// What follows this phase in a Pomodoro run; plain timers have nothing next.
    public func next(now: Date) -> FocusTimer? {
        switch kind {
        case .focus:
            let done = round + 1
            return done % 4 == 0
                ? FocusTimer(kind: .longBreak, label: "Long break", duration: Self.longBreakLength, startedAt: now, round: done)
                : FocusTimer(kind: .shortBreak, label: "Break", duration: Self.shortBreakLength, startedAt: now, round: done)
        case .shortBreak, .longBreak:
            return .focus(round: round, now: now)
        case .timer:
            return nil
        }
    }

    /// "18:42" or "1:02:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
