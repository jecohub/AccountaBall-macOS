@testable import AccountaBall
import Foundation

func runTimelineRangeTests() {
    suite("TimelineRange_coalesce") {
        let start = Date()
        func e(_ s: TimeInterval, _ idx: Int?, _ l: String) -> (at: Date, taskIndex: Int?, label: String) {
            (at: start.addingTimeInterval(s), taskIndex: idx, label: l)
        }
        let entries = [e(0,0,"vscode"), e(5,0,"vscode"), e(10,nil,"linkedin"), e(15,nil,"linkedin")]
        let ranges = TimelineCoalescer.ranges(sessionStart: start, entries: entries, cycleSeconds: 5)
        expect(ranges.count == 2, "two coalesced ranges")
        expect(ranges[0] == TimelineRange(startOffset: 0, endOffset: 10, label: "vscode", taskIndex: 0), "first range 0–10 vscode")
        expect(ranges[1] == TimelineRange(startOffset: 10, endOffset: 20, label: "linkedin", taskIndex: nil), "second range 10–20 off-task")
    }

    suite("TimelineRange_singleEntry") {
        let start = Date()
        let entries = [(at: start, taskIndex: 0, label: "code")]
        let ranges = TimelineCoalescer.ranges(sessionStart: start, entries: entries, cycleSeconds: 5)
        expect(ranges.count == 1, "one range from single entry")
        expect(ranges[0].startOffset == 0, "starts at 0")
        expect(ranges[0].endOffset == 5, "ends at cycleSeconds (5)")
    }

    suite("TimelineRange_empty") {
        let ranges = TimelineCoalescer.ranges(sessionStart: Date(), entries: [], cycleSeconds: 5)
        expect(ranges.isEmpty, "empty entries -> empty ranges")
    }

    suite("TimelineRange_interleavedTasks") {
        let start = Date()
        func e(_ s: TimeInterval, _ idx: Int?, _ l: String) -> (at: Date, taskIndex: Int?, label: String) {
            (at: start.addingTimeInterval(s), taskIndex: idx, label: l)
        }
        let entries = [e(0,0,"vscode"), e(5,1,"slides"), e(10,0,"vscode"), e(15,nil,"yt")]
        let ranges = TimelineCoalescer.ranges(sessionStart: start, entries: entries, cycleSeconds: 5)
        expect(ranges.count == 4, "four ranges (no adjacent same labels)")
        expect(ranges[0].taskIndex == 0, "first range task 0")
        expect(ranges[1].taskIndex == 1, "second range task 1")
        expect(ranges[2].taskIndex == 0, "third range task 0 again")
        expect(ranges[3].taskIndex == nil, "fourth range off-task")
    }
}
