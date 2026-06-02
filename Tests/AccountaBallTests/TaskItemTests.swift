import Foundation
@testable import AccountaBall

func runTaskItemTests() {
    suite("TaskItemTests") {
        let item = TaskItem(task: "write proposal", context: "for client meeting")
        expect(item.task == "write proposal", "task stored correctly")
        expect(item.context == "for client meeting", "context stored correctly")
        expect(item.isComplete == false, "starts incomplete")
        expect(item.timeOnTask == 0, "starts with zero time")

        // Codable roundtrip
        if let data = try? JSONEncoder().encode(item),
           let decoded = try? JSONDecoder().decode(TaskItem.self, from: data) {
            expect(decoded.task == item.task, "codable roundtrip preserves task")
            expect(decoded.id == item.id, "codable roundtrip preserves id")
            expect(decoded.isComplete == false, "codable roundtrip preserves isComplete")
            expect(decoded.context == item.context, "codable roundtrip preserves context")
            expect(decoded.timeOnTask == item.timeOnTask, "codable roundtrip preserves timeOnTask")
        } else {
            expect(false, "codable roundtrip failed — encode/decode error")
        }

        // Empty item
        let empty = TaskItem()
        expect(empty.task == "", "empty item has blank task")
        expect(empty.context == "", "empty item has blank context")

        // isFilledIn
        expect(!empty.isFilledIn, "empty item is not filled in")
        expect(item.isFilledIn, "item with task+context is filled in")

        // Whitespace-only is not filled in
        let ws = TaskItem(task: "  ", context: "\t")
        expect(!ws.isFilledIn, "whitespace-only item is not filled in")
    }
}
