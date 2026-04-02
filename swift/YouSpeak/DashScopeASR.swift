import Foundation

/// Wraps DashScope Paraformer realtime ASR via the WebSocket JSON protocol.
final class DashScopeASR {
    private let apiKey: String
    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?

    private var taskID: String = ""
    private var resultBuffer: [Int: String] = [:]
    private var completion: ((Result<String, Error>) -> Void)?
    private var allAudioSent = false

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public

    /// Transcribes raw PCM Int16 / 16 kHz / mono audio data.
    func transcribe(_ pcmData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.run(pcmData: pcmData) { result in
                cont.resume(with: result)
            }
        }
    }

    // MARK: - Internal

    private func run(pcmData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        resultBuffer    = [:]
        allAudioSent    = false
        taskID          = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                                           .lowercased()
                                           .prefix(32)
                                           .description

        let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("enable", forHTTPHeaderField: "X-DashScope-DataInspection")

        let cfg = URLSessionConfiguration.default
        session = URLSession(configuration: cfg)
        ws = session?.webSocketTask(with: req)
        ws?.resume()

        // Send run-task command
        let runTask = buildRunTask()
        ws?.send(.string(runTask)) { [weak self] err in
            guard let self, err == nil else {
                completion(.failure(err ?? ASRError.sendFailed))
                return
            }
            self.receiveLoop()
        }

        // Wait for task-started before sending audio
        // We'll send audio after receiving task-started in receiveLoop
        _ = pcmData  // stored via closure capture below
        self.pendingPCM = pcmData
    }

    private var pendingPCM: Data = Data()

    private func sendAudio() {
        let chunkSize = 3200 * 2  // 200 ms @ 16kHz Int16 = 6400 bytes
        var offset = 0
        let data = pendingPCM
        let group = DispatchGroup()

        func sendNext() {
            guard offset < data.count else {
                // send finish command
                allAudioSent = true
                let finish = buildFinishTask()
                ws?.send(.string(finish)) { _ in }
                return
            }
            let end   = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            offset = end

            group.enter()
            ws?.send(.data(chunk)) { _ in
                group.leave()
                group.notify(queue: .global()) { sendNext() }
            }
        }
        sendNext()
    }

    private func receiveLoop() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.finish(.failure(err))
            case .success(let msg):
                self.handle(message: msg)
                self.receiveLoop()
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let header = json["header"] as? [String: Any]
        let event  = header?["event"] as? String ?? ""

        switch event {
        case "task-started":
            sendAudio()

        case "result-generated":
            guard allAudioSent else { return }  // ignore intermediate results
            if let payload = json["payload"] as? [String: Any],
               let output  = payload["output"]  as? [String: Any],
               let sentence = output["sentence"] as? [String: Any],
               let text     = sentence["text"]   as? String,
               let endTime  = sentence["end_time"] as? Int,
               endTime > 0
            {
                let sid = sentence["sentence_id"] as? Int ?? resultBuffer.count
                resultBuffer[sid] = text
            }

        case "task-finished":
            let combined = resultBuffer
                .sorted { $0.key < $1.key }
                .map(\.value)
                .joined()
            finish(.success(combined))

        case "task-failed":
            let msg = (json["payload"] as? [String: Any])?["message"] as? String ?? "ASR failed"
            finish(.failure(ASRError.taskFailed(msg)))

        default:
            break
        }
    }

    private func finish(_ result: Result<String, Error>) {
        ws?.cancel()
        ws = nil
        let cb = completion
        completion = nil
        cb?(result)
    }

    // MARK: - Message builders

    private func buildRunTask() -> String {
        let obj: [String: Any] = [
            "header": [
                "action":     "run-task",
                "task_id":    taskID,
                "streaming":  "duplex"
            ],
            "payload": [
                "task": [
                    "task": "asr",
                    "function": "recognition",
                    "model": "paraformer-realtime-v2"
                ],
                "parameters": [
                    "format": "pcm",
                    "sample_rate": 16000
                ],
                "input": [String: Any]()
            ]
        ]
        return (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
    }

    private func buildFinishTask() -> String {
        let obj: [String: Any] = [
            "header": [
                "action":  "finish-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [String: Any]()
            ]
        ]
        return (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
    }

    enum ASRError: Error {
        case sendFailed
        case taskFailed(String)
    }
}
