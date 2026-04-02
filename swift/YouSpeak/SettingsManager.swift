import Foundation
import AppKit

// MARK: - SettingsManager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: ASR
    @Published var asrAPIKey: String {
        didSet { defaults.set(asrAPIKey, forKey: "asrAPIKey") }
    }

    // MARK: LLM
    @Published var polishEnabled: Bool {
        didSet { defaults.set(polishEnabled, forKey: "polishEnabled") }
    }
    @Published var qwenAPIKey: String {
        didSet { defaults.set(qwenAPIKey, forKey: "qwenAPIKey") }
    }

    // MARK: Debug
    @Published var debugEnabled: Bool {
        didSet { defaults.set(debugEnabled, forKey: "debugEnabled") }
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
        asrAPIKey     = defaults.string(forKey: "asrAPIKey") ?? ""
        polishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? true
        qwenAPIKey    = defaults.string(forKey: "qwenAPIKey") ?? ""
        debugEnabled  = defaults.object(forKey: "debugEnabled") as? Bool ?? false

        let storedCode  = defaults.object(forKey: "hotkeyCode") as? Int
        hotkeyCode      = storedCode ?? 61
        hotkeyModifiers = (defaults.object(forKey: "hotkeyModifiers") as? UInt64) ?? 0
        hotkeyLabel     = defaults.string(forKey: "hotkeyLabel") ?? "右⌥"
    }
}
