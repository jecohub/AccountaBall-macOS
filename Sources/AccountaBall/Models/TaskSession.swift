import Foundation

struct TaskSession: Codable, Equatable {
    let task: String
    let startedAt: Date
    let completedAt: Date

    var duration: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }
}
