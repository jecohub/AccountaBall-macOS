import Foundation
@testable import AccountaBall

func runFreeBallMarkdownTests() {
    suite("FreeBallMarkdown") {
        let r = FreeBallRecap(date: Date(timeIntervalSince1970: 0), duration: 600,
            narrative: "Mostly coded.", categories: [CategorySpan(label: "Coding", minutes: 10)],
            insight: "Long blocks.", workingOn: ["refactor timeout"], people: ["Sarah (Slack)"],
            codeContext: ["OllamaAIService.swift"], openThreads: ["reply to Sarah"], recapPending: false)
        let md = FreeBallMarkdown.render(recap: r)
        expect(md.contains("# FreeBall"), "has a title")
        expect(md.contains("Mostly coded."), "narrative present")
        expect(md.contains("## Working on"), "working on section")
        expect(md.contains("refactor timeout"), "working on item")
        expect(md.contains("## Open threads"), "open threads section")
        expect(md.contains("reply to Sarah"), "thread item")

        let empty = FreeBallRecap(date: Date(timeIntervalSince1970: 0), duration: 0, narrative: "",
            categories: [], insight: "", workingOn: [], people: [], codeContext: [], openThreads: [], recapPending: false)
        expect(!FreeBallMarkdown.render(recap: empty).contains("## Working on"), "empty section omitted")
    }
}
