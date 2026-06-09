@testable import AccountaBall

func runFreeBallSummarizeTests() {
    suite("FreeBallSummarize_parse") {
        let json = #"{"narrative":"You mostly coded.","categories":[{"label":"Coding","minutes":45},{"label":"Email","minutes":10}],"insight":"You code in long blocks."}"#
        let out = AIPrompts.parseFreeBallSummary(json)
        expect(out.narrative == "You mostly coded.", "narrative parsed")
        expect(out.categories.count == 2, "two categories")
        expect(out.categories.first?.label == "Coding", "first label")
        expect(out.categories.first?.minutes == 45, "first minutes")
        expect(out.insight == "You code in long blocks.", "insight parsed")
    }

    suite("FreeBallSummarize_parse_badJSON") {
        let out = AIPrompts.parseFreeBallSummary("not json")
        expect(out.narrative.isEmpty, "bad json -> empty narrative")
        expect(out.categories.isEmpty, "bad json -> empty categories")
    }

    suite("FreeBallSummarize_prompt") {
        let transcript = [FreeBallTranscriptEntry(text: "editing main.swift", seconds: 120)]
        let past = [FreeBallPastRecap(narrative: "Lots of email.", categories: [CategorySpan(label: "Email", minutes: 30)], insight: "Mornings are emaily.")]
        let prompt = AIPrompts.buildFreeBallPrompt(transcript: transcript, pastRecaps: past)
        expect(prompt.contains("editing main.swift"), "transcript text included")
        expect(prompt.contains("Lots of email."), "past recap included")
    }
}
