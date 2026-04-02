import Foundation

/// Orchestrates recording → ASR → LLM polish → text injection.
@MainActor
final class SpeechController: ObservableObject {
    static let shared = SpeechController()

    @Published private(set) var state: State = .idle

    enum State { case idle, recording, processing }

    struct TranscriptionRecord: Identifiable {
        let id        = UUID()
        let text:     String   // polished (or raw if polish disabled)
        let rawText:  String   // ASR original
        let date      = Date()
        let audioURL: URL?
        init(text: String, rawText: String, audioURL: URL? = nil) {
            self.text     = text
            self.rawText  = rawText
            self.audioURL = audioURL
        }
    }

    @Published private(set) var history: [TranscriptionRecord] = []

    func clearHistory() {
        for record in history {
            if let url = record.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Also remove any leftover WAV files not tracked in history
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/YouSpeak")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) {
            files.filter { $0.pathExtension == "wav" }.forEach {
                try? FileManager.default.removeItem(at: $0)
            }
        }
        history = []
    }

    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private var inFlight = false

    // MARK: - Hotkey actions

    func keyDown() {
        guard state == .idle else { return }
        guard recorder.start() else { return }  // false = mic permission denied / engine error
        state = .recording
    }

    func keyUp() {
        guard state == .recording else { return }
        let pcm = recorder.stop()
        state = .processing
        Task { await transcribe(pcm) }
    }

    // MARK: - Pipeline

    private func transcribe(_ pcm: Data) async {
        defer { state = .idle }
        guard !pcm.isEmpty, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let s = SettingsManager.shared
        guard !s.asrAPIKey.isEmpty else {
            print("[YouSpeak] ASR API key not set — open Settings")
            return
        }

        let audioURL = SettingsManager.shared.debugEnabled ? saveDebugAudio(pcm) : nil

        let raw: String
        do {
            raw = try await DashScopeASR(apiKey: s.asrAPIKey).transcribe(pcm)
        } catch {
            print("[YouSpeak] ASR error: \(error)")
            if let url = audioURL { try? FileManager.default.removeItem(at: url) }
            return
        }
        guard !raw.isEmpty else {
            print("[YouSpeak] (nothing recognised)")
            if let url = audioURL { try? FileManager.default.removeItem(at: url) }
            return
        }
        print("[ASR] \(raw)")

        let polished: String
        if s.polishEnabled {
            polished = (try? await LLMService.shared.polish(raw)) ?? raw
        } else {
            polished = raw
        }
        print("[输入] \(polished)")

        history.insert(TranscriptionRecord(text: polished, rawText: raw, audioURL: audioURL), at: 0)
        if history.count > 50 { history.removeLast() }

        // type() is @MainActor async — yields between chars instead of blocking.
        await injector.type(polished)
    }

    // MARK: - Debug audio

    /// Saves PCM as a WAV file to ~/Documents/YouSpeak/ and returns the URL.
    @discardableResult
    private func saveDebugAudio(_ pcm: Data) -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/YouSpeak", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let file = dir.appendingPathComponent("\(fmt.string(from: Date())).wav")

        guard (try? makeWAV(pcm).write(to: file)) != nil else { return nil }
        print("[Debug] 音频 → \(file.path)")
        return file
    }

    private func makeWAV(_ pcm: Data, sampleRate: Int = 16_000) -> Data {
        let dataSize  = UInt32(pcm.count)
        var h = Data()
        func u16(_ v: UInt16) { h += withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func u32(_ v: UInt32) { h += withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        h += "RIFF".utf8; u32(36 + dataSize)
        h += "WAVE".utf8
        h += "fmt ".utf8; u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        h += "data".utf8; u32(dataSize)
        return h + pcm
    }
}
