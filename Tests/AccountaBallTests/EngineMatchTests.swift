import Foundation
import SwiftData
@testable import AccountaBall

@MainActor
func runEngineMatchTests() async {
    await suite("EngineMatchTests") {
        // Cheap-path test
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let kt = KnowledgeTask(normalizedTitle: "write proposal", lastCompletedAt: .now)
        kt.originalTitles = ["Write proposal"]
        ctx.insert(kt)
        try? ctx.save()

        // Build a minimal engine (no AI calls in cheap path)
        final class NoMatchAI: AIService {
            func classify(task: String, screenText: String) async throws -> BallState { .onTask }
            func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
            func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
            func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
            func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? {
                // Prove cheap path wins by throwing — if this is called, the test fails
                throw NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "AI match should NOT be called when cheap path hits"])
            }
            func healthCheck() async -> Bool { true }
            func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
            func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { FreeBallSummary(narrative: "", categories: [], insight: "") }
        }
        let s = AppState()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: NoMatchAI(), notificationService: NotificationService())
        engine.modelContext = ctx

        let matched = await engine.proposeMatch(for: "Write proposal")
        expect(matched?.normalizedTitle == "write proposal", "cheap path matched by normalized original")
    }
}
