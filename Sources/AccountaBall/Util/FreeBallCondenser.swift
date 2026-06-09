import Foundation

/// Cap the transcript size fed to a local model. Budget is split across entries
/// in proportion to how long each screen was up, so the longest-lived screens
/// keep the most text and brief blips are trimmed first. Chronological order is
/// preserved. (Chunk-then-stitch for extreme sessions is a future refinement.)
enum FreeBallCondenser {
    /// Per-entry floor so brief blips never vanish entirely.
    private static let floorChars = 40

    static func condense(_ entries: [FreeBallTranscriptEntry],
                         maxChars: Int = AppConstants.freeBallMaxTranscriptChars) -> [FreeBallTranscriptEntry] {
        let total = entries.reduce(0) { $0 + $1.text.count }
        if total <= maxChars { return entries }
        // Reserve each entry's floor up front, then split the REMAINING budget by
        // dwell time. Reserving first keeps the grand total at or under maxChars
        // (a floor added on top of a proportional share is what blew the budget).
        let reserved = entries.reduce(0) { $0 + min(floorChars, $1.text.count) }
        let remaining = max(0, maxChars - reserved)
        let weightTotal = entries.reduce(0.0) { $0 + max($1.seconds, 1) }
        return entries.map { e in
            let floor = min(floorChars, e.text.count)
            let share = max(e.seconds, 1) / weightTotal
            let budget = floor + Int(Double(remaining) * share)
            let trimmed = e.text.count <= budget ? e.text : String(e.text.prefix(budget))
            return FreeBallTranscriptEntry(text: trimmed, seconds: e.seconds)
        }
    }
}
