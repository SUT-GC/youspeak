import SwiftUI

struct MainView: View {
    @ObservedObject private var speech   = SpeechController.shared
    @ObservedObject private var settings = SettingsManager.shared
    // Hotkey active state — updated via HotkeyManager.onActiveChange callback
    @State private var hotkeyActive = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusCard
            Divider()

            // Permission warning — shown when CGEventTap isn't running
            if !hotkeyActive {
                permissionBanner
                Divider()
            }

            // API Key warning
            if settings.asrAPIKey.isEmpty {
                setupBanner
                Divider()
            }

            footer
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Sync initial state and subscribe to changes
            if let mgr = AppDelegate.shared?.hotkeyManager {
                hotkeyActive = mgr.isActive
                mgr.onActiveChange = { active in
                    DispatchQueue.main.async { hotkeyActive = active }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("YouSpeak")
                    .font(.title2.bold())
                Text("语音输入工具")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: statusIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline)
                Text(statusHint).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var statusColor: Color {
        guard hotkeyActive else { return .gray }
        switch speech.state {
        case .idle:       return .green
        case .recording:  return .red
        case .processing: return .orange
        }
    }

    private var statusIcon: String {
        guard hotkeyActive else { return "mic.slash" }
        switch speech.state {
        case .idle:       return "mic"
        case .recording:  return "mic.fill"
        case .processing: return "ellipsis.circle"
        }
    }

    private var statusTitle: String {
        guard hotkeyActive else { return "快捷键未就绪" }
        switch speech.state {
        case .idle:       return "待机中"
        case .recording:  return "录音中…"
        case .processing: return "识别中…"
        }
    }

    private var statusHint: String {
        guard hotkeyActive else { return "请授权辅助功能权限（见下方提示）" }
        switch speech.state {
        case .idle:
            return settings.asrAPIKey.isEmpty
                ? "请先在设置中填入 API Key"
                : "按住 \(settings.hotkeyLabel) 开始说话"
        case .recording:  return "松开按键结束录音"
        case .processing: return "正在转写，请稍候…"
        }
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("需要辅助功能权限").font(.caption).bold()
                Text("系统设置 → 隐私与安全性 → 辅助功能 → 开启 YouSpeak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("去开启") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.07))
    }

    // MARK: - API Key banner

    private var setupBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("未设置 DashScope API Key，语音识别无法使用。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("去设置") { AppDelegate.shared?.openSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                AppDelegate.shared?.openSettings()
            } label: {
                Label("设置", systemImage: "gearshape").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            Spacer()
            Text("v1.0")
                .font(.caption2)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    MainView()
}
