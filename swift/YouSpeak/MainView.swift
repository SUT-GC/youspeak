import SwiftUI

struct MainView: View {
    @ObservedObject private var speech = SpeechController.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            header

            Divider()

            // ── Status ──
            statusCard

            Divider()

            // ── Setup hint (only if API key missing) ──
            if settings.asrAPIKey.isEmpty {
                setupBanner
                Divider()
            }

            // ── Footer ──
            footer
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
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
                Text(statusTitle)
                    .font(.headline)
                Text(statusHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var statusColor: Color {
        switch speech.state {
        case .idle:       return .green
        case .recording:  return .red
        case .processing: return .orange
        }
    }

    private var statusIcon: String {
        switch speech.state {
        case .idle:       return "mic.slash"
        case .recording:  return "mic.fill"
        case .processing: return "ellipsis.circle"
        }
    }

    private var statusTitle: String {
        switch speech.state {
        case .idle:       return "待机中"
        case .recording:  return "录音中…"
        case .processing: return "识别中…"
        }
    }

    private var statusHint: String {
        switch speech.state {
        case .idle:
            return settings.asrAPIKey.isEmpty
                ? "请先在设置中填入 API Key"
                : "按住 \(settings.hotkeyLabel) 开始说话"
        case .recording:  return "松开按键结束录音"
        case .processing: return "正在转写，请稍候…"
        }
    }

    // MARK: - Setup banner

    private var setupBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("未设置 DashScope API Key，语音识别无法使用。")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("去设置") {
                AppDelegate.shared?.openSettings()
            }
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
                Label("设置", systemImage: "gearshape")
                    .font(.callout)
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
