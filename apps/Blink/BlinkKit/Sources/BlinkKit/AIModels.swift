// © Pexilim
import Foundation

/// A model the owner can pick per feature in Settings. Must match MODELS in backend functions/_shared/models.ts:
/// the server only ever calls models on its own list and falls back to Claude Opus for anything else.
public struct AIModel: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case claude = "Claude", best = "Best (OpenRouter credit)", free = "Free (Groq)"
    }
    public let id: String
    public let name: String
    public let isFree: Bool
    public var group: Group { isFree ? .free : id.hasPrefix("claude-") ? .claude : .best }

    public static let all: [AIModel] = [
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

    /// "Opus 5.5", "GPT-OSS 120B": the name without the provider and the note, for small places.
    public var shortName: String {
        name.components(separatedBy: " · ").first?
            .replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: " on Groq", with: "")
            .replacingOccurrences(of: " (preview)", with: "") ?? name
    }
}
