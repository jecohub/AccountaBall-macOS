import Foundation

// All test suites run on the main actor. Sync suites run inline; the v3 engine
// suites are `@MainActor async` (they drive the engine's async methods). The
// entire run is driven by ONE top-level `Task { @MainActor in ... }` plus
// `RunLoop.main.run()`. The run loop services the main-actor executor's jobs, so
// every `await` inside the suites makes progress. `reportAndExit()` calls
// `exit()`, which is how we break out of the otherwise-never-returning run loop.
//
// Do NOT reintroduce semaphores, DispatchGroup.wait(), or nested
// `RunLoop.main.run(mode:before:)` here: blocking the main thread while
// main-actor async work is pending is what deadlocked this runner before.
@MainActor
func runAllTests() async {
    runBallStateTests()
    runTaskSessionTests()
    runAppStateTests()
    runAppStateV2Tests()
    runAccountabilityEngineTests()
    runOCRServiceTests()
    runClaudeAIServiceTests()
    runAppPhaseTests()
    runTaskItemTests()
    runMultiTaskResultTests()
    runMultiTaskClassificationTests()
    runTaskMatcherTests()
    runDurationDeltaTests()
    runExcuseVerdictTests()
    runTimelineCoalescerTests()
    runTimelineRangeTests()
    runPersistenceTests()
    runEngineSessionTests()
    runSnapshotTests()
    runOpenRouterPromptTests()
    runOllamaServiceTests()
    runSummarizeSessionParseTests()
    runDebugLogTests()

    // Async v3 engine suites — awaited directly.
    await runEngineAllowanceTests()
    await runEngineCompletionTests()
    await runEngineMatchTests()
    await runEngineSessionRecapTests()

    reportAndExit()
}

Task { @MainActor in
    await runAllTests()
}
RunLoop.main.run()
