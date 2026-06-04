import Foundation

// Driver for the LIVE integration suite. Same single-Task + RunLoop pattern as
// Tests/TestRunner/main.swift (see that file for why no semaphores). Kept as a
// separate executable from `make test` so the slow, network-dependent live
// suite never gates the fast unit run.
@MainActor
func runAllIntegrationTests() async {
    await runOllamaIntegrationTests()
    reportAndExit()
}

Task { @MainActor in
    await runAllIntegrationTests()
}
RunLoop.main.run()
