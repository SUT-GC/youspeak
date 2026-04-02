import Foundation

/// Wraps DashScope Paraformer realtime ASR via the WebSocket JSON protocol.
final class DashScopeASR {
    private let apiKey: String
    static let timeoutSeconds: Double = 30

    init(apiKey: String) { self.apiKey = apiKey }

    func transcribe(_ pcmData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Session(apiKey: apiKey, pcmData: pcmData) { cont.resume(with: $0) }.start()
        }
    }
}

// MARK: - Session (one-shot, self-retaining until complete)

private final class Session {
    private let apiKey:   String
    private let pcmData:  Data
    private let onFinish: (Result<String, Error>) -> Void

    private var ws:          URLSessionWebSocketTask?
    private var urlSession:  URLSession?
    private var results:     [Int: String] = [:]
    private var finished     = false

    // Self-retain: keeps this object alive through all async WebSocket callbacks.
    // Released inside complete() after onFinish is called.
    private var strongSelf:  Session?

    // Protects `allAudioSent`, which is written from a send-callback thread
    // and read from a receive-callback thread.
    private let lock          = NSLock()
    private var _allAudioSent = false
    private var allAudioSent: Bool {
        get { lock.withLock { _allAudioSent } }
        set { lock.withLock { _allAudioSent = newValue } }
    }

    private let taskID = UUID().uuidString
        .replacingOccurrences(of: "-", with: "").lowercased()

    init(apiKey: String, pcmData: Data, onFinish: @escaping (Result<String, Error>) -> Void) {
        self.apiKey   = apiKey
        self.pcmData  = pcmData
        self.onFinish = onFinish
    }

    func start() {
        // Retain ourselves so ARC doesn't deallocate us before the
        // WebSocket callbacks have a chance to run.
        strongSelf = self

        let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        ws = urlSession!.webSocketTask(with: req)
        ws!.resume()

        ws!.send(.string(buildRunTask())) { [weak self] err in
            guard let self else { return }
            if let err { self.complete(.failure(err)); return }
            self.receiveLoop()
        }

        // Hard timeout — prevents a hung network call from locking up the app.
        DispatchQueue.global().asyncAfter(deadline: .now() + DashScopeASR.timeoutSeconds) { [weak self] in
            self?.complete(.failure(ASRError.timeout))
        }
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                if !self.finished { self.complete(.failure(err)) }
            case .success(let msg):
                self.handle(msg)
                if !self.finished { self.receiveLoop() }
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = msg,
              let data   = text.data(using: .utf8),
              let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event  = header["event"] as? String
        else { return }

        switch event {
        case "task-started":
            sendAllAudio()

        case "result-generated":
            // Ignore all mid-stream partials; only collect after every chunk is sent.
            guard allAudioSent else { return }
            guard let payload  = json["payload"]  as? [String: Any],
                  let output   = payload["output"] as? [String: Any],
                  let sentence = output["sentence"] as? [String: Any],
                  let txt      = sentence["text"]   as? String,
                  (sentence["end_time"] as? Int ?? 0) > 0
            else { return }
            let sid = sentence["sentence_id"] as? Int ?? results.count
            results[sid] = txt

        case "task-finished":
            let combined = results.sorted { $0.key < $1.key }.map(\.value).joined()
            complete(.success(combined))

        case "task-failed":
            let msg = (json["payload"] as? [String: Any])?["message"] as? String ?? "ASR task failed"
            complete(.failure(ASRError.taskFailed(msg)))

        default: break
        }
    }

    // MARK: - Send audio

    private func sendAllAudio() {
        let chunkSize = 6400   // 200 ms @ 16 kHz Int16 mono
        let data      = pcmData
        var offset    = 0

        func sendNext() {
            guard !finished, offset < data.count else {
                allAudioSent = true
                ws?.send(.string(buildFinishTask())) { _ in }
                return
            }
            let end   = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            offset    = end
            ws?.send(.data(chunk)) { _ in sendNext() }
        }
        sendNext()
    }

    // MARK: - Completion

    private func complete(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        ws?.cancel();    ws = nil
        urlSession = nil  // release URLSession promptly
        let cb = onFinish
        strongSelf = nil  // release self-retain AFTER capturing cb
        cb(result)
    }

    // MARK: - Message builders

    private func buildRunTask() -> String {
        json([
            "header": [
                "action":    "run-task",
                "task_id":   taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task":       "asr",
                "function":   "recognition",
                "model":      "paraformer-realtime-v2",
                "parameters": ["format": "pcm", "sample_rate": 16000],
                "input":      [String: Any]()
            ]
        ])
    }

    private func buildFinishTask() -> String {
        json([
            "header": ["action": "finish-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["input": [String: Any]()]
        ])
    }

    private func json(_ obj: Any) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
    }
}

// MARK: - Errors

enum ASRError: Error {
    case taskFailed(String)
    case timeout
}
