// © Pexilim
import SwiftUI

/// Swift side of `design/tokens.json`. `TokensTests` checks every value here against the JSON,
/// so the JSON stays the source of truth.
public enum Tokens {
    public struct Spring: Sendable, Equatable {
        public let response: Double
        public let damping: Double
        public var animation: Animation { .spring(response: response, dampingFraction: damping) }
    }

    public struct Timing: Sendable, Equatable {
        public let dur: Double
    }

    public enum Motion {
        public static let eyeShape = Spring(response: 0.22, damping: 0.9)
        public static let success = Spring(response: 0.4, damping: 0.6)
        public static let focus = Spring(response: 0.5, damping: 1.0)

        public static let blinkClose = Timing(dur: 0.09)
        public static let blinkOpen = Timing(dur: 0.12)
        public static let blinkIntervalMin = 20.0
        public static let blinkIntervalMax = 40.0
        public static let doubleBlinkChance = 0.1
        public static let moodTint = Timing(dur: 0.25)
        public static let eyeShapeReduceMotion = Timing(dur: 0.15)
        public static let importantPulse = Timing(dur: 0.6)
        public static let morningOpen = Timing(dur: 0.8)
        public static let sleepyClose = Timing(dur: 1.2)
        public static let celebrateBurst = Timing(dur: 0.8)
        public static let celebrateMaxParticles = 30
        public static let thinkingCycle = Timing(dur: 1.6)
        public static let thinkingSlowDur = 3.2
        public static let thinkingSlowAfter = 10.0
        public static let thinkingFreezeAfter = 30.0
        public static let ambientFPS = 30.0
    }

    public enum Glow {
        public static let alpha = 0.55
        public static let blur = 10.0
    }
}
