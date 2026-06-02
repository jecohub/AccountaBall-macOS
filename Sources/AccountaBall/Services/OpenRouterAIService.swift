import Foundation

class OpenRouterAIService: AIService {
    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

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

    init(apiKey: String, model: String = "anthropic/claude-haiku-4-5") {
        self.apiKey = apiKey
        self.model = model
    }

    func classify(task: String, screenText: String) async throws -> BallState {
        let userMessage = "Task: \(task)\n\nScreen text:\n\(screenText)"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else { return .onTask }

        return ClaudeAIService.parseResponse(text)
    }
}
