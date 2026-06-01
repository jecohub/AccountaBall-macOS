import Foundation
@testable import AccountaBall

func runTaskSessionTests() {
    suite("TaskSessionTests") {
        let start = Date()
        let end = start.addingTimeInterval(300)
        let session = TaskSession(task: "write proposal", startedAt: start, completedAt: end)
        expect(abs(session.duration - 300) < 0.001, "duration calculates correctly")

        let start2 = Date(timeIntervalSince1970: 1000)
        let end2 = Date(timeIntervalSince1970: 1300)
        let s2 = TaskSession(task: "write tests", startedAt: start2, completedAt: end2)
        if let data = try? JSONEncoder().encode(s2),
           let decoded = try? JSONDecoder().decode(TaskSession.self, from: data) {
            expect(decoded.task == "write tests", "codable roundtrip preserves task")
            expect(abs(decoded.duration - 300) < 0.001, "codable roundtrip preserves duration")
        } else {
            expect(false, "codable roundtrip succeeded")
        }
    }
}
