import Foundation

struct ExcuseVerdict: Equatable {
    let justified: Bool
    let taskIndex: Int?
    let rule: String

    /// Accepts "VERDICT | taskIndex | rule". Reject NOT before matching JUSTIFIED.
    static func parse(_ raw: String) -> ExcuseVerdict {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let verdict = (parts.first ?? "").uppercased()
        let justified = !verdict.contains("NOT") && verdict.contains("JUSTIFIED")
        let taskIndex = parts.count > 1 ? Int(parts[1]) : nil
        let rule = parts.count > 2 ? parts[2] : ""
        return ExcuseVerdict(justified: justified, taskIndex: justified ? taskIndex : nil, rule: justified ? rule : "")
    }
}
