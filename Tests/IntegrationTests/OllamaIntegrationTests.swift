import Foundation
import SwiftData
@testable import AccountaBall

// LIVE integration tests against a running local Ollama daemon. These are NOT
// part of `make test` — they hit the real model (non-deterministic, slow) and
// require Ollama running with the configured model pulled. Run with
// `make test-integration`.
//
// What this proves that the mocked unit tests cannot: the REAL provider path —
// that classifyMulti / evaluateExcuse / summarizeSession actually return output
// the parsers accept and that the model classifies clear-cut cases correctly.
// This covers the plan's deferred "re-test with Ollama actually running" item.
//
// Design notes:
// - If Ollama is unreachable, the suite SKIPS cleanly (exit 0) rather than
//   failing — so it's safe to run in environments without Ollama.
// - The "provider down" check points a service at a dead port instead of
//   killing your running Ollama (non-invasive). `pkill -x ollama` would also
//   work but isn't necessary to prove the healthCheck contract.
// - Assertions use clear-cut scenarios a 7B model handles reliably, and every
//   live result is printed so an occasional model wobble is easy to diagnose.

private func isOnTask(_ r: MultiTaskResult) -> Bool { if case .onTask = r { return true }; return false }
private func isOffTask(_ r: MultiTaskResult) -> Bool { if case .offTask = r { return true }; return false }

@MainActor
func runOllamaIntegrationTests() async {
    let ai = OllamaAIService()   // default localhost:11434, qwen2.5:7b

    // Gate: skip cleanly if the live provider isn't available.
    guard await ai.healthCheck() else {
        print("\n⚠️  Ollama not reachable with the configured model — SKIPPING live integration suite.")
        print("    Start Ollama and run `ollama pull qwen2.5:7b`, then `make test-integration`.")
        return
    }
    print("\n(live Ollama detected — running integration suite against \(ai.model))")

    // MARK: healthCheck contract (up / unreachable / missing model)
    await suite("OllamaIntegration_health") {
        let up = await ai.healthCheck()
        expect(up, "healthCheck() == true with live Ollama + model present")

        let unreachable = await OllamaAIService(host: "http://127.0.0.1:1").healthCheck()
        expect(!unreachable, "healthCheck() == false when the daemon is unreachable")

        let missingModel = await OllamaAIService(model: "definitely-not-real:999b").healthCheck()
        expect(!missingModel, "healthCheck() == false when the configured model isn't pulled")
    }

    // MARK: classifyMulti — clear on-task vs off-task
    await suite("OllamaIntegration_classify") {
        let tasks = [TaskItem(task: "Write the quarterly sales proposal",
                              context: "Due Friday, for the Acme account")]

        let onScreen = "Google Docs — Q3 Sales Proposal for Acme. Executive summary: this proposal outlines pricing tiers and projected revenue for the Acme account."
        let onResult = (try? await ai.classifyMulti(tasks: tasks, screenText: onScreen, allowanceRulesByIndex: [:])) ?? .offTask(label: "ERROR")
        print("    → on-task screen classified as: \(onResult)")
        expect(isOnTask(onResult), "clearly on-task screen → .onTask")

        let offScreen = "YouTube — Top 10 Funny Cat Fails Compilation 2026. Up next: more cat videos. Subscribe for daily fails."
        let offResult = (try? await ai.classifyMulti(tasks: tasks, screenText: offScreen, allowanceRulesByIndex: [:])) ?? .onTask(index: 0, label: "ERROR")
        print("    → off-task screen classified as: \(offResult)")
        expect(isOffTask(offResult), "clearly off-task screen → .offTask")
    }

    // MARK: evaluateExcuse — aligned vs unrelated
    await suite("OllamaIntegration_excuse") {
        let tasks = [TaskItem(task: "Write the quarterly sales proposal",
                              context: "Due Friday, for the Acme account")]
        let screen = "Gmail — compose message"

        let aligned = (try? await ai.evaluateExcuse(
            excuse: "I'm emailing the Acme client to get the pricing numbers I need to finish the proposal.",
            tasks: tasks, screenText: screen)) ?? ExcuseVerdict(justified: false, taskIndex: nil, rule: "ERROR")
        print("    → aligned excuse verdict: justified=\(aligned.justified)")
        expect(aligned.justified, "aligned excuse → justified")

        let unrelated = (try? await ai.evaluateExcuse(
            excuse: "Just checking my fantasy football scores real quick.",
            tasks: tasks, screenText: screen)) ?? ExcuseVerdict(justified: true, taskIndex: nil, rule: "ERROR")
        print("    → unrelated excuse verdict: justified=\(unrelated.justified)")
        expect(!unrelated.justified, "unrelated excuse → not justified")
    }

    // MARK: summarizeSession — returns parseable per-task commentary
    await suite("OllamaIntegration_summarizeSession") {
        let input = [PerTaskSessionInput(
            title: "Write the quarterly sales proposal",
            durationSeconds: 720, lastDurationSeconds: 900, averageSeconds: 960,
            offTaskCount: 1, steps: ["Google Docs — proposal", "Gmail — client"],
            localComparison: "Faster than last time (15m → 12m). Avg 16m.")]
        let comments = (try? await ai.summarizeSession(perTask: input)) ?? []
        print("    → summarizeSession returned \(comments.count) comment(s)")
        for c in comments {
            print("       • \(c.taskTitle): \(c.comment)\(c.suggestion.map { "  💡 \($0)" } ?? "")")
        }
        expect(comments.count >= 1, "summarizeSession returns at least one parseable comment")
        if let first = comments.first {
            expect(!first.comment.isEmpty, "comment text is non-empty")
        }
    }

    // MARK: end-to-end — real classification driven through the engine
    await suite("OllamaIntegration_enginePath") {
        guard let c = try? AccountaBallStore.makeContainer(inMemory: true) else { expect(false, "container"); return }
        let s = AppState()
        s.tasks = [TaskItem(task: "Write the quarterly sales proposal", context: "Due Friday")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: ScreenCaptureService(),
                                          ocrService: OCRService(), aiService: ai,
                                          notificationService: NotificationService())
        engine.modelContext = c.mainContext
        engine.beginSession(tasks: s.tasks)

        // The same call the capture loop makes, but with canned screen text so we
        // don't need Screen Recording / a real capture. Real model → real engine.
        let onScreen = "Google Docs — Q3 Sales Proposal. Drafting the executive summary and pricing table for Acme."
        let result = try? await ai.classifyMulti(tasks: s.activeTasks, screenText: onScreen, allowanceRulesByIndex: [:])
        engine.processCycle(result)
        print("    → engine after real on-task cycle: ballState=\(s.ballState), activeTaskIndex=\(String(describing: s.activeTaskIndex))")
        expect(s.ballState != .offTask, "real on-task classification does not flip the ball to off-task")
    }
}
