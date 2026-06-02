import Foundation
import Combine

private let tasksKey = "accountaball.tasks.v2"

class AppState: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var appPhase: AppPhase = .idle
    @Published var activeTaskIndex: Int? = nil
    @Published var sessionStartTime: Date? = nil
    @Published var isCapturing: Bool = false
    @Published var ballState: BallState = .idle
    @Published var sessionLog: [TaskSession] = []

    var activeTasks: [TaskItem] { tasks.filter { !$0.isComplete } }
    var allTasksComplete: Bool { !tasks.isEmpty && tasks.allSatisfy { $0.isComplete } }

    func startSession() {
        sessionStartTime = Date()
        isCapturing = true
        appPhase = .session
        ballState = .onTask
    }

    func endSession() {
        isCapturing = false
        sessionStartTime = nil
        activeTaskIndex = nil
        ballState = .idle
    }

    func completeTaskAt(index: Int) {
        guard index < tasks.count else { return }
        tasks[index].isComplete = true
        if allTasksComplete {
            endSession()
            appPhase = .complete
        }
    }

    func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
    }

    func loadTasks() {
        guard let data = UserDefaults.standard.data(forKey: tasksKey),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data)
        else { return }
        tasks = decoded.map {
            var t = $0; t.isComplete = false; t.timeOnTask = 0; return t
        }
    }

    func clearSavedTasks() {
        UserDefaults.standard.removeObject(forKey: tasksKey)
        tasks = []
    }

    // Legacy compat — used by AccountabilityEngine (replaced in Task 6)
    var currentTask: String { activeTasks.first?.task ?? "" }
}
