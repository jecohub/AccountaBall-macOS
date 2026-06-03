import Foundation
@testable import AccountaBall

func runDurationDeltaTests() {
    suite("DurationDeltaTests") {
        let faster = DurationDelta.compare(current: 34*60, previous: 52*60)
        expect(faster.fasterThanPrevious == true, "34<52 is faster")
        expect(faster.deltaMinutes == 18, "18 minute delta")
        let slower = DurationDelta.compare(current: 60*60, previous: 50*60)
        expect(slower.fasterThanPrevious == false, "slower")
        expect(slower.deltaMinutes == 10, "abs delta minutes")
    }
}
