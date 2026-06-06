import Foundation

/// Local LLM provider talking to a running Ollama daemon (default localhost:11434).
/// Uses the `/api/chat` endpoint with `stream: false` and a `format` JSON schema
/// for structured outputs.
final class OllamaAIService: AIService {
    let host: String
    let model: String
    private let session: URLSession

    init(host: String = "http://localhost:11434", model: String = "qwen2.5:7b") {
        self.host = host
        self.model = model
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Body builder (pure, unit-tested)

    /// Builds the JSON body for POST /api/chat.
    static func chatBody(model: String, system: String, user: String, jsonSchema: [String: Any]) -> [String: Any] {
        return [
            "model": model,
            "stream": false,
            "format": jsonSchema,
            "keep_alive": "10m",
            // Deterministic decoding. Ollama's default temperature (0.8) made the
            // same screen score on-task one cycle and off-task the next, which
            // reset the suspicion counter and let real off-task work slip by — and
            // made excuse verdicts a coin flip. Temperature 0 gives stable,
            // repeatable judgments.
            "options": ["temperature": 0.0],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
    }

    // MARK: - AIService

    func classify(task: String, screenText: String) async throws -> BallState {
        // v1 single-task classify is unused in v3 — the multi-task path is the default.
        // Kept on the protocol, but not wired in the engine.
        return .onTask
    }

    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult {
        let prompt = OpenRouterAIService.buildClassifyPrompt(
            tasks: tasks,
            screenText: screenText,
            allowanceRulesByIndex: allowanceRulesByIndex
        )
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "result": ["type": "string"],
                "label":  ["type": "string"]
            ],
            "required": ["result", "label"]
        ]
        let raw: String = try await send(system: AIPrompts.classifySystem, user: prompt, schema: schema)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? String else {
            return .offTask(label: "")
        }
        let label = obj["label"] as? String ?? ""
        let line = label.isEmpty ? result : "\(result) | \(label)"
        return MultiTaskResult.parse(line)
    }

    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict {
        let taskList = tasks.map { "- \($0.task): \($0.context)" }.joined(separator: "\n")
        // Deliberately exclude screenText: the noisy full-desktop OCR over-weighted
        // the verdict (rejecting legit explanations because unrelated tabs were also
        // on screen). Judge the user's explanation against the declared tasks.
        let user = "Tasks:\n\(taskList)\n\nUser explanation:\n\(excuse)"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "verdict":   ["type": "string"],
                "taskIndex": ["type": "integer"],
                "rule":      ["type": "string"]
            ],
            "required": ["verdict"]
        ]
        let raw: String = try await send(system: AIPrompts.excuseSystem, user: user, schema: schema)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let verdict = obj["verdict"] as? String else {
            return ExcuseVerdict(justified: false, taskIndex: nil, rule: "")
        }
        let justifiedRaw = verdict.uppercased()
        let justified = !justifiedRaw.contains("NOT") && justifiedRaw.contains("JUSTIFIED")
        let taskIndex = obj["taskIndex"] as? Int
        let rule = obj["rule"] as? String ?? ""
        // Keep the model's reason on both verdicts — on a rejection it's the "why"
        // we surface and record. Only task attribution is dropped when rejected.
        return ExcuseVerdict(justified: justified, taskIndex: justified ? taskIndex : nil, rule: rule)
    }

    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval,
                       previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "summary":    ["type": "string"],
                "steps":      ["type": "array", "items": ["type": "string"]],
                "comparison": ["type": "string"]
            ],
            "required": ["summary", "steps"]
        ]
        let stepsList = steps.isEmpty ? "(none recorded)" : steps.map { "- \($0)" }.joined(separator: "\n")
        let durationMin = Int((durationSeconds / 60).rounded())
        var user = "Title: \(title)\nContext: \(context)\nDuration: \(durationMin) min\nSteps:\n\(stepsList)"
        if let prev = previous {
            let prevMin = Int((prev.durationSeconds / 60).rounded())
            user += "\n\nPrevious session: \(prevMin) min, \(prev.steps.count) steps, \(prev.offTaskCount) off-task."
        }
        let raw: String = try await send(system: AIPrompts.summarizeSystem, user: user, schema: schema)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil)
        }
        let summary = obj["summary"] as? String ?? ""
        let stepArr = (obj["steps"] as? [String]) ?? []
        let comparison = obj["comparison"] as? String
        return TaskRecap(summary: summary, steps: stepArr, duration: durationSeconds, comparison: comparison)
    }

    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? {
        if candidates.isEmpty { return nil }
        let candList = candidates.enumerated().map { i, c in
            "[\(i)] id=\(c.id) title=\(c.title) summary=\(c.summary)"
        }.joined(separator: "\n")
        let user = "Current focus: \(query)\n\nCandidates:\n\(candList)"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "index":     ["type": "integer"],
                "confident": ["type": "boolean"]
            ],
            "required": ["index", "confident"]
        ]
        let raw: String = try await send(system: AIPrompts.matchSystem, user: user, schema: schema)
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // `index` is the 0-based position in the candidates list we sent, not the id itself.
        // -1 / null means no match.
        if let idx = obj["index"] as? Int, idx >= 0, idx < candidates.count {
            let confident = (obj["confident"] as? Bool) ?? false
            return (id: candidates[idx].id, confident: confident)
        }
        return nil
    }

    // MARK: - AIService health check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(host)/api/tags") else { return false }
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let names = (obj?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let base = model.split(separator: ":").first.map(String.init) ?? model
            return names.contains(model) || names.contains { $0.hasPrefix(base + ":") || $0 == base }
        } catch {
            return false
        }
    }

    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] {
        let prompt = AIPrompts.buildSessionPrompt(perTask: perTask)
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "tasks": ["type": "array", "items": ["type": "object",
                    "properties": ["title": ["type": "string"], "comment": ["type": "string"], "suggestion": ["type": "string"]],
                    "required": ["title", "comment"]]]
            ],
            "required": ["tasks"]
        ]
        let raw: String = try await send(system: AIPrompts.sessionSystem, user: prompt, schema: schema)
        return AIPrompts.parseSessionComments(raw, titles: perTask.map { $0.title })
    }

    // MARK: - private

    private func send(system: String, user: String, schema: [String: Any]) async throws -> String {
        guard let endpoint = URL(string: "\(host)/api/chat") else {
            throw URLError(.badURL)
        }
        let body = Self.chatBody(model: model, system: system, user: user, jsonSchema: schema)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return "" }
        return content
    }
}
