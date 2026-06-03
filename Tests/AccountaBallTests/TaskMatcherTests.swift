@testable import AccountaBall

func runTaskMatcherTests() {
    suite("TaskMatcherTests") {
        expect(TaskMatcher.normalize("  Write the Q3 Proposal!! ") == "write the q3 proposal",
               "lowercases, trims, strips trailing punctuation, collapses spaces")
        // cheap match: exact normalized title
        let candidates = [(id: "A", normalized: "write proposal", originals: ["Write proposal"]),
                          (id: "B", normalized: "review slides", originals: ["Review slides"])]
        expect(TaskMatcher.cheapMatch("write proposal", in: candidates) == "A", "exact normalized hit")
        // cheap match via a prior original phrasing (normalized)
        expect(TaskMatcher.cheapMatch("review slides", in: candidates) == "B", "matches by normalized original")
        expect(TaskMatcher.cheapMatch("unrelated thing", in: candidates) == nil, "no cheap hit returns nil")
    }
}
