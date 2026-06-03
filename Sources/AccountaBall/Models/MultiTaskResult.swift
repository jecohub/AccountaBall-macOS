enum MultiTaskResult: Equatable {
    case onTask(index: Int, label: String)
    case offTask(label: String)
    case done(index: Int, label: String)

    /// Accepts "RESULT | label". Label is optional. Keyword is case-insensitive;
    /// label case is preserved.
    static func parse(_ raw: String) -> MultiTaskResult {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let keyword = parts.first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() } ?? ""
        let label = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if keyword == "OFFTASK" { return .offTask(label: label) }
        if keyword.hasPrefix("TASK:"), let idx = Int(keyword.dropFirst(5)) { return .onTask(index: idx, label: label) }
        if keyword.hasPrefix("DONE:"), let idx = Int(keyword.dropFirst(5)) { return .done(index: idx, label: label) }
        return .offTask(label: label)
    }
}
