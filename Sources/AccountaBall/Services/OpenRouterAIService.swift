import Foundation

class OpenRouterAIService: AIService {
    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    init(apiKey: String, model: String = "anthropic/claude-haiku-4-5") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Shared HTTP helper

    private func sendMessage(system: String, user: String, maxTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20  // never hang the UI on a stuck request
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else { return "" }
        return text
    }

    // MARK: - AIService

    func classify(task: String, screenText: String) async throws -> BallState {
        let system = "You are an accountability assistant. Respond with exactly one word: ONTASK, OFFTASK, or DONE. No explanation."
        let raw = try await sendMessage(system: system, user: "Task: \(task)\n\nScreen text:\n\(screenText)", maxTokens: 10)
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch cleaned {
        case "ONTASK": return .onTask
        case "OFFTASK": return .offTask
        case "DONE":   return .done
        default:       return .onTask
        }
    }

    // MARK: - Multi-task

    static func buildClassifyPrompt(tasks: [TaskItem], screenText: String) -> String {
        let taskList = tasks.enumerated().map { i, t in
            "[\(i)] \(t.task) — \(t.context)"
        }.joined(separator: "\n")
        return "Tasks:\n\(taskList)\n\nScreen text:\n\(screenText)"
    }

    func classifyMulti(tasks: [TaskItem], screenText: String) async throws -> MultiTaskResult {
        let system = """
        You are an accountability assistant monitoring a user's screen.
        The user has declared tasks numbered starting at 0.
        Respond with EXACTLY one token:
        - TASK:N (where N is the 0-based index of the task they appear to be working on)
        - OFFTASK (not working on any declared task)
        - DONE:N (task N appears completed)
        When uncertain, respond OFFTASK. No explanation.
        """
        let raw = try await sendMessage(system: system, user: Self.buildClassifyPrompt(tasks: tasks, screenText: screenText), maxTokens: 10)
        return MultiTaskResult.parse(raw)
    }

    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> Bool {
        let system = """
        You are an accountability judge. The user declared one or more tasks and was flagged as
        possibly off-task. They explained what they are doing. If the explanation is plausibly
        part of, supports, or is a reasonable step toward ANY declared task (for example reading
        docs, researching, or testing for that task), answer JUSTIFIED. Only answer NOT_JUSTIFIED
        if it is clearly unrelated (e.g. social media, games, entertainment, personal shopping).
        Respond with EXACTLY one word: JUSTIFIED or NOT_JUSTIFIED. No explanation.
        """
        let taskList = tasks.map { "- \($0.task): \($0.context)" }.joined(separator: "\n")
        let user = "Tasks:\n\(taskList)\n\nScreen text:\n\(screenText)\n\nUser explanation:\n\(excuse)"
        let raw = try await sendMessage(system: system, user: user, maxTokens: 10)
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // "NOT_JUSTIFIED" / "NOT JUSTIFIED" also contains "JUSTIFIED", so reject those first.
        if cleaned.contains("NOT") { return false }
        return cleaned.contains("JUSTIFIED")
    }
}
