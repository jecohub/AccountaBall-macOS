@testable import AccountaBall

func runSummarizeSessionParseTests() {
    suite("SummarizeSessionParse") {
        let json = #"{"tasks":[{"title":"Write proposal","comment":"Faster than last time.","suggestion":"Snooze Slack."},{"title":"Review","comment":"Mostly browsing.","suggestion":""}]}"#
        let out = AIPrompts.parseSessionComments(json, titles: ["Write proposal", "Review"])
        expect(out.count == 2, "two comments parsed")
        expect(out[0].taskTitle == "Write proposal", "first title")
        expect(out[0].comment == "Faster than last time.", "first comment")
        expect(out[0].suggestion == "Snooze Slack.", "first suggestion kept")
        expect(out[1].taskTitle == "Review", "second title")
        expect(out[1].comment == "Mostly browsing.", "second comment")
        expect(out[1].suggestion == nil, "empty suggestion -> nil")
    }

    suite("SummarizeSessionParse_badJSON") {
        let out = AIPrompts.parseSessionComments("not json", titles: ["a"])
        expect(out.isEmpty, "bad json returns empty")
    }

    suite("SummarizeSessionParse_missingSuggestion") {
        let json = #"{"tasks":[{"title":"Test","comment":"Some comment."}]}"#
        let out = AIPrompts.parseSessionComments(json, titles: ["Test"])
        expect(out.count == 1, "one comment without suggestion")
        expect(out[0].suggestion == nil, "missing suggestion -> nil")
    }
}
