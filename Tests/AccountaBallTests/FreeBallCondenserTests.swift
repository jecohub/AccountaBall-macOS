@testable import AccountaBall

func runFreeBallCondenserTests() {
    suite("FreeBallCondenser") {
        let long = String(repeating: "x", count: 500)
        let short = String(repeating: "y", count: 500)
        let entries = [
            FreeBallTranscriptEntry(text: long, seconds: 600),   // long-lived
            FreeBallTranscriptEntry(text: short, seconds: 30)    // brief blip
        ]
        let out = FreeBallCondenser.condense(entries, maxChars: 300)
        let total = out.reduce(0) { $0 + $1.text.count }
        expect(total <= 300, "total trimmed under budget")
        expect(out.count == 2, "entries preserved in order")
        expect(out[0].text.count > out[1].text.count, "longer-lived screen kept fuller")

        let small = [FreeBallTranscriptEntry(text: "hi", seconds: 10)]
        expect(FreeBallCondenser.condense(small, maxChars: 1000) == small, "under budget = unchanged")
    }
}
