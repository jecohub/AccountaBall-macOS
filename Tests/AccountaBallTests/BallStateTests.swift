@testable import AccountaBall

func runBallStateTests() {
    suite("BallStateTests") {
        expect(BallState.onTask == BallState.onTask, "onTask == onTask")
        expect(BallState.onTask != BallState.offTask, "onTask != offTask")

        let states: [BallState] = [.idle, .onTask, .offTask, .done]
        expect(states.count == 4, "all 4 cases exist")
    }
}
