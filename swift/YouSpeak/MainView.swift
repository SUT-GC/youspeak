import SwiftUI
import AppKit
import AVFoundation

extension Notification.Name {
    static let showSettingsTab = Notification.Name("com.youspeak.showSettingsTab")
}

struct MainView: View {
    @ObservedObject private var speech   = SpeechController.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var hotkeyActive = false
    @State private var selectedTab: Tab = .home

    enum Tab { case home, history, settings }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:     homeTab
                case .history:  historyTab
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            tabBar
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { subscribeHotkey() }
        .onChange(of: selectedTab) { tab in
            switch tab {
            case .settings: AppDelegate.shared?.hotkeyManager.stop()
            default:        AppDelegate.shared?.hotkeyManager.reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsTab)) { _ in
            selectedTab = .settings
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(icon: "mic.fill",  label: "首页",   isSelected: selectedTab == .home)     { selectedTab = .home }
            TabBarButton(icon: "clock",     label: "历史",   isSelected: selectedTab == .history)  { selectedTab = .history }
            TabBarButton(icon: "gearshape", label: "设置",   isSelected: selectedTab == .settings) { selectedTab = .settings }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Home Tab

    private var homeTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                headerSection
                statusCard
                if !hotkeyActive   { permissionCard }
                if settings.asrAPIKey.isEmpty { setupCard }
                featureHighlights
            }
            .padding(16)
        }
    }

    // MARK: - History Tab

    private var historyTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("转录历史")
                    .font(.headline)
                Spacer()
                if !speech.history.isEmpty {
                    Button("清空") { speech.clearHistory() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if speech.history.isEmpty {
                emptyHistory
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(speech.history) { record in
                            HistoryRow(record: record)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("暂无转录记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("按住 \(settings.hotkeyLabel) 说话后，记录会出现在这里")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [.blue, Color(red: 0.4, green: 0.2, blue: 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("YouSpeak")
                    .font(.title3.bold())
                Text("按住快捷键对着麦克风说话，文字自动输入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: statusIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline)
                Text(statusHint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Alert Cards

    private var permissionCard: some View {
        alertCard(
            icon: "lock.shield.fill", iconColor: .red,
            title: "需要辅助功能权限",
            message: "系统设置 → 隐私与安全性 → 辅助功能 → 开启 YouSpeak",
            buttonLabel: "去开启"
        ) {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    private var setupCard: some View {
        alertCard(
            icon: "key.fill", iconColor: .orange,
            title: "未配置 API Key",
            message: "需要 DashScope API Key 才能使用语音识别",
            buttonLabel: "去设置"
        ) { selectedTab = .settings }
    }

    private func alertCard(
        icon: String, iconColor: Color,
        title: String, message: String,
        buttonLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(iconColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(iconColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(iconColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Feature Highlights

    private var featureHighlights: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("功能特色")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                FeatureTile(icon: "bolt.fill",        color: .yellow, title: "实时流式",   desc: "边说边出字")
                FeatureTile(icon: "wand.and.stars",   color: .purple, title: "AI 润色",   desc: "智能修正表达")
                FeatureTile(icon: "doc.on.clipboard", color: .blue,   title: "不走剪贴板", desc: "CGEvent 注入")
                FeatureTile(icon: "globe",            color: .green,  title: "全局生效",   desc: "任意输入框")
            }
        }
    }

    // MARK: - Status helpers

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
        guard hotkeyActive else { return "请授权辅助功能权限" }
        switch speech.state {
        case .idle:
            return settings.asrAPIKey.isEmpty
                ? "请先在设置中填入 API Key"
                : "按住 \(settings.hotkeyLabel) 开始说话"
        case .recording:  return "松开按键结束录音"
        case .processing: return "正在转写，请稍候…"
        }
    }

    private func subscribeHotkey() {
        guard let mgr = AppDelegate.shared?.hotkeyManager else { return }
        hotkeyActive = mgr.isActive
        mgr.onActiveChange = { active in
            DispatchQueue.main.async { hotkeyActive = active }
        }
    }
}

// MARK: - TabBarButton

private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FeatureTile

private struct FeatureTile: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let record: SpeechController.TranscriptionRecord
    @ObservedObject private var settings = SettingsManager.shared
    @State private var copied    = false
    @State private var isPlaying = false
    @State private var player:   AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.text)
                        .font(.subheadline)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Text(record.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("复制文字")
            }

            if settings.debugEnabled, record.rawText != record.text {
                HStack(spacing: 4) {
                    Image(systemName: "waveform").font(.caption2)
                    Text("ASR 原文：\(record.rawText)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            if settings.debugEnabled, let url = record.audioURL {
                Button {
                    if isPlaying {
                        player?.stop()
                        isPlaying = false
                    } else {
                        player = try? AVAudioPlayer(contentsOf: url)
                        player?.play()
                        isPlaying = true
                        // Reset flag when playback finishes
                        let duration = player?.duration ?? 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                            isPlaying = false
                        }
                    }
                } label: {
                    Label(isPlaying ? "停止" : "播放录音",
                          systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .font(.caption)
                        .foregroundStyle(isPlaying ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    MainView()
}
