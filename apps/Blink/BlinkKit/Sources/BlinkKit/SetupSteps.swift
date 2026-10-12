// © Pexilim
import Foundation

/// What a new owner still has to set up (ARCHITECTURE §36.2 onboarding: "Setup 3/7" with just-in-time cards). Each step
/// says what's missing in a few words and where to fix it; the app shows the ones not done.
public struct SetupStep: Identifiable, Equatable, Sendable {
    public enum ID: String, CaseIterable, Sendable { case aiKey, calendar, handle, mail, money, habit }
    /// Where the fix is: a window page ("content", "money"…) or a Settings tab ("settings:connections").
    public let id: ID
    public let title: String
    public let detail: String
    public let symbol: String
    public let action: String
    public let destination: String
    public let done: Bool

    /// Every step, in the order a new owner should do them. `keys` is Settings › Connections' status per key
    /// ("ok", "missing"…), nil while unknown.
    public static func all(keys: [String: String]?, calendarGranted: Bool, voicePage: String, mailConnected: Bool,
                           hasAccount: Bool, hasHabit: Bool) -> [SetupStep] {
        // A key counts as there unless the server says it's missing or refused; a provider that's briefly down isn't "no key".
        let ai = keys.map { k in ["groq", "anthropic", "openrouter"].contains { k[$0].map { $0 != "missing" && $0 != "rejected" } ?? false } } ?? true
        return [
            SetupStep(id: .aiKey, title: "Add an AI key", detail: "Chat, drafts and sorting need Groq (free) or Claude",
                      symbol: "key", action: "Add Key", destination: "settings:connections", done: ai),
            SetupStep(id: .calendar, title: "Allow Calendar", detail: "Your meetings in the notch and on Today",
                      symbol: "calendar", action: "Allow", destination: "settings:calendar", done: calendarGranted),
            SetupStep(id: .handle, title: "Add your Instagram handle", detail: "Drafts in your voice and post stats",
                      symbol: "at", action: "Add Handle", destination: "content", done: voicePage.contains("@")),
            SetupStep(id: .mail, title: "Connect mail", detail: "Important mail sorted for you",
                      symbol: "envelope", action: "Connect", destination: "inbox", done: mailConnected),
            SetupStep(id: .money, title: "Add a bank account", detail: "See what you have and how long it lasts",
                      symbol: "building.columns", action: "Add Account", destination: "money", done: hasAccount),
            SetupStep(id: .habit, title: "Track a habit", detail: "Streaks that keep you going",
                      symbol: "checkmark.circle", action: "Add Habit", destination: "tasks", done: hasHabit),
        ]
    }
}
