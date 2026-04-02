import Foundation

/// Orchestrates recording → ASR → LLM polish → text injection.
@MainActor
final class SpeechController: ObservableObject {
    static let shared = SpeechController()

    @Published private(set) var state: State = .idle

    enum State { case idle, recording, processing }

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

        let raw: String
        do {
            raw = try await DashScopeASR(apiKey: s.asrAPIKey).transcribe(pcm)
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

        // type() is @MainActor async — yields between chars instead of blocking.
        await injector.type(polished)
    }
}
