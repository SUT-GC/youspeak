import Foundation
import AppKit

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Identifiable {
    case qwen   = "qwen"
    case doubao = "doubao"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen:   return "通义千问 (Qwen)"
        case .doubao: return "豆包 (Doubao)"
        }
    }

    var endpoint: String {
        switch self {
        case .qwen:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .doubao:
            return "https://ark.volcengine.com/api/v3/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .qwen:   return "qwen-turbo"
        case .doubao: return ""
        }
    }
}

// MARK: - SettingsManager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: ASR
    @Published var asrAPIKey: String {
        didSet { defaults.set(asrAPIKey, forKey: "asrAPIKey") }
    }

    // MARK: LLM
    @Published var llmProvider: LLMProvider {
        didSet { defaults.set(llmProvider.rawValue, forKey: "llmProvider") }
    }
    @Published var polishEnabled: Bool {
        didSet { defaults.set(polishEnabled, forKey: "polishEnabled") }
    }

    @Published var qwenAPIKey: String {
        didSet { defaults.set(qwenAPIKey, forKey: "qwenAPIKey") }
    }
    @Published var qwenModel: String {
        didSet { defaults.set(qwenModel, forKey: "qwenModel") }
    }

    @Published var doubaoAPIKey: String {
        didSet { defaults.set(doubaoAPIKey, forKey: "doubaoAPIKey") }
    }
    @Published var doubaoModel: String {
        didSet { defaults.set(doubaoModel, forKey: "doubaoModel") }
    }

    // MARK: Hotkey
    @Published var hotkeyCode: Int {
        didSet { defaults.set(hotkeyCode, forKey: "hotkeyCode") }
    }
    @Published var hotkeyModifiers: UInt64 {
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    @Published var hotkeyLabel: String {
        didSet { defaults.set(hotkeyLabel, forKey: "hotkeyLabel") }
    }

    private init() {
        asrAPIKey     = defaults.string(forKey: "asrAPIKey")   ?? ""
        llmProvider   = LLMProvider(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .qwen
        polishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? true
        qwenAPIKey    = defaults.string(forKey: "qwenAPIKey")  ?? ""
        qwenModel     = defaults.string(forKey: "qwenModel")   ?? "qwen-turbo"
        doubaoAPIKey  = defaults.string(forKey: "doubaoAPIKey") ?? ""
        doubaoModel   = defaults.string(forKey: "doubaoModel") ?? ""

        // Read once and apply default (61 = right Option) when no value has been stored.
        let storedCode  = defaults.object(forKey: "hotkeyCode") as? Int
        hotkeyCode      = storedCode ?? 61
        hotkeyModifiers = (defaults.object(forKey: "hotkeyModifiers") as? UInt64) ?? 0
        hotkeyLabel     = defaults.string(forKey: "hotkeyLabel") ?? "右⌥"
    }

    // MARK: Computed

    var currentLLMAPIKey: String {
        switch llmProvider {
        case .qwen:   return qwenAPIKey
        case .doubao: return doubaoAPIKey
        }
    }

    var currentLLMModel: String {
        switch llmProvider {
        case .qwen:   return qwenModel
        case .doubao: return doubaoModel
        }
    }
}
