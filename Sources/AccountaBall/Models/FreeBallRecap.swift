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
    let openThreads: [String]
}

/// The AI's structured output for one ended session.
struct FreeBallSummary: Equatable {
    let narrative: String
    let categories: [CategorySpan]
    let insight: String
    // Context extraction — grounded in the session transcript.
    let workingOn: [String]
    let people: [String]
    let codeContext: [String]
    let openThreads: [String]
}

/// UI-facing recap published to AppState and rendered by FreeBallRecapView.
struct FreeBallRecap: Equatable {
    let date: Date
    let duration: TimeInterval
    let narrative: String
    let categories: [CategorySpan]
    let insight: String
    let workingOn: [String]
    let people: [String]
    let codeContext: [String]
    let openThreads: [String]
    let recapPending: Bool   // AI was unavailable at End Session; raw kept for later
}

@available(macOS 14, *)
extension FreeBallRecap {
    /// Build a recap from a stored session (history browser + re-open).
    init(from s: FreeBallSession) {
        let end = s.endedAt ?? s.startedAt
        self.init(date: end, duration: end.timeIntervalSince(s.startedAt),
                  narrative: s.narrative, categories: s.categories, insight: s.insight,
                  workingOn: s.workingOn, people: s.people, codeContext: s.codeContext,
                  openThreads: s.openThreads, recapPending: s.recapPending)
    }
}
