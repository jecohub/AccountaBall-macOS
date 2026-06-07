@testable import AccountaBall

func runMultiTaskResultTests() {
    suite("MultiTaskResultTests") {
        expect(MultiTaskResult.parse("TASK:0 | editing AppDelegate") == .onTask(index: 0, label: "editing AppDelegate"), "parses TASK with label")
        expect(MultiTaskResult.parse("OFFTASK | browsing twitter") == .offTask(label: "browsing twitter"), "parses OFFTASK with label")
        expect(MultiTaskResult.parse("AMBIGUOUS | reading a Stripe pricing page") == .ambiguous(label: "reading a Stripe pricing page"), "AMBIGUOUS parses with label")
        expect(MultiTaskResult.parse("AMBIGUOUS") == .ambiguous(label: ""), "AMBIGUOUS parses without label")
        expect(MultiTaskResult.parse("ambiguous | x") == .ambiguous(label: "x"), "AMBIGUOUS is case-insensitive on the keyword")
        expect(MultiTaskResult.parse("DONE:2 | proposal finalized") == .done(index: 2, label: "proposal finalized"), "parses DONE with label")
        expect(MultiTaskResult.parse("TASK:3") == .onTask(index: 3, label: ""), "missing label defaults to empty")
        expect(MultiTaskResult.parse("  task:1 | Foo \n") == .onTask(index: 1, label: "Foo"), "trims + lowercases keyword, preserves label case")
        expect(MultiTaskResult.parse("garbage") == .offTask(label: ""), "unknown defaults to offTask")
        expect(MultiTaskResult.parse("") == .offTask(label: ""), "empty defaults to offTask")
        expect(MultiTaskResult.onTask(index: 0, label: "a") != MultiTaskResult.onTask(index: 1, label: "a"), "different indices differ")
        expect(MultiTaskResult.onTask(index: 0, label: "a") != MultiTaskResult.onTask(index: 0, label: "b"), "different labels differ")
        expect(MultiTaskResult.done(index: 0, label: "x") != .offTask(label: "x"), "done != offTask")
    }
}
