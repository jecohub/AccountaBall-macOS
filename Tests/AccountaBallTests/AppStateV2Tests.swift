import Foundation
@testable import AccountaBall

func runAppStateV2Tests() {
    suite("AppStateV2Tests") {
        // Initial state
        let s = AppState()
        expect(s.tasks.isEmpty, "starts with no tasks")
        expect(s.appPhase == .idle, "starts in idle phase")
        expect(s.activeTaskIndex == nil, "no active task initially")
        expect(s.sessionStartTime == nil, "no session start initially")
        expect(s.isCapturing == false, "not capturing initially")
        expect(s.ballState == .idle, "ballState starts as idle")
        expect(s.appPhase == .idle, "appPhase starts as idle")

        // activeTasks excludes completed
        let s2 = AppState()
        s2.tasks = [
            TaskItem(task: "a", context: "ctx"),
            TaskItem(task: "b", context: "ctx")
        ]
        expect(s2.activeTasks.count == 2, "activeTasks includes all when none complete")
        s2.tasks[0].isComplete = true
        expect(s2.activeTasks.count == 1, "activeTasks excludes completed")

        // allTasksComplete
        let s3 = AppState()
        s3.tasks = [TaskItem(task: "a", context: "b")]
        expect(!s3.allTasksComplete, "not complete when task incomplete")
        s3.tasks[0].isComplete = true
        expect(s3.allTasksComplete, "complete when all tasks done")
        let s3empty = AppState()
        expect(!s3empty.allTasksComplete, "not complete with no tasks")

        // startSession
        let s4 = AppState()
        s4.tasks = [TaskItem(task: "a", context: "b")]
        s4.startSession()
        expect(s4.appPhase == .session, "startSession sets phase to session")
        expect(s4.sessionStartTime != nil, "startSession sets sessionStartTime")
        expect(s4.isCapturing == true, "startSession starts capturing")
        expect(s4.ballState == .onTask, "startSession sets ballState to onTask")

        // completeTaskAt — tasks remain
        let s5 = AppState()
        s5.tasks = [TaskItem(task: "a", context: "b"), TaskItem(task: "c", context: "d")]
        s5.startSession()
        s5.completeTaskAt(index: 0)
        expect(s5.tasks[0].isComplete == true, "completeTaskAt marks task done")
        expect(s5.appPhase == .session, "session continues when tasks remain")

        // completeTaskAt — all done triggers complete
        let s6 = AppState()
        s6.tasks = [TaskItem(task: "a", context: "b")]
        s6.startSession()
        s6.completeTaskAt(index: 0)
        expect(s6.appPhase == .complete, "completeTaskAt triggers complete when all done")
        expect(s6.isCapturing == false, "capturing stops when complete")

        // out-of-bounds index is safe
        let s7 = AppState()
        s7.tasks = [TaskItem(task: "a", context: "b")]
        s7.completeTaskAt(index: 99)  // should not crash
        expect(s7.tasks[0].isComplete == false, "out-of-bounds index is a no-op")

        // Persistence
        let key = "accountaball.tasks.v2"
        UserDefaults.standard.removeObject(forKey: key)
        let s8 = AppState()
        s8.tasks = [TaskItem(task: "persist me", context: "ctx")]
        s8.saveTasks()
        let s9 = AppState()
        s9.loadTasks()
        expect(s9.tasks.first?.task == "persist me", "tasks survive save/load")
        expect(s9.tasks.first?.isComplete == false, "loadTasks resets isComplete")
        expect(s9.tasks.first?.timeOnTask == 0, "loadTasks resets timeOnTask")
        UserDefaults.standard.removeObject(forKey: key)  // cleanup

        // clearSavedTasks
        let s10 = AppState()
        s10.tasks = [TaskItem(task: "x", context: "y")]
        s10.saveTasks()
        s10.clearSavedTasks()
        expect(s10.tasks.isEmpty, "clearSavedTasks empties tasks")
        let s11 = AppState()
        s11.loadTasks()
        expect(s11.tasks.isEmpty, "cleared tasks do not survive load")
    }
}
