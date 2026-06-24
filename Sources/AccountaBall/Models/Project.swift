import SwiftData
import Foundation

/// Spine entities. A `Project` is a long-lived workstream; a `Thread` is an open
/// loop owned by a project (via cascade). These are part of the
/// Project→Thread→Contribution→Capture context spine.
@available(macOS 14, *)
@Model
final class Project {
    var id: UUID = UUID()
    var title: String
    var aliases: [String] = []
    var status: String = "active"          // active | dormant | done
    var createdAt: Date = Date()
    var lastTouchedAt: Date = Date()
    var summary: String = ""
    var people: [String] = []
    var codeContext: [String] = []
    var refs: [String] = []
    @Relationship(deleteRule: .cascade) var threads: [Thread] = []
    init(title: String) { self.title = title }
}

/// Note: shadows Foundation.Thread; this module never references the latter.
@available(macOS 14, *)
@Model
final class Thread {
    var id: UUID = UUID()
    var title: String
    var status: String = "open"            // open | resolved
    var openedAt: Date = Date()
    var resolvedAt: Date? = nil
    init(title: String) { self.title = title }
}
