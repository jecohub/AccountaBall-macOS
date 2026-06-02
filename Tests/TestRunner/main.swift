import Foundation

// Run all test suites on the main queue to satisfy @MainActor isolation
DispatchQueue.main.async {
    runBallStateTests()
    runTaskSessionTests()
    runAppStateTests()
    runAccountabilityEngineTests()
    runOCRServiceTests()
    runClaudeAIServiceTests()
    runAppPhaseTests()
    runTaskItemTests()
    runMultiTaskResultTests()
    reportAndExit()
}
RunLoop.main.run()
