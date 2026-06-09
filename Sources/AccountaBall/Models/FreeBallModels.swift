import SwiftData
import Foundation

/// A labeled slice of session time (the categorized breakdown). Stored as a
/// Codable value on FreeBallSession and round-tripped to the recap UI.
struct CategorySpan: Codable, Equatable {
    var label: String
    var minutes: Int
}

@available(macOS 14, *)
@Model
final class FreeBallSession {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var cycleCount: Int = 0
    // Distilled recap (kept long-term; feeds cross-session learning).
    var narrative: String = ""
    var categories: [CategorySpan] = []
    var insight: String = ""
    // Context extraction (grounded in the transcript), kept long-term.
    var workingOn: [String] = []
    var people: [String] = []
    var codeContext: [String] = []
    var openThreads: [String] = []
    /// True when End Session couldn't reach the AI; raw captures kept for a later pass.
    var recapPending: Bool = false
    @Relationship(deleteRule: .cascade) var captures: [FreeBallCapture] = []
    init(startedAt: Date) { self.startedAt = startedAt }
}

@available(macOS 14, *)
@Model
final class FreeBallCapture {
    var firstSeenAt: Date    // when this screen first appeared
    var lastSeenAt: Date     // extended while the screen stays effectively unchanged
    var text: String         // full OCR text of the screen
    init(firstSeenAt: Date, lastSeenAt: Date, text: String) {
        self.firstSeenAt = firstSeenAt; self.lastSeenAt = lastSeenAt; self.text = text
    }
    /// How long this screen was up, in seconds.
    var seconds: TimeInterval { lastSeenAt.timeIntervalSince(firstSeenAt) }
}
