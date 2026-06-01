import Foundation

// Run all test suites on the main queue to satisfy @MainActor isolation
DispatchQueue.main.async {
    runBallStateTests()
    runTaskSessionTests()
    runAppStateTests()
    runAccountabilityEngineTests()
    runOCRServiceTests()
    runClaudeAIServiceTests()
    reportAndExit()
}
RunLoop.main.run()
