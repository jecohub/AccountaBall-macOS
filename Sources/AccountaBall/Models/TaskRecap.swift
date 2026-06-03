import Foundation
struct TaskRecap: Equatable {
    let summary: String
    let steps: [String]
    let duration: TimeInterval
    let comparison: String?   // nil on first completion
}
