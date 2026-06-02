@testable import AccountaBall

private class MockAI: AIService {
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
}

@MainActor
func runAccountabilityEngineTests() {
    let capture = ScreenCaptureService()
    let ocr = OCRService()
    let notif = NotificationService()

    func make() -> (AppState, AccountabilityEngine) {
        let s = AppState()
        s.tasks = [TaskItem(task: "write the proposal", context: "work")]
        s.startSession()
        let e = AccountabilityEngine(
            state: s,
            captureService: capture,
            ocrService: ocr,
            aiService: MockAI(),
            notificationService: notif
        )
        return (s, e)
    }

    suite("AccountabilityEngineTests") {
        var (state, engine) = make()
        engine.processAIResult(.offTask)
        expect(state.ballState == .onTask, "single offTask does not flip state")

        (state, engine) = make()
        engine.processAIResult(.offTask)
        engine.processAIResult(.offTask)
        expect(state.ballState == .offTask, "two consecutive offTask flips to offTask")

        (state, engine) = make()
        engine.processAIResult(.offTask)
        engine.processAIResult(.onTask)
        engine.processAIResult(.offTask)
        expect(state.ballState == .onTask, "onTask in between resets suspicion")

        (state, engine) = make()
        engine.processAIResult(.done)
        expect(state.ballState == .idle, "done flips to idle via completeTaskAt")
        expect(state.appPhase == .complete, "done sets phase to complete")

        (state, engine) = make()
        engine.processAIResult(.offTask)
        engine.processAIResult(.offTask)
        engine.processAIResult(.onTask)
        expect(state.ballState == .onTask, "onTask while offTask returns to onTask")
    }
}
