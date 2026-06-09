import Foundation
import SwiftData
@testable import AccountaBall

private class FixedRecapAI: AIService {
    /// Captures the steps the engine passed in, so the test can prove the
    /// session timeline was coalesced and handed to the AI.
    var receivedSteps: [String] = []
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap {
        receivedSteps = steps
        return TaskRecap(summary: "did stuff", steps: ["a", "b"], duration: durationSeconds, comparison: nil)
    }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { true }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
    func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { FreeBallSummary(narrative: "", categories: [], insight: "", workingOn: [], people: [], codeContext: [], openThreads: []) }
}

@MainActor
func runEngineCompletionTests() async {
    await suite("EngineCompletionTests") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "Write proposal", context: "Q3")]
        s.startSession()
        let ai = FixedRecapAI()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: ai, notificationService: notif)
        engine.modelContext = ctx
        engine.beginSession(tasks: s.tasks)
        engine.record(taskIndex: 0, label: "writing")
        // Guarantee a distinct timestamp so the chronological sort in
        // summarizeCompletion is deterministic (SwiftData entries are unordered).
        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
        engine.record(taskIndex: 0, label: "editing")

        await engine.summarizeCompletion(taskIndex: 0)

        let kts = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>())) ?? []
        expect(kts.count == 1, "one KnowledgeTask created")
        let completions = kts.first?.completions ?? []
        expect(completions.count == 1, "one TaskCompletion recorded")
        // The coalesced session timeline is fed to the AI...
        expect(ai.receivedSteps == ["writing", "editing"], "coalesced timeline steps passed to AI")
        // ...and the AI recap's steps are what get stored (plan Task 14, Step 2).
        expect(completions.first?.steps == ["a", "b"], "recap's steps stored on completion")
        expect(completions.first?.summary == "did stuff", "summary from AI")
    }
}
