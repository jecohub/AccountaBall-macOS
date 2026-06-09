@testable import AccountaBall

func runFreeBallSummarizeTests() {
    suite("FreeBallSummarize_parse") {
        let json = #"{"narrative":"You mostly coded.","categories":[{"label":"Coding","minutes":45},{"label":"Email","minutes":10}],"insight":"You code in long blocks.","workingOn":["refactoring the timeout handling"],"people":["Sarah (Slack) — launch Friday"],"codeContext":["OllamaAIService.swift"],"openThreads":["reply to Sarah"]}"#
        let out = AIPrompts.parseFreeBallSummary(json)
        expect(out.narrative == "You mostly coded.", "narrative parsed")
        expect(out.categories.count == 2, "two categories")
        expect(out.categories.first?.label == "Coding", "first label")
        expect(out.categories.first?.minutes == 45, "first minutes")
        expect(out.insight == "You code in long blocks.", "insight parsed")
        expect(out.workingOn == ["refactoring the timeout handling"], "workingOn parsed")
        expect(out.people.first == "Sarah (Slack) — launch Friday", "people parsed")
        expect(out.codeContext == ["OllamaAIService.swift"], "codeContext parsed")
        expect(out.openThreads == ["reply to Sarah"], "openThreads parsed")
    }

    suite("FreeBallSummarize_parse_badJSON") {
        let out = AIPrompts.parseFreeBallSummary("not json")
        expect(out.narrative.isEmpty, "bad json -> empty narrative")
        expect(out.categories.isEmpty, "bad json -> empty categories")
        expect(out.workingOn.isEmpty, "bad json -> empty workingOn")
    }

    suite("FreeBallSummarize_prompt") {
        let transcript = [FreeBallTranscriptEntry(text: "editing main.swift", seconds: 120)]
        let past = [FreeBallPastRecap(narrative: "Lots of email.", categories: [CategorySpan(label: "Email", minutes: 30)], insight: "Mornings are emaily.", openThreads: [])]
        let prompt = AIPrompts.buildFreeBallPrompt(transcript: transcript, pastRecaps: past)
        expect(prompt.contains("editing main.swift"), "transcript text included")
        expect(prompt.contains("Lots of email."), "past recap included")
    }
}
