import Foundation

/// One deduped block of the live session, fed to the summarizer.
struct FreeBallTranscriptEntry: Equatable {
    let text: String
    let seconds: TimeInterval   // how long this screen was up
}

/// A prior session's distilled recap, fed as cross-session context (recaps, not
/// raw transcripts, so context stays small as history grows).
struct FreeBallPastRecap: Equatable {
    let narrative: String
    let categories: [CategorySpan]
    let insight: String
}

/// The AI's structured output for one ended session.
struct FreeBallSummary: Equatable {
    let narrative: String
    let categories: [CategorySpan]
    let insight: String
}

/// UI-facing recap published to AppState and rendered by FreeBallRecapView.
struct FreeBallRecap: Equatable {
    let duration: TimeInterval
    let narrative: String
    let categories: [CategorySpan]
    let insight: String
    let recapPending: Bool   // AI was unavailable at End Session; raw kept for later
}
