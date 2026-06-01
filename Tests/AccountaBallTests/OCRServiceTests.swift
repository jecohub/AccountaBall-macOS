@testable import AccountaBall

func runOCRServiceTests() {
    suite("OCRServiceTests") {
        let service = OCRService()

        let filtered = service.filterText(["a", "is", "Hello", "World", "OK", "do"])
        expect(filtered == ["Hello", "World"], "filters strings under 3 chars")

        let empty = service.filterText([])
        expect(empty.isEmpty, "empty input returns empty")

        let joined = service.joinedText(["Hello", "World"])
        expect(joined == "Hello\nWorld", "joins with newlines")
    }
}
