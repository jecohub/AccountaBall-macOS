import Foundation

/// One deduped block of the live session, fed to the summarizer.
struct FreeBallTranscriptEntry: Equatable {
    let text: String
    let seconds: TimeInterval   // how long this screen was up
}
