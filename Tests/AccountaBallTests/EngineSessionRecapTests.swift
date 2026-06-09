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
    func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { FreeBallSummary(narrative: "", categories: [], insight: "") }
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

    await suite("EngineSessionRecap.transparencyLog") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = c.mainContext

        let s = AppState()
        s.tasks = [TaskItem(task: "Write proposal", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: EmptySessionAI(), notificationService: NotificationService())
        engine.modelContext = ctx
        engine.beginSession(tasks: s.tasks)
        engine.record(taskIndex: 0, label: "vscode")

        guard let session = engine.currentSession else {
            expect(false, "session active"); return
        }
        let start = session.startedAt

        // Seed three checks with DISTINCT timestamps (out of chronological order
        // on purpose) so the time-ordering assertion is meaningful.
        func seed(at: Date, kind: String, excuse: String, rule: String) {
            let event = JustificationEvent(
                at: at, excuse: excuse, justified: false, inferredTaskIndex: nil,
                activity: "browsing", rule: rule, kind: kind
            )
            ctx.insert(event)
            session.justifications.append(event)
        }
        seed(at: start.addingTimeInterval(30), kind: "offtask", excuse: "x", rule: "")
        seed(at: start.addingTimeInterval(10), kind: "ambiguous", excuse: "research", rule: "")
        seed(at: start.addingTimeInterval(20), kind: "offtask", excuse: "x", rule: "")
        try? ctx.save()

        await engine.finalizeSessionRecap()
        guard let recap = s.sessionRecap else {
            expect(false, "recap built"); return
        }
        expect(recap.checks.count == 3, "checks are surfaced")
        expect(recap.driftCount == 2, "drift count surfaced")
        expect(recap.driftLimit == s.driftLimit, "drift limit surfaced")
        expect(recap.checks == recap.checks.sorted { $0.offset < $1.offset }, "checks are time-ordered")
    }
}
