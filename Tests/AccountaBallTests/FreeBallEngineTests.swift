import Foundation
import SwiftData
@testable import AccountaBall

/// Fake returning a fixed FreeBall summary; records that it was called.
final class FreeBallFakeAI: AIService {
    var called = false
    var summary = FreeBallSummary(narrative: "N", categories: [CategorySpan(label: "Coding", minutes: 5)], insight: "I",
                                  workingOn: [], people: [], codeContext: [], openThreads: [])
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { true }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
    func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { called = true; return summary }
}

/// Fake whose summarizeFreeBall throws (provider unreachable at End Session).
final class FreeBallFailAI: AIService {
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { false }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
    func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { throw URLError(.cannotConnectToHost) }
}

@MainActor
private func makeFreeBallEngine(ai: AIService) -> (FreeBallEngine, AppState, ModelContainer) {
    let state = AppState()
    let container = try! AccountaBallStore.makeContainer(inMemory: true)
    let eng = FreeBallEngine(state: state, captureService: ScreenCaptureService(),
                             ocrService: OCRService(), aiService: ai)
    eng.modelContext = container.mainContext
    // NOTE: return the CONTAINER, not just its mainContext. A ModelContext does
    // not keep its container alive; dropping the container here would deallocate
    // the in-memory store and trap on the next insert.
    return (eng, state, container)
}

@MainActor
func runFreeBallEngineTests() async {
    suite("FreeBallEngine_begin") {
        let (eng, state, container) = makeFreeBallEngine(ai: FreeBallFakeAI())
        _ = container   // keep the in-memory store alive for the suite
        eng.beginForTest()   // begin without starting the real capture loop
        expect(state.appPhase == .freeBall, "begin -> .freeBall")
        expect(state.freeBallStartTime != nil, "start time set")
        expect(eng.currentSession != nil, "session created")
    }

    suite("FreeBallEngine_ingest_dedup") {
        let (eng, _, container) = makeFreeBallEngine(ai: FreeBallFakeAI())
        let ctx = container.mainContext
        eng.beginForTest()
        eng.ingest(text: "editing AppDelegate.swift line 1")
        eng.ingest(text: "editing AppDelegate.swift line 1 ")   // same screen -> extend
        eng.ingest(text: "watching youtube basketball video")   // new screen -> new block
        let caps = (try? ctx.fetch(FetchDescriptor<FreeBallCapture>())) ?? []
        expect(caps.count == 2, "dedup collapsed identical consecutive reads")
    }

    await suite("FreeBallEngine_end_summarizes") {
        let ai = FreeBallFakeAI()
        let (eng, state, container) = makeFreeBallEngine(ai: ai)
        _ = container   // keep the in-memory store alive for the suite
        eng.beginForTest()
        eng.ingest(text: String(repeating: "real work content ", count: 10))
        await eng.end()
        expect(ai.called, "summarizeFreeBall called at end")
        expect(state.appPhase == .freeBallRecap, "end -> .freeBallRecap")
        expect(state.freeBallRecap?.narrative == "N", "recap published")
        expect(state.freeBallSummarizing == false, "summarizing cleared")
        expect(eng.currentSession == nil, "session closed")
    }

    await suite("FreeBallEngine_end_emptySession") {
        let ai = FreeBallFakeAI()
        let (eng, state, container) = makeFreeBallEngine(ai: ai)
        _ = container   // keep the in-memory store alive for the suite
        eng.beginForTest()           // no ingest -> trivial session
        await eng.end()
        expect(!ai.called, "trivial session skips the AI call")
        expect(state.appPhase == .freeBallRecap, "still shows a recap")
    }

    await suite("FreeBallEngine_end_aiUnavailable") {
        let (eng, state, container) = makeFreeBallEngine(ai: FreeBallFailAI())
        let ctx = container.mainContext
        eng.beginForTest()
        eng.ingest(text: String(repeating: "real work content ", count: 10))
        await eng.end()
        expect(state.freeBallRecap?.recapPending == true, "recap marked pending on AI failure")
        let sessions = (try? ctx.fetch(FetchDescriptor<FreeBallSession>())) ?? []
        expect(sessions.first?.recapPending == true, "session persisted recapPending")
        expect(sessions.first?.captures.isEmpty == false, "raw captures retained for later")
    }
}
