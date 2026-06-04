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

    /// Coalesce contiguous entries with the same `(taskIndex, label)` into
    /// `TimelineRange`s. The end of the last range extends one `cycleSeconds`
    /// past its final entry's timestamp. Entries are sorted chronologically
    /// first (the caller provides them in `(Date, ...)` format).
    static func ranges(sessionStart: Date,
                       entries: [(at: Date, taskIndex: Int?, label: String)],
                       cycleSeconds: TimeInterval = AppConstants.cycleSeconds) -> [TimelineRange] {
        let sorted = entries.sorted { $0.at < $1.at }
        var out: [TimelineRange] = []
        var i = 0
        while i < sorted.count {
            let startOff = sorted[i].at.timeIntervalSince(sessionStart)
            let idx = sorted[i].taskIndex, label = sorted[i].label
            var j = i
            while j + 1 < sorted.count && sorted[j+1].taskIndex == idx && sorted[j+1].label == label {
                j += 1
            }
            // End = next group's start, or last entry + one cycle.
            let endOff: TimeInterval = (j + 1 < sorted.count)
                ? sorted[j+1].at.timeIntervalSince(sessionStart)
                : sorted[j].at.timeIntervalSince(sessionStart) + cycleSeconds
            out.append(TimelineRange(startOffset: startOff, endOffset: endOff, label: label, taskIndex: idx))
            i = j + 1
        }
        return out
    }
}
