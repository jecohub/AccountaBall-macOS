import Foundation
import SwiftData
@testable import AccountaBall

private class MultiMockAI: AIService {
    var nextResult: MultiTaskResult = .offTask(label: "")
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { nextResult }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: true, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
}

@MainActor
func runAccountabilityEngineTests() {
    let capture = ScreenCaptureService()
    let ocr = OCRService()
    let notif = NotificationService()

    func make() -> (AppState, AccountabilityEngine) {
        let s = AppState()
        s.tasks = [
            TaskItem(task: "write proposal", context: "for client"),
            TaskItem(task: "review slides",  context: "deck")
        ]
        s.startSession()
        let e = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        return (s, e)
    }

    suite("AccountabilityEngineTests") {
        var (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .onTask, "single offTask does not flip state")
        expect(state.appPhase == .session, "single offTask does not change phase")

        (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .offTask, "two consecutive offTask flips to offTask")
        expect(state.appPhase == .offTask, "two consecutive offTask sets offTask phase")

        (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        engine.processResult(.onTask(index: 0, label: ""))
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .onTask, "onTask in between resets suspicion")

        (state, engine) = make()
        engine.processResult(.onTask(index: 1, label: ""))
        expect(state.activeTaskIndex == 1, "onTask sets activeTaskIndex")
        expect(state.ballState == .onTask, "onTask sets ballState to onTask")

        (state, engine) = make()
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.tasks[0].timeOnTask == 5, "onTask accumulates 5s per cycle")
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.tasks[0].timeOnTask == 10, "second onTask accumulates another 5s")

        (state, engine) = make()
        engine.processResult(.onTask(index: 1, label: ""))
        expect(state.tasks[1].timeOnTask == 5, "onTask on task 1 accumulates time on task 1")
        expect(state.tasks[0].timeOnTask == 0, "task 0 not affected")

        (state, engine) = make()
        engine.processResult(.done(index: 0, label: ""))
        expect(state.tasks[0].isComplete == true, "done marks task complete")

        (state, engine) = make()
        engine.processResult(.done(index: 0, label: ""))
        engine.processResult(.done(index: 1, label: ""))
        expect(state.appPhase == .complete, "all done triggers complete phase")

        (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .offTask, "two offTask enters offTask phase")
        // Capture results must be ignored while the excuse prompt is up, so the
        // prompt isn't dismissed before the user answers.
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.appPhase == .offTask, "onTask is ignored while awaiting excuse")
        expect(state.activeTaskIndex == nil, "onTask does not set active task while offTask")

        (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .offTask, "confirmed offTask phase")
        engine.resumeAfterExcuse()
        expect(state.ballState == .onTask, "resumeAfterExcuse restores onTask ball")
        expect(state.appPhase == .session, "resumeAfterExcuse restores session phase")
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .session, "suspicion reset by resumeAfterExcuse")
    }
}

@MainActor
func runEngineSessionTests() {
    suite("EngineSessionTests") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "test", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx

        engine.beginSession(tasks: [TaskItem(task: "test", context: "")])
        expect(engine.currentSession != nil, "session is active after beginSession")
        expect(engine.currentSession?.taskTitles == ["test"], "task titles snapshotted")

        engine.record(taskIndex: 0, label: "x")
        engine.record(taskIndex: 0, label: "y")
        expect(engine.currentSession?.entries.count == 2, "two timeline entries recorded")
        expect(engine.currentSession?.entries.first?.label == "x", "first label stored")
        expect(engine.currentSession?.entries.last?.label == "y", "last label stored")
        expect(engine.currentSession?.entries.first?.taskIndex == 0, "task index stored on entry")

        engine.endSession()
        expect(engine.currentSession == nil, "currentSession is nil after endSession")
        expect(engine.currentSession == nil, "session ended cleanly")
    }

    suite("EngineSessionTests_labelCapture") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "test", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        engine.beginSession(tasks: s.tasks)

        engine.processResult(.onTask(index: 0, label: "writing"))
        expect(engine.lastActivityLabel == "writing", "onTask label captured")

        engine.processResult(.offTask(label: "twitter"))
        expect(engine.lastActivityLabel == "twitter", "offTask label captured")
        expect(engine.currentSession?.entries.contains(where: { $0.label == "twitter" }) == true, "offTask entry recorded with label")
    }

    suite("EngineSessionTests_noContextIsNoop") {
        // Engine built without a modelContext (test stub path) should not crash
        // when beginSession/record/endSession are called.
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "t", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        // modelContext intentionally nil
        engine.beginSession(tasks: s.tasks)
        expect(engine.currentSession == nil, "beginSession is a no-op without context")
        engine.record(taskIndex: 0, label: "x")
        expect(true, "record is a no-op without session")
        engine.endSession()
        expect(true, "endSession is a no-op without session")
    }
}
