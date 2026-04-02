import Foundation

final class LLMService {
    static let shared = LLMService()
    private init() {}

    private let systemPrompt = """
        你是语音识别文本的后处理助手。\
        用户给你一段 ASR 原始输出，可能有错别字、重复词语或语义不通顺。\
        请直接输出修正后的文本，不要解释，不要加任何前缀或后缀，保持原意，尽量少改动。
        """

    private static let endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    private static let model    = "qwen-turbo"

    func polish(_ raw: String) async throws -> String {
        let s = SettingsManager.shared
        guard !s.qwenAPIKey.isEmpty else { return raw }

        let url = URL(string: Self.endpoint)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(s.qwenAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": raw]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            print("[LLM] HTTP error: \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
            return raw
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return raw }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
