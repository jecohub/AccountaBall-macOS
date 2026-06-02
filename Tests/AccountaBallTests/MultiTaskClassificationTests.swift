@testable import AccountaBall

func runMultiTaskClassificationTests() {
    suite("MultiTaskClassificationTests") {
        let tasks = [
            TaskItem(task: "write proposal", context: "for client meeting friday"),
            TaskItem(task: "review slides", context: "deck for monday presentation")
        ]

        // Test the static prompt builder — no network needed
        let prompt = OpenRouterAIService.buildClassifyPrompt(tasks: tasks, screenText: "Google Docs open")
        expect(prompt.contains("TASK 0"), "prompt includes TASK 0 header")
        expect(prompt.contains("write proposal"), "prompt includes task 0 name")
        expect(prompt.contains("for client meeting friday"), "prompt includes task 0 context")
        expect(prompt.contains("TASK 1"), "prompt includes TASK 1 header")
        expect(prompt.contains("review slides"), "prompt includes task 1 name")
        expect(prompt.contains("Google Docs open"), "prompt includes screen text")

        // Parser already tested in MultiTaskResultTests — just verify the round-trip label
        expect(MultiTaskResult.parse("TASK:0") == .onTask(index: 0), "TASK:0 parses to onTask(0)")
        expect(MultiTaskResult.parse("OFFTASK") == .offTask, "OFFTASK parses correctly")
        expect(MultiTaskResult.parse("DONE:1") == .done(index: 1), "DONE:1 parses correctly")
    }
}
