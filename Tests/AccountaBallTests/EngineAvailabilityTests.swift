import Foundation
@testable import AccountaBall

/// AI fake that starts in an "unhealthy" state and flips to healthy once the
/// outage is cleared via `recover()`. This models a provider going down then
/// coming back. The contract is deterministic regardless of how many times the
/// engine's background health-poller calls `healthCheck()` (it would otherwise
/// race a plain call-counter), which is what lets the suite assert the
/// unhealthy→healthy transition reliably.
@MainActor
private final class FlakyAI: AIService {
    private var healthy = false
    func recover() { healthy = true }
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { .onTask(index: 0, label: "") }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: false, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { healthy }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
}

@MainActor
func runEngineAvailabilityTests() async {
    await suite("EngineAvailability_pauseAndResume") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.tasks = [TaskItem(task: "x", context: "")]; s.startSession()
        let ai = FlakyAI()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: ai, notificationService: NotificationService())
        engine.modelContext = c.mainContext; engine.beginSession(tasks: s.tasks)

        let unhealthy = await ai.healthCheck()     // provider is down
        expect(!unhealthy, "fake reports unhealthy while down")

        engine.enterAIUnavailable()
        expect(s.appPhase == .aiUnavailable, "entered aiUnavailable")
        expect(s.aiUnavailableHint != nil, "hint set")
        expect(s.isCapturing == false, "outage stops capturing so recover can re-trigger the watcher edge")

        ai.recover()                               // provider comes back
        let ok = await ai.healthCheck()            // now healthy
        expect(ok, "fake reports healthy after recovery")
        engine.recoverFromAIUnavailable()
        expect(s.appPhase == .session, "resumed to session")
        expect(s.aiUnavailableHint == nil, "hint cleared")
        expect(s.isCapturing == true, "recovery re-arms capturing (false→true edge restarts the loop)")
    }

    // Launched with the provider down (user is on .welcome, no session yet):
    // recovery must return to .welcome, NOT dump them into a task-less session.
    await suite("EngineAvailability_recoverReturnsToOriginPhase") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false,"c"); return }
        let s = AppState(); s.appPhase = .welcome          // fresh launch, no session
        let ai = FlakyAI()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(), ocrService: OCRService(), aiService: ai, notificationService: NotificationService())
        engine.modelContext = c.mainContext

        engine.enterAIUnavailable()
        expect(s.appPhase == .aiUnavailable, "entered aiUnavailable from welcome")
        ai.recover()
        engine.recoverFromAIUnavailable()
        expect(s.appPhase == .welcome, "recovery returns to .welcome, not .session")
        expect(s.isCapturing == false, "no capturing armed when there was no session")
    }

    // Cancellation-class errors are benign (we cancelled the request) and must
    // never be treated as a provider outage.
    await suite("EngineAvailability_benignCancellation") {
        expect(AccountabilityEngine.isBenignCancellation(CancellationError()), "CancellationError is benign")
        expect(AccountabilityEngine.isBenignCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)), "URLError cancelled (-999) is benign")
        expect(!AccountabilityEngine.isBenignCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)), "cannotConnectToHost is a real outage, not benign")
        expect(!AccountabilityEngine.isBenignCancellation(NSError(domain: "Other", code: -999)), "non-URL -999 is not treated as cancellation")
    }
}
