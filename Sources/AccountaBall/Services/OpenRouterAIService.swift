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

    private func sendMessage(system: String, user: String, maxTokens: Int,
                             responseFormatJSON: Bool = false) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            // Deterministic decoding for stable, repeatable classification and
            // excuse verdicts (mirrors the Ollama path — see OllamaAIService).
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ]
        ]
        if responseFormatJSON {
            body["response_format"] = ["type": "json_object"]
        }
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
        let system = """
        You are an accountability assistant monitoring a user's screen.
        The user has declared tasks numbered starting at 0.
        Respond with one line: RESULT | <3-5 word activity label>. Example: TASK:0 | editing AppDelegate.swift
        - TASK:N (where N is the 0-based index of the task they appear to be working on)
        - OFFTASK (not working on any declared task)
        - DONE:N (task N appears completed)
        When uncertain, respond OFFTASK. No explanation.
        """
        let raw = try await sendMessage(
            system: system,
            user: Self.buildClassifyPrompt(tasks: tasks, screenText: screenText, allowanceRulesByIndex: allowanceRulesByIndex),
            maxTokens: 40
        )
        return MultiTaskResult.parse(raw)
    }

    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict {
        let system = """
        You are an accountability judge. The user declared one or more tasks and was flagged as
        possibly off-task. They explained what they are doing. If the explanation is plausibly
        part of, supports, or is a reasonable step toward ANY declared task (for example reading
        docs, researching, or testing for that task), answer JUSTIFIED. Only answer NOT_JUSTIFIED
        if it is clearly unrelated (e.g. social media, games, entertainment, personal shopping).
        Respond with EXACTLY one line: VERDICT | taskIndex | short reusable rule
        - JUSTIFIED | <0-based task index> | <short reusable rule describing this allowance, e.g. "watching React tutorials">
        - NOT_JUSTIFIED | |
        No extra explanation.
        """
        let taskList = tasks.enumerated().map { i, t in "[\(i)] \(t.task) — \(t.context)" }.joined(separator: "\n")
        let user = "Tasks:\n\(taskList)\n\nScreen text:\n\(screenText)\n\nUser explanation:\n\(excuse)"
        let raw = try await sendMessage(system: system, user: user, maxTokens: 60)
        return ExcuseVerdict.parse(raw)
    }

    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval,
                       previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap {
        let system = """
        You are an accountability assistant. Given a task's title, context, and the steps the user
        took, produce a compact JSON object with this exact shape:
        {"summary": "<1-2 sentence recap>", "steps": ["<bullet 1>", ...], "comparison": "<one sentence explaining why this run took longer/shorter than the previous run, in the user's voice; empty string if no prior run>"}
        Output JSON only, no prose.
        """
        let prevJSON: String = {
            guard let p = previous else { return "null" }
            return #"{"durationSeconds": \#(Int(p.durationSeconds)), "steps": \#(Self.jsonArray(p.steps)), "offTaskCount": \#(p.offTaskCount)}"#
        }()
        let user = #"""
        Title: \#(title)
        Context: \#(context)
        Steps this run: \#(Self.jsonArray(steps))
        Duration seconds: \#(Int(durationSeconds))
        Previous run: \#(prevJSON)
        """#
        let raw = try await sendMessage(system: system, user: user, maxTokens: 400, responseFormatJSON: true)
        if let parsed = Self.parseSummaryJSON(raw) {
            return Self.buildRecap(parsed: parsed, durationSeconds: durationSeconds, previous: previous)
        }
        return TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil)
    }

    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? {
        guard !candidates.isEmpty else { return nil }
        let system = """
        You are a task matcher. Given a user query and a numbered list of candidate tasks
        (each with id, title, summary), determine which candidate best matches the query.
        Respond with EXACTLY one line: MATCH:<id>|<HIGH|LOW>  or  NONE
        - HIGH means you are confident this is the same task
        - LOW means it's a plausible match but not certain
        - NONE means no candidate matches
        """
        let list = candidates.enumerated().map { i, c in
            "[\(i)] id=\(c.id) title=\(c.title) summary=\(c.summary)"
        }.joined(separator: "\n")
        let user = "Query: \(query)\n\nCandidates:\n\(list)"
        let raw = try await sendMessage(system: system, user: user, maxTokens: 30)
        return Self.parseMatch(raw)
    }

    // MARK: - Static helpers

    func healthCheck() async -> Bool { !apiKey.isEmpty }

    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] {
        let prompt = AIPrompts.buildSessionPrompt(perTask: perTask)
        let raw = try await sendMessage(
            system: AIPrompts.sessionSystem,
            user: prompt,
            maxTokens: 600,
            responseFormatJSON: true
        )
        return AIPrompts.parseSessionComments(raw, titles: perTask.map { $0.title })
    }

    static func parseMatch(_ raw: String) -> (id: String, confident: Bool)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("MATCH:") else { return nil }
        let parts = trimmed.dropFirst("MATCH:".count).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let idPart = parts.first else { return nil }
        let id = String(idPart).trimmingCharacters(in: .whitespacesAndNewlines)
        let confidentPart = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() : ""
        let confident = confidentPart == "HIGH"
        return id.isEmpty ? nil : (id, confident)
    }

    private static func parseSummaryJSON(_ raw: String) -> (summary: String, steps: [String], why: String)? {
        // Find the first {...} block in the response (model may add stray prose).
        guard let open = raw.firstIndex(of: "{"),
              let close = raw.lastIndex(of: "}") else { return nil }
        let jsonSlice = String(raw[open...close])
        guard let data = jsonSlice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let summary = (obj["summary"] as? String) ?? ""
        let steps = (obj["steps"] as? [String]) ?? []
        let why = (obj["comparison"] as? String) ?? ""
        return (summary, steps, why)
    }

    private static func buildRecap(parsed: (summary: String, steps: [String], why: String),
                                    durationSeconds: TimeInterval,
                                    previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) -> TaskRecap {
        guard let prev = previous else {
            return TaskRecap(summary: parsed.summary, steps: parsed.steps, duration: durationSeconds, comparison: nil)
        }
        let delta = DurationDelta.compare(current: durationSeconds, previous: prev.durationSeconds)
        let prefix: String
        if delta.fasterThanPrevious {
            prefix = "\(delta.deltaMinutes) min faster than last time"
        } else {
            prefix = "\(delta.deltaMinutes) min slower than last time"
        }
        let why = parsed.why.trimmingCharacters(in: .whitespacesAndNewlines)
        let comparison: String
        if why.isEmpty {
            comparison = prefix + "."
        } else {
            comparison = "\(prefix). \(why)"
        }
        return TaskRecap(summary: parsed.summary, steps: parsed.steps, duration: durationSeconds, comparison: comparison)
    }

    private static func jsonArray(_ items: [String]) -> String {
        let encoded = items.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        return "[\(encoded)]"
    }
}
