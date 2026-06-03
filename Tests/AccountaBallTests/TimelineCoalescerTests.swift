import Foundation
@testable import AccountaBall

func runTimelineCoalescerTests() {
    suite("TimelineCoalescerTests") {
        let reads: [(Int?, String)] = [
            (0, "editing AppDelegate"), (0, "editing AppDelegate"), (0, "running tests"),
            (nil, "twitter"), (0, "editing Engine")
        ]
        let steps = TimelineCoalescer.labelsForTask(index: 0, reads: reads)
        expect(steps == ["editing AppDelegate", "running tests", "editing Engine"],
               "dedupes consecutive, keeps order, skips off-task")

        let cycles = TimelineCoalescer.cycleCountForTask(index: 0, reads: reads)
        expect(cycles == 4, "counts on-task reads for the index")
    }
}
