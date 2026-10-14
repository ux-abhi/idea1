// © Pexilim
import Foundation

/// A model the owner can pick per feature in Settings. Server models must match MODELS in backend
/// functions/_shared/models.ts (the server falls back to Claude Opus for anything else); `onDeviceID` runs on the Mac.
public struct AIModel: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case onDevice = "On this Mac (free, private)", claude = "Claude", best = "Best (OpenRouter credit)", free = "Free (Groq)"
    }
    public let id: String
    public let name: String
    public let isFree: Bool
    public var group: Group { id == Self.onDeviceID ? .onDevice : isFree ? .free : id.hasPrefix("claude-") ? .claude : .best }

    /// Apple's on-device model (Apple Intelligence): chat only, answered on the Mac, no key, nothing leaves it.
    public static let onDeviceID = "apple-on-device"

    public static let all: [AIModel] = [
        AIModel(id: onDeviceID, name: "Apple Intelligence · on this Mac, free", isFree: true),
        AIModel(id: "claude-opus-5-5", name: "Claude Opus 5.5 · best", isFree: false),
        AIModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5 · balanced", isFree: false),
        AIModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5 · fast, cheapest Claude", isFree: false),
        AIModel(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B on Groq", isFree: true),
        AIModel(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B on Groq · fastest", isFree: true),
        AIModel(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B on Groq", isFree: true),
        AIModel(id: "qwen/qwen3.8-27b", name: "Qwen 3.8 27B on Groq", isFree: true),
        AIModel(id: "minimaxai/minimax-m2.7", name: "MiniMax M2.7 on Groq (preview)", isFree: true),
        AIModel(id: "openai/gpt-6.1-sol", name: "GPT-6.1 Sol · OpenAI's best", isFree: false),
        AIModel(id: "google/gemini-3.1-pro-preview", name: "Gemini 3.1 Pro · Google's best", isFree: false),
        AIModel(id: "moonshotai/kimi-k3", name: "Kimi K3 · top Chinese model", isFree: false),
        AIModel(id: "deepseek/deepseek-v4-pro", name: "DeepSeek V4 Pro · strong, very cheap", isFree: false),
    ]

    public static let defaultID = "claude-opus-5-5"

    /// Which model answers a feature. `serverPref` is what's saved on the server (server models only); the on-device
    /// choice is kept on this device, so server jobs that read the chat setting (mail drafts) keep their real model.
    /// With nothing picked, chat goes on-device only when Claude is known not to work, or the server can't be reached.
    public static func choose(feature: String, serverPref: String?, onDevicePicked: Bool, onDeviceReady: Bool,
                              claudeWorks: Bool?, serverReachable: Bool) -> String {
        if feature == "chat", onDevicePicked, onDeviceReady { return onDeviceID }
        if let serverPref, serverPref != onDeviceID, all.contains(where: { $0.id == serverPref }) { return serverPref }
        let noClaude = claudeWorks.map { !$0 } ?? !serverReachable
        return feature == "chat" && onDeviceReady && noClaude ? onDeviceID : defaultID
    }

    /// "Opus 5.5", "GPT-OSS 120B": the name without the provider and the note, for small places.
    public var shortName: String {
        name.components(separatedBy: " · ").first?
            .replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: " on Groq", with: "")
            .replacingOccurrences(of: "Apple Intelligence", with: "On-device")
            .replacingOccurrences(of: " (preview)", with: "") ?? name
    }
}
