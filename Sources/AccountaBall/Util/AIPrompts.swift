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
    You judge whether a user's explanation for their current screen is a legitimate
    part of getting their declared task done.

    Decide from the USER'S EXPLANATION first; the screen is secondary context. Give
    the user the benefit of the doubt: if they state a plausible, specific connection
    to a declared task, accept it.

    JUSTIFIED when the activity supports a task, even indirectly: reading docs,
    researching or evaluating a tool/library/technique, watching a tutorial, testing,
    or looking something up — as long as the user ties it to a task. "Researching X to
    improve/build/fix <my task>" is JUSTIFIED.

    NOT_JUSTIFIED only when it is clearly unrelated or a vague pretext: social media,
    messaging, entertainment, shopping, news, or an explanation that names no real
    connection to a task (e.g. "just checking X", "got side-tracked").

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
