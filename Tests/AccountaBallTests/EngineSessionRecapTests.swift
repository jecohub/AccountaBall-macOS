import Foundation
import SwiftData
@testable import AccountaBall

/// AI fake that returns an empty array from summarizeSession — tests the
/// local-comparison fallback path.
private final class EmptySessionAI: AIService {
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { true }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
}

@MainActor
func runEngineSessionRecapTests() async {
    await suite("EngineSessionRecap") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = c.mainContext

        // Prior completion (older session): 900s
        let kt = KnowledgeTask(normalizedTitle: "write proposal", lastCompletedAt: .now.addingTimeInterval(-86400))
        kt.completions.append(TaskCompletion(completedAt: .now.addingTimeInterval(-86400), duration: 900, summary: "s", steps: ["a"], offTaskCount: 0))
        ctx.insert(kt); try? ctx.save()

        let s = AppState()
        s.tasks = [TaskItem(task: "Write proposal", context: "")]
        s.startSession()
        s.tasks[0].timeOnTask = 600
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: EmptySessionAI(), notificationService: NotificationService())
        engine.modelContext = ctx
        engine.beginSession(tasks: s.tasks)
        engine.record(taskIndex: 0, label: "vscode")

        await engine.finalizeSessionRecap()
        expect(s.sessionRecap != nil, "recap built")
        expect(s.sessionRecap?.ranges.isEmpty == false, "timeline ranges present")
        let c0 = s.sessionRecap?.perTask.first
        expect(c0?.comment.contains("Faster") == true, "local comparison says faster (600 < 900)")
    }
}
