import Foundation
import SwiftData
@testable import AccountaBall

/// AI fake that always reports on-task / healthy. Used by the prompt-gate suite.
private final class AlwaysOnTaskAI: AIService {
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { true }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
}

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
