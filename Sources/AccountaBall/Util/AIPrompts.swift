import Foundation

// MARK: - summarizeSession types (imported via SessionRecap.swift)

/// System prompt for summarizeSession — the model returns structured JSON.
extension AIPrompts {
    static let sessionSystem = """
    You are an accountability assistant. The user completed a focus session with one or more tasks.
    For each task, write a one-sentence comment describing performance: did they finish faster/slower
    than before? What was notable? Optionally suggest one short improvement tip if there is any.
    Respond with JSON: {"tasks": [{"title": "<exact task title>", "comment": "<one sentence>", "suggestion": "<tip or empty string>"}, ...]}
    Output JSON only, no prose.
    """

    /// Build the user-side prompt for the AI's summarizeSession call. The caller
    /// computes the local comparison authoritatively; the AI writes the prose.
    static func buildSessionPrompt(perTask: [PerTaskSessionInput]) -> String {
        perTask.enumerated().map { i, t in
            let lastStr = t.lastDurationSeconds.map { "\(Int(($0/60).rounded()))m" } ?? "N/A"
            let avgStr = t.averageSeconds.map { "\(Int(($0/60).rounded()))m" } ?? "N/A"
            return """
            Task \(i): "\(t.title)"
            - This run: \(Int((t.durationSeconds/60).rounded()))m, \(t.offTaskCount) off-task moments
            - Steps: \(t.steps.isEmpty ? "none" : t.steps.joined(separator: ", "))
            - Last run: \(lastStr), Average: \(avgStr)
            - Local comparison: \(t.localComparison)
            """
        }.joined(separator: "\n\n")
    }

    /// Parse the AI's JSON response into `[PerTaskComment]`. Returns empty array
    /// on any parse failure.
    static func parseSessionComments(_ json: String, titles: [String]) -> [PerTaskComment] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["tasks"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let t = d["title"] as? String else { return nil }
            let c = (d["comment"] as? String) ?? ""
            let sug = (d["suggestion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return PerTaskComment(taskTitle: t, comment: c, suggestion: sug)
        }
    }
}

/// Shared prompt strings used by AIService implementations.
/// Centralised so the local (Ollama) and remote (OpenRouter) providers
/// stay in lockstep on what we ask the model to do.
enum AIPrompts {
    /// System prompt for classifyMulti — request structured JSON
    /// matching the classifyMulti JSON schema.
    static let classifySystem = """
    You classify which of the user's declared tasks matches the current screen.
    Respond with JSON: {"result": "TASK:N" | "OFFTASK" | "DONE:N", "label": "<description>"}
    - TASK:N means the user is on the Nth task (0-based)
    - OFFTASK means none of the declared tasks match the screen
    - DONE:N means task N appears completed
    - label: a specific, concrete description of what's actually on screen,
      naming the app/site and the content — e.g. "Editing the Q3 sales proposal
      in Google Docs" or "Watching a cat video on YouTube". One short phrase,
      max ~12 words. Describe what you see, not a generic category.
    """

    /// System prompt for evaluateExcuse.
    static let excuseSystem = """
    You are an accountability judge. The user declared one or more tasks and was flagged
    as possibly off-task. They explained what they are doing. If the explanation is
    plausibly part of, supports, or is a reasonable step toward ANY declared task
    (for example reading docs, researching, or testing for that task), answer
    JUSTIFIED. Only answer NOT_JUSTIFIED if it is clearly unrelated (e.g. social
    media, games, entertainment, personal shopping).
    Respond with JSON: {"verdict": "JUSTIFIED" | "NOT_JUSTIFIED", "taskIndex": <int|null>, "rule": "<short reason>"}
    """

    /// System prompt for summarizeTask.
    static let summarizeSystem = """
    You write a short recap of a completed focus session.
    Respond with JSON: {"summary": "<one sentence>", "steps": ["<step>", ...], "comparison": "<optional one-sentence delta vs prior session>"}
    """

    /// System prompt for matchTask — picking the best matching prior task.
    static let matchSystem = """
    You pick the best matching prior task for the user's current focus.
    Respond with JSON: {"id": "<candidate id>" | null, "confident": true | false}
    """
}
