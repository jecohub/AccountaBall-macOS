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

    static func buildClassifyPrompt(tasks: [TaskItem], screenText: String,
                                    allowanceRulesByIndex: [Int: [String]] = [:]) -> String {
        let taskList = tasks.enumerated().map { i, t in
            "[\(i)] \(t.task) — \(t.context)"
        }.joined(separator: "\n")
        var prompt = "Tasks:\n\(taskList)\n\nScreen text:\n\(screenText)"
        if !allowanceRulesByIndex.isEmpty {
            let lines = allowanceRulesByIndex.keys.sorted().flatMap { idx -> [String] in
                (allowanceRulesByIndex[idx] ?? []).map { rule in "Task \(idx): \(rule)" }
            }
            prompt += "\n\nAllowances — treat these as ON-TASK for the named task:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
        }
        return prompt
    }

    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult {
        let system = AIPrompts.classifySystem
        let raw = try await sendMessage(
            system: system,
            user: Self.buildClassifyPrompt(tasks: tasks, screenText: screenText, allowanceRulesByIndex: allowanceRulesByIndex),
            maxTokens: 40
        )
        return MultiTaskResult.parse(raw)
    }

    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict {
        let system = AIPrompts.excuseSystem
        let taskList = tasks.map { "- \($0.task): \($0.context)" }.joined(separator: "\n")
        let user = "Tasks:\n\(taskList)\n\nScreen text:\n\(screenText)\n\nUser explanation:\n\(excuse)"
        let raw = try await sendMessage(system: system, user: user, maxTokens: 60)
        return ExcuseVerdict.parse(raw)
    }

    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval,
                       previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap {
        return TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil)
    }

    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? {
        return nil
    }
}
