protocol AIService {
    func classify(task: String, screenText: String) async throws -> BallState
    func classifyMulti(tasks: [TaskItem], screenText: String) async throws -> MultiTaskResult
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> Bool
}
