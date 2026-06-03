@testable import AccountaBall

func runOpenRouterPromptTests() {
    suite("OpenRouterPromptTests") {
        let tasks = [TaskItem(task: "Write proposal", context: "Q3"),
                     TaskItem(task: "Review slides", context: "deck")]
        let p = OpenRouterAIService.buildClassifyPrompt(tasks: tasks, screenText: "doc",
                    allowanceRulesByIndex: [1: ["watching tutorials"]])
        expect(p.contains("[0] Write proposal"), "lists task 0")
        expect(p.contains("Allowances"), "includes allowance section when present")
        expect(p.contains("Task 1: watching tutorials"), "allowance scoped to task index")

        let p2 = OpenRouterAIService.buildClassifyPrompt(tasks: tasks, screenText: "doc", allowanceRulesByIndex: [:])
        expect(!p2.contains("Allowances"), "omits allowance section when none")
    }
}
