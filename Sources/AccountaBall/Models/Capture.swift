import SwiftData
import Foundation

/// One screen read, shared by both modes. Task mode no longer discards OCR;
/// FreeBall continues to keep full text. De-dup collapses unchanged screens into
/// a firstSeenAt…lastSeenAt span.
@available(macOS 14, *)
@Model
final class Capture {
    var id: UUID = UUID()
    var firstSeenAt: Date
    var lastSeenAt: Date
    var text: String
    var mode: String          // "task" | "free"
    var appHint: String?
    var taskIndex: Int?
    /// Deliberate soft foreign key (not a SwiftData `@Relationship`): a Capture may belong to
    /// either a WorkSession or a FreeBallSession, and a typed relationship can't reference two model types.
    var sessionId: UUID
    init(firstSeenAt: Date, lastSeenAt: Date, text: String, mode: String,
         appHint: String? = nil, taskIndex: Int? = nil, sessionId: UUID) {
        self.firstSeenAt = firstSeenAt; self.lastSeenAt = lastSeenAt
        self.text = text; self.mode = mode; self.appHint = appHint
        self.taskIndex = taskIndex; self.sessionId = sessionId
    }
    var seconds: TimeInterval { lastSeenAt.timeIntervalSince(firstSeenAt) }
}
