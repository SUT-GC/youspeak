import SwiftUI

struct SettingsView: View {
    @ObservedObject private var s = SettingsManager.shared
    @State private var isCapturing = false

    var body: some View {
        TabView {
            asrTab.tabItem    { Label("语音识别", systemImage: "mic") }
            llmTab.tabItem    { Label("文本润色", systemImage: "wand.and.stars") }
            hotkeyTab.tabItem { Label("快捷键",   systemImage: "keyboard") }
        }
        .padding()
        .frame(width: 440, height: 300)
    }

    // MARK: - ASR

    private var asrTab: some View {
        Form {
            Section("DashScope API") {
                APIKeyField("API Key (sk-…)", text: $s.asrAPIKey)
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
                    APIKeyField("Qwen API Key", text: $s.qwenAPIKey)
                    TextField("模型 (默认 qwen-turbo)", text: $s.qwenModel)
                        .textFieldStyle(.roundedBorder)
                case .doubao:
                    APIKeyField("豆包 API Key", text: $s.doubaoAPIKey)
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
                    // Only persist settings here. HotkeyManager is currently stopped
                    // (AppDelegate stops it on openSettings); it will reload with the
                    // new values when the settings window closes.
                    s.hotkeyCode      = Int(code)
                    s.hotkeyModifiers = mods.rawValue
                    s.hotkeyLabel     = label
                    isCapturing       = false
                }
            )

            if isCapturing {
                Text("按下你想要的按键组合…").foregroundColor(.accentColor)
            } else {
                Text("点击上方框后按任意键").foregroundColor(.secondary)
            }

            Button("重置为 右⌥") {
                // Same: only update settings; reload happens on window close.
                s.hotkeyCode      = 61
                s.hotkeyModifiers = 0
                s.hotkeyLabel     = "右⌥"
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
        } else if view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
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
        let code = CGKeyCode(event.keyCode)
        guard code != 0 else { return }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        // Only fire on key-down (flags becoming non-zero for this key).
        guard flags.rawValue != 0 else { return }
        let label = modifierLabel(keyCode: code)
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

    /// Returns a label that distinguishes left vs right modifier keys by key code.
    private func modifierLabel(keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 54: return "右⌘"
        case 55: return "左⌘"
        case 56: return "左⇧"
        case 57: return "⇪"
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

// MARK: - APIKeyField
// SwiftUI's SecureField has a known paste bug on macOS.
// This wraps NSTextField directly to get reliable ⌘V / right-click paste.

struct APIKeyField: View {
    private let placeholder: String
    @Binding var text: String
    @State private var isVisible = false

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            if isVisible {
                NativeTextField(placeholder: placeholder, text: $text, isSecure: false)
                    .frame(height: 22)
            } else {
                NativeTextField(placeholder: placeholder, text: $text, isSecure: true)
                    .frame(height: 22)
            }
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(isVisible ? "隐藏" : "显示")
        }
    }
}

// NSViewRepresentable wrapper around NSTextField / NSSecureTextField.
// Unlike SwiftUI's SecureField, these respond correctly to ⌘V and
// right-click → Paste without any extra configuration.
private struct NativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        field.placeholderString  = placeholder
        field.isBordered         = true
        field.bezelStyle         = .roundedBezel
        field.delegate           = context.coordinator
        field.stringValue        = text
        field.cell?.isScrollable = true
        field.cell?.wraps        = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if text changed externally (avoid cursor-jump on every keystroke).
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { self._text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

#Preview {
    SettingsView()
}
