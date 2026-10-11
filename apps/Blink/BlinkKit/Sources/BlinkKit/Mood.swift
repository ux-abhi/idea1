// © Pexilim
import SwiftUI

/// Blink's moods (ARCHITECTURE §7). Every mood = colour + eye shape + word, never colour alone.
public enum Mood: String, CaseIterable, Identifiable, Sendable {
    case idle, morning, headsUp, important, listening, thinking, done, concerned, focus, evening, sleepy, celebrate

    public var id: String { rawValue }

    /// The VoiceOver value and picker title.
    public var word: String {
        switch self {
        case .idle: "Resting"
        case .morning: "Good morning"
        case .headsUp: "Heads-up"
        case .important: "Important"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .done: "Done"
        case .concerned: "Needs you"
        case .focus: "Focus"
        case .evening: "Evening"
        case .sleepy: "Sleepy"
        case .celebrate: "Celebrating"
        }
    }

    public var tint: MoodTint {
        switch self {
        case .idle, .morning, .listening: .rest
        case .headsUp: .headsUp
        case .important: .important
        case .thinking: .thinking
        case .done: .done
        case .concerned: .attention
        case .evening: .evening
        case .focus, .sleepy: .dimmed
        case .celebrate: .celebrate
        }
    }

    public var pose: EyePose {
        switch self {
        case .idle, .morning: .pill
        case .headsUp, .important, .listening: .wide
        case .thinking: EyePose(openness: 0.82, lookY: -0.22)
        case .done, .celebrate: EyePose(openness: 0.9, bite: 1)
        case .concerned: EyePose(openness: 0.85, lid: 0.32, lidTilt: -18)
        case .focus: .closed
        case .evening: EyePose(openness: 0.8, lid: 0.28)
        case .sleepy: EyePose(openness: 0.8, lid: 0.55)
        }
    }
}

/// Mood colours. `token` is the `blink.mood.*` key in design/tokens.json.
public enum MoodTint: String, CaseIterable, Sendable {
    case rest, headsUp, important, thinking, done, attention, evening, celebrate, dimmed

    public var token: String? { self == .dimmed ? nil : "mood.\(rawValue)" }

    public var color: Color {
        switch self {
        case .rest: .white
        case .headsUp: .mint
        case .important: .red
        case .thinking: .indigo
        case .done: .green
        case .attention: .orange
        case .evening: .orange.opacity(0.85) // "low" intensity, still clear on black
        case .celebrate: .yellow
        case .dimmed: .white.opacity(0.55) // dim, but readable against the black notch
        }
    }

    /// The Apple colour this tint uses, matching the token's `maps` (rest is plain white in the JSON).
    public var appleName: String {
        switch self {
        case .rest, .dimmed: "white"
        case .headsUp: "systemMint"
        case .important: "systemRed"
        case .thinking: "systemIndigo"
        case .done: "systemGreen"
        case .attention, .evening: "systemOrange"
        case .celebrate: "systemYellow"
        }
    }
}

/// Eye geometry, all relative to the eye's box so it scales with the stage.
public struct EyePose: Equatable, Sendable {
    /// 1 = wide, ~0.82 = resting pill, ~0.08 = closed line.
    public var openness: Double
    /// 0 = pill, 1 = ∩ (bottom bitten out).
    public var bite: Double = 0
    /// Upper lid coming down, 0…1 of the eye height.
    public var lid: Double = 0
    /// Lid slope in degrees for the left eye (mirrored on the right); negative drops the outer corner.
    public var lidTilt: Double = 0
    /// Gaze, fraction of the eye height; negative looks up.
    public var lookY: Double = 0

    public static let pill = EyePose(openness: 0.82)
    public static let wide = EyePose(openness: 1)
    public static let closed = EyePose(openness: 0.08)
}
