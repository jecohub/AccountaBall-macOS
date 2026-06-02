enum MultiTaskResult: Equatable {
    case onTask(index: Int)
    case offTask
    case done(index: Int)

    static func parse(_ raw: String) -> MultiTaskResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned == "OFFTASK" { return .offTask }
        if cleaned.hasPrefix("TASK:"), let idx = Int(cleaned.dropFirst(5)) {
            return .onTask(index: idx)
        }
        if cleaned.hasPrefix("DONE:"), let idx = Int(cleaned.dropFirst(5)) {
            return .done(index: idx)
        }
        return .offTask
    }
}
