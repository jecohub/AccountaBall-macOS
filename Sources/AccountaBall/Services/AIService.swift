import Foundation

protocol AIService {
    func classify(task: String, screenText: String) async throws -> BallState
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval,
                       previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)?

    /// Cheap reachability probe. Returns false on connection failure or, for
    /// local providers, when the configured model isn't available. Non-throwing
    /// by design — callers branch on the Bool, never treat a failure as off-task.
    func healthCheck() async -> Bool

    /// Prose commentary per task for the end-of-session breakdown. The caller
    /// computes local comparisons authoritatively; the model writes the human-
    /// readable comment + optional suggestion. Returns per-task comments in the
    /// same order.
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment]
}
