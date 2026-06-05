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

    // The "Continue anyway" escape hatch grants a longer grace than the default
    // settle window: a user who keeps going after a rejected excuse must not be
    // re-nagged until the grace lapses.
    await suite("EngineGraceWindow_continueAnywaySuppressesLongerThanSettle") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext
        var fakeNow = Date()
        engine.now = { fakeNow }
        engine.resumeAfterExcuse(graceSeconds: AppConstants.continueAnywayGraceSeconds)  // settleUntil = now+120
        // Past the default 15s settle window but inside the 120s grace: no prompt.
        fakeNow = fakeNow.addingTimeInterval(engine.settleWindow + 1)
        engine.processResult(.offTask(label: "yt"))
        engine.processResult(.offTask(label: "yt"))
        expect(s.appPhase == .session, "grace window suppresses past the default settle window")
        // Past the grace window: off-task reads prompt again.
        fakeNow = fakeNow.addingTimeInterval(AppConstants.continueAnywayGraceSeconds)
        engine.processResult(.offTask(label: "yt"))
        engine.processResult(.offTask(label: "yt"))
        expect(s.appPhase == .offTask, "prompts after the grace window lapses")
    }
}
