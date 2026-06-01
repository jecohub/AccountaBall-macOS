import Foundation
import Combine

class AppState: ObservableObject {
    @Published var currentTask: String = ""
    @Published var ballState: BallState = .idle
    @Published var isCapturing: Bool = false
    @Published var sessionLog: [TaskSession] = []

    private var taskStartedAt: Date?

    func submitTask(_ task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentTask = trimmed
        ballState = .onTask
        isCapturing = true
        taskStartedAt = Date()
    }

    func clearTask() {
        currentTask = ""
        ballState = .idle
        isCapturing = false
        taskStartedAt = nil
    }

    func completeTask() {
        guard let startedAt = taskStartedAt else { return }
        let session = TaskSession(
            task: currentTask,
            startedAt: startedAt,
            completedAt: Date()
        )
        sessionLog.append(session)
        clearTask()
    }
}
