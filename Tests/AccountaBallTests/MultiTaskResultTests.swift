@testable import AccountaBall

func runMultiTaskResultTests() {
    suite("MultiTaskResultTests") {
        expect(MultiTaskResult.parse("TASK:0") == .onTask(index: 0), "parses TASK:0")
        expect(MultiTaskResult.parse("TASK:3") == .onTask(index: 3), "parses TASK:3")
        expect(MultiTaskResult.parse("OFFTASK") == .offTask, "parses OFFTASK")
        expect(MultiTaskResult.parse("DONE:2") == .done(index: 2), "parses DONE:2")
        expect(MultiTaskResult.parse("  task:1\n") == .onTask(index: 1), "trims whitespace and lowercases")
        expect(MultiTaskResult.parse("  done:1\n") == .done(index: 1), "trims whitespace for DONE branch")
        expect(MultiTaskResult.parse("garbage") == .offTask, "unknown defaults to offTask")
        expect(MultiTaskResult.parse("") == .offTask, "empty defaults to offTask")
        expect(MultiTaskResult.parse("JUSTIFIED") == .offTask, "non-result defaults to offTask")

        // Distinctness
        expect(MultiTaskResult.onTask(index: 0) != MultiTaskResult.onTask(index: 1), "different indices are not equal")
        expect(MultiTaskResult.onTask(index: 0) != .offTask, "onTask != offTask")
        expect(MultiTaskResult.done(index: 0) != .offTask, "done != offTask")
        expect(MultiTaskResult.done(index: 0) != MultiTaskResult.done(index: 1), "different done indices are not equal")
    }
}
