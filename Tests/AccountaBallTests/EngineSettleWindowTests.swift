import Foundation
@testable import AccountaBall

// AlwaysOnTaskAI lives in TestFakes.swift (shared across suites).

@MainActor
func runEngineSettleWindowTests() async {
    await suite("EngineSettleWindow_suppressesEarlyPrompt") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext
        var fakeNow = Date()
        engine.now = { fakeNow }
        engine.beginSession(tasks: s.tasks)              // arms settle window: now+15
        // Two off-task reads inside the window must NOT prompt:
        engine.processResult(.offTask(label: "yt"))
        engine.processResult(.offTask(label: "yt"))
        expect(s.appPhase == .session, "no prompt inside settle window")
        // Advance past the window; two more off-task reads DO prompt:
        fakeNow = fakeNow.addingTimeInterval(16)
        engine.processResult(.offTask(label: "yt"))
        engine.processResult(.offTask(label: "yt"))
        expect(s.appPhase == .offTask, "prompts after settle window")
    }
}
