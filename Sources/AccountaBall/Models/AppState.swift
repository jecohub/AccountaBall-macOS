import Foundation
import Combine

private let tasksKey = "accountaball.tasks.v2"
private let driftLimitKey = "accountaball.driftLimit.v1"

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
    /// Frozen total duration captured at completion. `endSession()` clears
    /// `sessionStartTime`, so the completion screen reads this instead (otherwise
    /// it shows "--:--").
    @Published var lastSessionDuration: TimeInterval? = nil

    // v3 — UI bridges (Task 18)
    /// AI recap per finished task, keyed by task title. Written by the engine on
    /// completion; read by the recap UI (progress panel + completion summary).
    @Published var recaps: [String: TaskRecap] = [:]
    /// A revived allowance awaiting one-time user confirmation on reuse.
    @Published var pendingAllowanceConfirm: AllowanceConfirm? = nil

    /// Pre-committed drift budget for a session: the number of confirmed off-task
    /// drifts allowed before the commitment is broken. Set ONLY at setup — the
    /// in-the-moment user must not be able to raise it. Persisted in UserDefaults.
    @Published var driftLimit: Int = 3 {
        didSet {
            let clamped = min(max(driftLimit, 1), 10)
            if clamped != driftLimit { driftLimit = clamped; return }  // re-entrant set won't re-fire didSet for observers; guard avoids double-persist
            UserDefaults.standard.set(driftLimit, forKey: driftLimitKey)
        }
    }

    func loadDriftLimit() {
        let v = UserDefaults.standard.integer(forKey: driftLimitKey)
        driftLimit = (v == 0) ? 3 : min(max(v, 1), 10)   // 0 == unset → default 3
    }

    var activeTasks: [TaskItem] { tasks.filter { !$0.isComplete } }
    var allTasksComplete: Bool { !tasks.isEmpty && tasks.allSatisfy { $0.isComplete } }

    func startSession() {
        sessionStartTime = Date()
        lastSessionDuration = nil
        sessionRecap = nil
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
            // Freeze the total duration before endSession() nils sessionStartTime,
            // so the completion screen can show it.
            if let start = sessionStartTime {
                lastSessionDuration = Date().timeIntervalSince(start)
            }
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
