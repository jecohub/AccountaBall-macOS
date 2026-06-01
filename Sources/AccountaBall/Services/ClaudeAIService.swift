import Foundation

class ClaudeAIService: AIService {
    private let apiKey: String
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let systemPrompt = """
    You are an accountability assistant. The user declared a task.
    Look at what's on their screen and respond with exactly one word:
    ONTASK, OFFTASK, or DONE.

    Rules:
    - ONTASK: screen content is clearly related to the declared task
    - OFFTASK: screen shows something unrelated (social media, YouTube, unrelated apps)
    - DONE: the task appears completed (document finished, code committed, etc.)
    - When uncertain, respond ONTASK (benefit of the doubt)
    - Respond with ONLY the single word. No punctuation. No explanation.
    """

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func classify(task: String, screenText: String) async throws -> BallState {
        let userMessage = "Task: \(task)\n\nScreen text:\n\(screenText)"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String
        else { return .onTask }

        return Self.parseResponse(text)
    }

    static func parseResponse(_ raw: String) -> BallState {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch cleaned {
        case "ONTASK":  return .onTask
        case "OFFTASK": return .offTask
        case "DONE":    return .done
        default:        return .onTask
        }
    }
}
