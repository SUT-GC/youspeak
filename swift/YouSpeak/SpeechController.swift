import Foundation

/// Orchestrates recording → ASR → LLM polish → text injection.
@MainActor
final class SpeechController: ObservableObject {
    @Published private(set) var state: State = .idle

    enum State { case idle, recording, processing }

    private let recorder  = AudioRecorder()
    private let injector  = TextInjector()
    private var inFlight  = false   // prevent concurrent transcriptions

    // MARK: - Hotkey actions

    func keyDown() {
        guard state == .idle else { return }
        state = .recording
        recorder.start()
    }

    func keyUp() {
        guard state == .recording else { return }
        state = .processing
        let pcm = recorder.stop()
        Task { await transcribe(pcm) }
    }

    // MARK: - Pipeline

    private func transcribe(_ pcm: Data) async {
        defer { state = .idle }
        guard !pcm.isEmpty else { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let s = SettingsManager.shared
        guard !s.asrAPIKey.isEmpty else {
            print("[YouSpeak] ASR API key not set — open Settings")
            return
        }

        let asr = DashScopeASR(apiKey: s.asrAPIKey)
        let raw: String
        do {
            raw = try await asr.transcribe(pcm)
        } catch {
            print("[YouSpeak] ASR error: \(error)")
            return
        }
        guard !raw.isEmpty else {
            print("[YouSpeak] (nothing recognised)")
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

        // Inject on the main thread (CGEvent must be posted from a thread with a run loop)
        await MainActor.run { injector.type(polished) }
    }
}
