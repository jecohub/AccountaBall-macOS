import SwiftData
import Foundation

/// Join between a session and a project/thread: what this session advanced.
/// Links by UUID soft-reference (not @Relationship) because a Contribution may
/// reference either a WorkSession or a FreeBallSession — two different model
/// types a typed relationship can't span.
@available(macOS 14, *)
@Model
final class Contribution {
    var id: UUID = UUID()
    var at: Date
    var projectId: UUID
    var threadId: UUID?
    var sessionId: UUID
    var sessionKind: String     // "task" | "free"
    var minutes: Int
    var summary: String
    init(at: Date, projectId: UUID, threadId: UUID?, sessionId: UUID,
         sessionKind: String, minutes: Int, summary: String) {
        self.at = at; self.projectId = projectId; self.threadId = threadId
        self.sessionId = sessionId; self.sessionKind = sessionKind
        self.minutes = minutes; self.summary = summary
    }
}

/// One model-proposal + user-decision pair from session-end entity resolution.
/// The learning signal + eval set for the trust ladder.
@available(macOS 14, *)
@Model
final class Judgment {
    var id: UUID = UUID()
    var at: Date
    var captureRangeStart: Date
    var captureRangeEnd: Date
    var modelProposal: String   // JSON
    var userDecision: String    // "accepted" | "rejected" | "edited"
    init(at: Date, captureRangeStart: Date, captureRangeEnd: Date,
         modelProposal: String, userDecision: String) {
        self.at = at; self.captureRangeStart = captureRangeStart
        self.captureRangeEnd = captureRangeEnd
        self.modelProposal = modelProposal; self.userDecision = userDecision
    }
}
