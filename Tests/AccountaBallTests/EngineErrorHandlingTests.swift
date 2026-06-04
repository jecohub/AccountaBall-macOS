import Foundation
@testable import AccountaBall

// AlwaysOnTaskAI lives in TestFakes.swift (shared across suites).

@MainActor
func runEngineErrorHandlingTests() async {
    await suite("EngineErrorHandling_errorIsNotOffTask") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false, "container"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "write", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext
        engine.beginSession(tasks: s.tasks)
        // Two failed cycles (nil) must NOT escalate to the off-task prompt.
        engine.processCycle(nil)
        engine.processCycle(nil)
        expect(s.appPhase == .session, "AI errors keep us in session, not offTask")
        expect(s.ballState != .offTask, "AI errors never set offTask ball state")
    }
}
