import Foundation

enum TimelineCoalescer {
    /// Ordered, consecutive-deduped labels for one task index. Off-task reads are skipped
    /// but DO break a run (so a label can repeat after an interruption).
    static func labelsForTask(index: Int, reads: [(Int?, String)]) -> [String] {
        var out: [String] = []
        for (idx, label) in reads where idx == index {
            if out.last != label, !label.isEmpty { out.append(label) }
        }
        return out
    }

    static func cycleCountForTask(index: Int, reads: [(Int?, String)]) -> Int {
        reads.filter { $0.0 == index }.count
    }
}
