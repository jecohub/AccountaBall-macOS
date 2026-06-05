@testable import AccountaBall
import Foundation

func runOllamaServiceTests() {
    suite("OllamaServiceTests") {
        let body = OllamaAIService.chatBody(model: "qwen2.5:7b", system: "S", user: "U", jsonSchema: ["type": "object"])
        expect(body["model"] as? String == "qwen2.5:7b", "model set")
        expect(body["stream"] as? Bool == false, "non-streaming")
        expect(body["format"] != nil, "format schema attached")
        let msgs = body["messages"] as? [[String: String]]
        expect(msgs?.first?["role"] == "system", "system message first")
        expect(msgs?.last?["content"] == "U", "user content last")
        // Deterministic decoding: Ollama defaults to temperature 0.8, which made
        // classification flip-flop (same screen scored on-task one cycle, off-task
        // the next), resetting the off-task suspicion counter so real off-task work
        // was never caught. Pin temperature to 0 for stable, repeatable verdicts.
        let opts = body["options"] as? [String: Any]
        expect(opts?["temperature"] as? Double == 0, "deterministic temperature 0")
    }
}
