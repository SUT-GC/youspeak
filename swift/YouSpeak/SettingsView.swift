import SwiftUI

struct SettingsView: View {
    @ObservedObject private var s = SettingsManager.shared
    @State private var selectedTab: Tab = .asr
    @State private var isCapturing = false

    enum Tab: String, CaseIterable {
        case asr    = "语音识别"
        case llm    = "文本润色"
        case hotkey = "快捷键"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch selectedTab {
                case .asr:    asrTab
                case .llm:    llmTab
                case .hotkey: hotkeyTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - ASR

    private var asrTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("DashScope API Key", systemImage: "key.fill")
                .font(.subheadline.bold())

            APIKeyField("sk-…", text: $s.asrAPIKey)

            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.caption2)
                Text("在 dashscope.console.aliyun.com 申请，有免费额度")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Divider()

            Toggle(isOn: $s.debugEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("调试模式").font(.subheadline.bold())
                    Text("录音自动保存为 WAV，历史页可播放对比")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !SpeechController.shared.history.isEmpty || s.debugEnabled {
                Button(role: .destructive) {
                    SpeechController.shared.clearHistory()
                } label: {
                    Label("清理所有历史与音频缓存", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    // MARK: - LLM

    private var llmTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("启用文本润色", isOn: $s.polishEnabled)
                .font(.subheadline.bold())

            if s.polishEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Label("通义千问 (Qwen) API Key", systemImage: "key.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    APIKeyField("sk-…", text: $s.qwenAPIKey)
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.caption2)
                        Text("在 dashscope.console.aliyun.com 申请，模型默认使用 qwen-turbo")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .animation(.default, value: s.polishEnabled)
    }

    // MARK: - Hotkey

    private var hotkeyTab: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("当前快捷键").font(.subheadline.bold())
                Text("点击下方框，再按想绑定的按键").font(.caption).foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isCapturing ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isCapturing ? 2 : 1
                    )
                Text(s.hotkeyLabel)
                    .font(.title2.monospaced().bold())
                    .foregroundStyle(isCapturing ? Color.accentColor : Color.primary)
            }
            .frame(width: 200, height: 56)
            .onTapGesture { isCapturing = true }
            .background(
                HotkeyCapture(isActive: $isCapturing) { code, mods, label in
                    s.hotkeyCode      = Int(code)
                    s.hotkeyModifiers = mods.rawValue
                    s.hotkeyLabel     = label
                    isCapturing       = false
                }
            )

            Text(isCapturing ? "按下你想要的按键组合…" : "点击上方框后按任意键")
                .font(.caption)
                .foregroundStyle(isCapturing ? Color.accentColor : Color.secondary)

            Button("重置为 右⌥") {
                s.hotkeyCode      = 61
                s.hotkeyModifiers = 0
                s.hotkeyLabel     = "右⌥"
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
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
        guard flags.rawValue != 0 else { return }
        let label = modifierLabel(keyCode: code)
        guard !label.isEmpty else { return }
        onCapture?(code, flags, label)
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
        .frame(width: 420, height: 420)
}
