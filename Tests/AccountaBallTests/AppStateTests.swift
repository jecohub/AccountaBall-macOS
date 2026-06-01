@testable import AccountaBall

func runAppStateTests() {
    suite("AppStateTests") {
        let state = AppState()
        expect(state.currentTask == "", "initial task is empty")
        expect(state.ballState == .idle, "initial state is idle")
        expect(state.isCapturing == false, "not capturing initially")
        expect(state.sessionLog.isEmpty, "session log empty initially")

        state.submitTask("write the proposal")
        expect(state.currentTask == "write the proposal", "submitTask sets task")
        expect(state.ballState == .onTask, "submitTask sets onTask")
        expect(state.isCapturing == true, "submitTask starts capturing")

        let s2 = AppState()
        s2.submitTask("   ")
        expect(s2.ballState == .idle, "whitespace-only task is ignored")
        expect(s2.isCapturing == false, "whitespace-only task does not start capture")

        let s3 = AppState()
        s3.submitTask("write the proposal")
        s3.clearTask()
        expect(s3.currentTask == "", "clearTask resets task")
        expect(s3.ballState == .idle, "clearTask resets to idle")
        expect(s3.isCapturing == false, "clearTask stops capturing")

        let s4 = AppState()
        s4.submitTask("write the proposal")
        s4.completeTask()
        expect(s4.sessionLog.count == 1, "completeTask appends to log")
        expect(s4.sessionLog.first?.task == "write the proposal", "log entry has correct task")
        expect(s4.ballState == .idle, "completeTask resets to idle")
        expect(s4.isCapturing == false, "completeTask stops capturing")
    }
}
