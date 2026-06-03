import Foundation

/// Shared prompt strings used by AIService implementations.
/// Centralised so the local (Ollama) and remote (OpenRouter) providers
/// stay in lockstep on what we ask the model to do.
enum AIPrompts {
    /// System prompt for classifyMulti — request structured JSON
    /// matching the classifyMulti JSON schema.
    static let classifySystem = """
    You classify which of the user's declared tasks matches the current screen.
    Respond with JSON: {"result": "TASK:N" | "OFFTASK" | "DONE:N", "label": "<3-5 word activity>"}
    - TASK:N means the user is on the Nth task (0-based)
    - OFFTASK means none of the declared tasks match the screen
    - DONE:N means task N appears completed
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
