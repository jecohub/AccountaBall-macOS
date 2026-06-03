struct KnowledgeTaskSnapshot: Sendable {
    let normalizedTitle: String
    let summaryOfLatest: String
    let activeAllowanceRules: [String]   // confirmed only

    init(_ kt: KnowledgeTask) {
        normalizedTitle = kt.normalizedTitle
        summaryOfLatest = kt.completions.sorted { $0.completedAt > $1.completedAt }.first?.summary ?? ""
        activeAllowanceRules = kt.allowances.filter { !$0.needsConfirmation }.map { $0.rule }
    }
}
