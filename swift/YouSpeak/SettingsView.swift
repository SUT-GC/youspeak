import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject private var s = SettingsManager.shared
    @State private var isCapturing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            asrTab.tabItem { Label("语音识别", systemImage: "mic") }
            llmTab.tabItem { Label("文本润色", systemImage: "wand.and.stars") }
            hotkeyTab.tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .padding()
        .frame(width: 440, height: 320)
    }

    // MARK: - ASR

    private var asrTab: some View {
        Form {
            Section("DashScope API") {
                SecureField("API Key (sk-…)", text: $s.asrAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("在 [dashscope.console.aliyun.com](https://dashscope.console.aliyun.com) 获取")
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
            .background(HotkeyCapture(isActive: $isCapturing) { code, mods, label in
                s.hotkeyCode      = Int(code)
                s.hotkeyModifiers = mods.rawValue
                s.hotkeyLabel     = label
                isCapturing       = false
                AppDelegate.shared?.hotkeyManager.reload()
            })

            if isCapturing {
                Text("按下你想要的按键组合…")
                    .foregroundColor(.accentColor)
            } else {
                Text("点击上方框后按任意键设置")
                    .foregroundColor(.secondary)
            }

            Button("重置为 右⌥") {
                s.hotkeyCode      = 61
                s.hotkeyModifiers = 0
                s.hotkeyLabel     = "右 ⌥"
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
        if isActive { view.window?.makeFirstResponder(view) }
    }
}

final class HotkeyCaptureView: NSView {
    var onCapture: ((CGKeyCode, CGEventFlags, String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let code  = CGKeyCode(event.keyCode)
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let label = keyLabel(event: event)
        onCapture?(code, flags, label)
    }

    override func flagsChanged(with event: NSEvent) {
        // modifier-only keys
        guard event.keyCode != 0 else { return }
        let code  = CGKeyCode(event.keyCode)
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let label = modLabel(flags: event.modifierFlags)
        if !label.isEmpty { onCapture?(code, flags, label) }
    }

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

    private func modLabel(flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

#Preview {
    SettingsView()
}
