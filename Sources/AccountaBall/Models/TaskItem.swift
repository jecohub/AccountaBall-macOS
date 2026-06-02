import Foundation

struct TaskItem: Codable, Identifiable, Equatable {
    let id: UUID
    var task: String
    var context: String
    var isComplete: Bool
    var timeOnTask: TimeInterval

    init(task: String = "", context: String = "", isComplete: Bool = false, timeOnTask: TimeInterval = 0) {
        self.id = UUID()
        self.task = task
        self.context = context
        self.isComplete = isComplete
        self.timeOnTask = timeOnTask
    }

    var isFilledIn: Bool {
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
