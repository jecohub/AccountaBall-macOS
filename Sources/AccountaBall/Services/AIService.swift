import Foundation

protocol AIService {
    func classify(task: String, screenText: String) async throws -> BallState
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval,
                       previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)?
}
