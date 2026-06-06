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

    // The "Give me 2 minutes" escape hatch grants an ACTIVITY-SCOPED grace: while
    // the user stays on the activity they asked to continue, off-task reads are
    // suppressed — but switching to a different activity ends the grace and
    // re-checks. The breather is for that one screen, not a blanket pass.
    await suite("EngineGraceWindow_activityScoped") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext
        var fakeNow = Date()
        engine.now = { fakeNow }
        // Flagged off-task watching youtube, user taps "Give me 2 minutes".
        engine.processResult(.offTask(label: "watching youtube"))   // sets lastActivityLabel
        engine.resumeAfterExcuse(graceForCurrentActivity: true)     // grace for that activity, +120s
        // Past the 15s settle, still on the SAME activity → suppressed.
        fakeNow = fakeNow.addingTimeInterval(engine.settleWindow + 1)
        engine.processResult(.offTask(label: "watching youtube"))
        engine.processResult(.offTask(label: "watching youtube"))
        expect(s.appPhase == .session, "same-activity off-task suppressed during the 2-min grace")
        // Switch to a DIFFERENT off-task activity → grace ends, normal re-check.
        engine.processResult(.offTask(label: "scrolling twitter"))
        engine.processResult(.offTask(label: "scrolling twitter"))
        expect(s.appPhase == .offTask, "switching to a different activity ends the grace and re-prompts")
    }

    // The activity grace is also time-bounded: once it lapses, even the same
    // activity gets re-checked.
    await suite("EngineGraceWindow_expiresAfterWindow") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext
        var fakeNow = Date()
        engine.now = { fakeNow }
        engine.processResult(.offTask(label: "watching youtube"))
        engine.resumeAfterExcuse(graceForCurrentActivity: true)     // graceUntil = now+120
        // Jump past the whole grace window; the same activity now prompts again.
        fakeNow = fakeNow.addingTimeInterval(AppConstants.continueAnywayGraceSeconds + 1)
        engine.processResult(.offTask(label: "watching youtube"))
        engine.processResult(.offTask(label: "watching youtube"))
        expect(s.appPhase == .offTask, "same activity prompts again after the grace window lapses")
    }
}
