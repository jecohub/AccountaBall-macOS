import Foundation
import SwiftData
@testable import AccountaBall

/// Task 5: task mode persists full OCR into the shared `Capture` model, de-duped
/// exactly like FreeBall, so task-mode time builds the same high-fidelity context.
@MainActor
func runCaptureIngestTests() async {
    await suite("CaptureIngest") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let state = AppState()
        state.tasks = [TaskItem(task: "write proposal", context: "for client")]
        state.startSession()
        let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: AlwaysOnTaskAI(), notificationService: notif)
        engine.modelContext = container.mainContext
        engine.startSessionForTest()

        engine.ingestCapture(text: "screen A")            // new screen -> new row
        engine.ingestCapture(text: "screen A")            // same -> extend, no new row
        engine.ingestCapture(text: "totally different B") // new screen -> new row

        let caps = (try? container.mainContext.fetch(FetchDescriptor<Capture>())) ?? []
        expect(caps.count == 2, "dedup collapses identical consecutive screens")
        expect(caps.allSatisfy { $0.mode == "task" }, "task-mode captures tagged task")
        expect(caps.allSatisfy { $0.sessionId == engine.currentSession?.id }, "captures linked to session")
    }
}
