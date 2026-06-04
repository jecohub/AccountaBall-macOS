import Foundation
import Combine

private let tasksKey = "accountaball.tasks.v2"

final class AppState: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var appPhase: AppPhase = .idle
    @Published var activeTaskIndex: Int? = nil
    @Published var sessionStartTime: Date? = nil
    @Published var isCapturing: Bool = false
    @Published var ballState: BallState = .idle
    @Published var sessionLog: [TaskSession] = []
    /// Optional diagnostic/setup hint shown to the user (e.g. missing env vars).
    /// The UI layer in Task 17 will surface this in a banner.
    @Published var setupHint: String? = nil
    /// Set when the AI provider is unreachable; shown on the pause card.
    @Published var aiUnavailableHint: String? = nil
    /// The end-of-session breakdown: timeline ranges + per-task commentary.
    @Published var sessionRecap: SessionRecap? = nil

    // v3 — UI bridges (Task 18)
    /// AI recap per finished task, keyed by task title. Written by the engine on
    /// completion; read by the recap UI (progress panel + completion summary).
    @Published var recaps: [String: TaskRecap] = [:]
    /// A revived allowance awaiting one-time user confirmation on reuse.
    @Published var pendingAllowanceConfirm: AllowanceConfirm? = nil

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
        guard index >= 0 && index < tasks.count else { return }
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

/// A one-time prompt asking the user to confirm a revived allowance from a
/// previously-completed task that was brought back into this session.
struct AllowanceConfirm: Identifiable, Equatable {
    let id = UUID()
    let taskTitle: String
    let rule: String
}
