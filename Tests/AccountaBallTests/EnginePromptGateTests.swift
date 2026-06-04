import Foundation
import SwiftData
@testable import AccountaBall

// AlwaysOnTaskAI lives in TestFakes.swift (shared across suites).

@MainActor
func runEnginePromptGateTests() async {
    await suite("EnginePromptGate_noPromptOutsideSession") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: AlwaysOnTaskAI(), notificationService: NotificationService())
        engine.modelContext = c.mainContext; engine.beginSession(tasks: s.tasks)
        engine.now = { Date().addingTimeInterval(3600) }   // past settle window
        s.appPhase = .progress                              // user is on the session-log screen
        engine.processResult(.offTask(label: "yt"))
        engine.processResult(.offTask(label: "yt"))
        expect(s.appPhase == .progress, "stays on the log screen; no prompt")
        let entries = (try? c.mainContext.fetch(FetchDescriptor<TimelineEntry>())) ?? []
        expect(entries.count == 2, "timeline still recorded while suppressed")
    }
}
