@testable import AccountaBall

func runAppPhaseTests() {
    suite("AppPhaseTests") {
        expect(AppPhase.idle == AppPhase.idle, "idle == idle")
        expect(AppPhase.welcome != AppPhase.setup, "welcome != setup")

        let all: [AppPhase] = [.idle, .welcome, .setup, .session, .offTask, .progress, .complete]
        expect(all.count == 7, "all 7 phases exist")
    }
}
