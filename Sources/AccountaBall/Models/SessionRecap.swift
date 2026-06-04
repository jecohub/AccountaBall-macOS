import Foundation

/// One contiguous block of the session timeline with the same activity label.
struct TimelineRange: Equatable {
    let startOffset: TimeInterval   // seconds from session start
    let endOffset: TimeInterval
    let label: String
    let taskIndex: Int?             // nil = off-task
}

/// AI-written prose for one task in the end-of-session breakdown.
struct PerTaskComment: Equatable {
    let taskTitle: String
    let comment: String
    let suggestion: String?
}

/// The full end-of-session breakdown: mechanical timeline ranges + per-task
/// AI commentary (or local comparisons if the AI call fails).
struct SessionRecap: Equatable {
    let ranges: [TimelineRange]
    let perTask: [PerTaskComment]
}

/// Input to the AI's `summarizeSession` — one per task. The local comparison
/// string is authoritative; the AI writes the human-readable comment.
struct PerTaskSessionInput: Equatable {
    let title: String
    let durationSeconds: TimeInterval
    let lastDurationSeconds: TimeInterval?
    let averageSeconds: TimeInterval?
    let offTaskCount: Int
    let steps: [String]
    let localComparison: String   // computed locally, not AI-invented
}
