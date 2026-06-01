@testable import AccountaBall

func runClaudeAIServiceTests() {
    suite("ClaudeAIServiceTests") {
        expect(ClaudeAIService.parseResponse("ONTASK") == .onTask,  "parses ONTASK")
        expect(ClaudeAIService.parseResponse("OFFTASK") == .offTask, "parses OFFTASK")
        expect(ClaudeAIService.parseResponse("DONE") == .done,      "parses DONE")
        expect(ClaudeAIService.parseResponse("  ONTASK\n") == .onTask, "trims whitespace")
        expect(ClaudeAIService.parseResponse("I'm not sure") == .onTask, "unknown defaults to onTask")
        expect(ClaudeAIService.parseResponse("") == .onTask, "empty defaults to onTask")
    }
}
