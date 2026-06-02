import Foundation

// Run all test suites on the main queue to satisfy @MainActor isolation
DispatchQueue.main.async {
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
    reportAndExit()
}
RunLoop.main.run()
