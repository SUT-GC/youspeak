import SwiftUI

struct SettingsView: View {
    @ObservedObject private var s = SettingsManager.shared
    @State private var isCapturing = false

    var body: some View {
        TabView {
            asrTab.tabItem   { Label("语音识别", systemImage: "mic") }
            llmTab.tabItem   { Label("文本润色", systemImage: "wand.and.stars") }
            hotkeyTab.tabItem { Label("快捷键",   systemImage: "keyboard") }
        }
        .padding()
        .frame(width: 440, height: 300)
    }

    // MARK: - ASR

    private var asrTab: some View {
        Form {
            Section("DashScope API") {
                SecureField("API Key (sk-…)", text: $s.asrAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("在 dashscope.console.aliyun.com 获取")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - LLM

    private var llmTab: some View {
        Form {
            Toggle("启用文本润色", isOn: $s.polishEnabled)

            if s.polishEnabled {
                Picker("服务商", selection: $s.llmProvider) {
                    ForEach(LLMProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                switch s.llmProvider {
                case .qwen:
                    SecureField("Qwen API Key", text: $s.qwenAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型 (默认 qwen-turbo)", text: $s.qwenModel)
                        .textFieldStyle(.roundedBorder)
                case .doubao:
                    SecureField("豆包 API Key", text: $s.doubaoAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型 / Endpoint ID", text: $s.doubaoModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
        .animation(.default, value: s.llmProvider)
        .animation(.default, value: s.polishEnabled)
    }

    // MARK: - Hotkey

    private var hotkeyTab: some View {
        VStack(spacing: 16) {
            Text("当前快捷键").font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCapturing ? Color.accentColor : Color.secondary, lineWidth: 2)
                    .frame(width: 200, height: 50)
                Text(s.hotkeyLabel)
                    .font(.title2.monospaced())
            }
            .onTapGesture { isCapturing = true }
            .background(
                HotkeyCapture(isActive: $isCapturing) { code, mods, label in
                    s.hotkeyCode      = Int(code)
                    s.hotkeyModifiers = mods.rawValue
                    s.hotkeyLabel     = label
                    isCapturing       = false
                    // HotkeyManager was stopped when settings opened (AppDelegate).
                    // reload() will restart it with the new key.
                    AppDelegate.shared?.hotkeyManager.reload()
                }
            )

            if isCapturing {
                Text("按下你想要的按键组合…").foregroundColor(.accentColor)
            } else {
                Text("点击上方框后按任意键").foregroundColor(.secondary)
            }

            Button("重置为 右⌥") {
                s.hotkeyCode      = 61
                s.hotkeyModifiers = 0
                s.hotkeyLabel     = "右⌥"
                AppDelegate.shared?.hotkeyManager.reload()
            }
        }
        .padding()
    }
}

// MARK: - HotkeyCapture (NSViewRepresentable)

private struct HotkeyCapture: NSViewRepresentable {
    @Binding var isActive: Bool
    var onCapture: (CGKeyCode, CGEventFlags, String) -> Void

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let v = HotkeyCaptureView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ view: HotkeyCaptureView, context: Context) {
        if isActive {
            view.window?.makeFirstResponder(view)
        } else {
            // Resign so other controls can receive keyboard events normally.
            if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
        }
    }
}

final class HotkeyCaptureView: NSView {
    var onCapture: ((CGKeyCode, CGEventFlags, String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let code  = CGKeyCode(event.keyCode)
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        onCapture?(code, flags, keyLabel(event: event))
    }

    override func flagsChanged(with event: NSEvent) {
        // Capture standalone modifier keys (e.g. right Option alone as hotkey).
        let code = CGKeyCode(event.keyCode)
        guard code != 0 else { return }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        // Only fire when the modifier is being pressed, not when released.
        guard flags.rawValue != 0 else { return }
        let label = modifierKeyLabel(keyCode: code, flags: event.modifierFlags)
        guard !label.isEmpty else { return }
        onCapture?(code, flags, label)
    }

    // MARK: - Label helpers

    private func keyLabel(event: NSEvent) -> String {
        var parts: [String] = []
        let mods = event.modifierFlags
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            parts.append(chars)
        }
        return parts.joined()
    }

    /// Labels that distinguish left vs right modifier keys using the key code.
    private func modifierKeyLabel(keyCode: CGKeyCode, flags: NSEvent.ModifierFlags) -> String {
        switch keyCode {
        case 54: return "右⌘"
        case 55: return "左⌘"
        case 56: return "左⇧"
        case 57: return "⇪"    // Caps Lock
        case 58: return "左⌥"
        case 59: return "左⌃"
        case 60: return "右⇧"
        case 61: return "右⌥"
        case 62: return "右⌃"
        case 63: return "Fn"
        default: return ""
        }
    }
}

#Preview {
    SettingsView()
}
