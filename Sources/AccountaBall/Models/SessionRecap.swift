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

/// One entry in the session's transparency log — a moment the ball asked or the
/// user chose. Rendered calmly in past tense in the recap.
struct CheckLogItem: Equatable {
    let offset: TimeInterval        // seconds from session start
    let kind: String                // "ambiguous" | "offtask" | "auto-return"
    let activity: String
    let note: String                // user's response / what happened
}

/// The full end-of-session breakdown: mechanical timeline ranges + per-task
/// AI commentary (or local comparisons if the AI call fails), plus the
/// transparency log (every check) and the drift summary.
struct SessionRecap: Equatable {
    let ranges: [TimelineRange]
    let perTask: [PerTaskComment]
    let checks: [CheckLogItem]
    let driftCount: Int
    let driftLimit: Int
    let commitmentBroken: Bool
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
