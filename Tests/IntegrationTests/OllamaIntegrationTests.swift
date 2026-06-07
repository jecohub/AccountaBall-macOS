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
private func isAmbiguous(_ r: MultiTaskResult) -> Bool { if case .ambiguous = r { return true }; return false }

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

    // MARK: classifyMulti — 3-state bias: borderline screen must NOT be OFFTASK
    // This is the only test that exercises the REAL model's 3-state behaviour end
    // to end. It guards the core trust property from the classify prompt: "When you
    // are unsure, prefer TASK:N or AMBIGUOUS over OFFTASK." A generic spreadsheet
    // (numbers + headers) could plausibly be the budget proposal or could be
    // something unrelated — a well-behaved biased model must answer AMBIGUOUS (or
    // ON), never a false "get back to work". We assert NOT .offTask; the specific
    // label is free text so we don't assert on it.
    await suite("OllamaIntegration_classify3StateBias") {
        let tasks = [TaskItem(task: "Write the Q3 budget proposal",
                              context: "A document outlining projected spend and revenue for next quarter")]

        // Genuinely borderline: a bare spreadsheet with generic financial-ish
        // headers and numbers. It COULD be the budget work, but nothing names the
        // task, the quarter, or a proposal — so a calibrated model should hedge to
        // AMBIGUOUS, and a biased one must never escalate to OFFTASK.
        let borderlineScreen = "Sheet1 | A B C D | Category Amount Total Notes | 1200 450 1650 | 980 320 1300 | 2100 760 2860 | Subtotal 4280"
        let result = (try? await ai.classifyMulti(tasks: tasks, screenText: borderlineScreen, allowanceRulesByIndex: [:])) ?? .offTask(label: "ERROR")
        print("    → borderline generic-spreadsheet screen classified as: \(result)")
        expect(isAmbiguous(result) || isOnTask(result),
               "borderline generic spreadsheet → .ambiguous or .onTask (model hedges when unsure)")
        expect(!isOffTask(result),
               "borderline screen must NOT be .offTask — no false \"get back to work\" when unsure")
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

        // Regression (real QA finding): indirect-but-genuine research the user
        // ties to their task must be justified. The earlier prompt rejected this
        // as "off-topic research" even though the user explained the connection.
        let researchTasks = [TaskItem(task: "Debugging AccountaBall v3.1.1",
                                      context: "Using VS Code, terminal, and notes to fix bugs in Ollama")]
        let research = (try? await ai.evaluateExcuse(
            excuse: "I'm learning about a new LLM Odysseus. I need this to improve AccountaBall.",
            tasks: researchTasks, screenText: "Brave — github.com/pewdiepie-archdaemon/odysseus")) ?? ExcuseVerdict(justified: false, taskIndex: nil, rule: "ERROR")
        print("    → indirect-research excuse verdict: justified=\(research.justified)")
        expect(research.justified, "research the user ties to their task → justified")

        // Regression (real QA finding): a noisy multi-tab screen used to flip this
        // to NOT_JUSTIFIED. The verdict is now judged on the explanation, not the
        // screen — so checking a service the user will use for the task is justified
        // even with unrelated tabs in the OCR.
        let svc = (try? await ai.evaluateExcuse(
            excuse: "Just checking my OpenRouter usage. We'll be using this as the next LLM for AccountaBall.",
            tasks: researchTasks,
            screenText: "Brave substack.com/home/post/199355984 openrouter.ai/workspaces/default many tabs")) ?? ExcuseVerdict(justified: false, taskIndex: nil, rule: "ERROR")
        print("    → service-usage excuse verdict: justified=\(svc.justified)")
        expect(svc.justified, "checking a service the user will use for the task → justified (despite noisy screen)")

        // Regression (real QA finding): casual "just checking" phrasing tied to a
        // task must not be rejected as a "vague pretext". The connection to the
        // task is what decides, not the wording.
        let casual = (try? await ai.evaluateExcuse(
            excuse: "I'm just checking my credits in DeepSeek. We might use this in AccountaBall so I'm checking it.",
            tasks: researchTasks, screenText: "")) ?? ExcuseVerdict(justified: false, taskIndex: nil, rule: "ERROR")
        print("    → casual-but-tied excuse verdict: justified=\(casual.justified)")
        expect(casual.justified, "\"just checking\" a service tied to the task → justified, not a vague pretext")
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
