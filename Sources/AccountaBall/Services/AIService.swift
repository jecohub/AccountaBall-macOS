protocol AIService {
    func classify(task: String, screenText: String) async throws -> BallState
}
