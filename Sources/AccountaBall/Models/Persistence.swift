import SwiftData
import Foundation

@available(macOS 14, *)
@Model
final class WorkSession {
    var startedAt: Date
    var endedAt: Date?
    @Relationship(deleteRule: .cascade) var entries: [TimelineEntry] = []
    @Relationship(deleteRule: .cascade) var justifications: [JustificationEvent] = []
    var taskTitles: [String] = []        // snapshot of what was declared
    init(startedAt: Date) { self.startedAt = startedAt }
}

@available(macOS 14, *)
@Model
final class TimelineEntry {       // one per 5s cycle
    var at: Date
    var taskIndex: Int?            // nil = off-task
    var label: String              // AI's 3-5 word activity label
    init(at: Date, taskIndex: Int?, label: String) {
        self.at = at; self.taskIndex = taskIndex; self.label = label
    }
}

@available(macOS 14, *)
@Model
final class JustificationEvent {  // one per off-task interrogation
    var at: Date
    var excuse: String             // what the user typed
    var justified: Bool
    var inferredTaskIndex: Int?    // which task it was judged against
    var activity: String           // AI's short description of the activity
    var rule: String = ""          // the model's reason for the verdict (the "why")
    init(at: Date, excuse: String, justified: Bool, inferredTaskIndex: Int?, activity: String, rule: String = "") {
        self.at = at; self.excuse = excuse; self.justified = justified
        self.inferredTaskIndex = inferredTaskIndex; self.activity = activity; self.rule = rule
    }
}

@available(macOS 14, *)
@Model
final class KnowledgeTask {        // persists across sessions
    @Attribute(.unique) var normalizedTitle: String
    var id: UUID = UUID()           // stable id for cross-session links
    var originalTitles: [String] = []     // every phrasing the user has used
    var lastCompletedAt: Date
    var timesCompleted: Int = 0
    @Relationship(deleteRule: .cascade) var allowances: [Allowance] = []
    @Relationship(deleteRule: .cascade) var completions: [TaskCompletion] = []
    init(normalizedTitle: String, lastCompletedAt: Date) {
        self.normalizedTitle = normalizedTitle
        self.lastCompletedAt = lastCompletedAt
    }
}

@available(macOS 14, *)
@Model
final class Allowance {
    var rule: String                      // AI-written, e.g. "watching React tutorials on YouTube"
    var createdAt: Date
    var needsConfirmation: Bool = false   // true when revived in a new session
    init(rule: String, createdAt: Date, needsConfirmation: Bool = false) {
        self.rule = rule
        self.createdAt = createdAt
        self.needsConfirmation = needsConfirmation
    }
}

@available(macOS 14, *)
@Model
final class TaskCompletion {       // one record per finished run
    var completedAt: Date
    var duration: TimeInterval      // total time on this task that session
    var summary: String
    var steps: [String]
    var offTaskCount: Int           // times flagged that run (feeds the "why")
    init(completedAt: Date, duration: TimeInterval, summary: String, steps: [String], offTaskCount: Int) {
        self.completedAt = completedAt
        self.duration = duration
        self.summary = summary
        self.steps = steps
        self.offTaskCount = offTaskCount
    }
}

@available(macOS 14, *)
enum AccountaBallStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([WorkSession.self, TimelineEntry.self, JustificationEvent.self,
                             KnowledgeTask.self, Allowance.self, TaskCompletion.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
