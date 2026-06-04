import Foundation
@testable import AccountaBall

/// AI fake whose classifyMulti always reports on-task and whose health check
/// always passes. Used to prove that an AI *error* (nil cycle) is never treated
/// as off-task.
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
