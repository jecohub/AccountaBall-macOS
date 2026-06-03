@testable import AccountaBall
import SwiftData

@MainActor
func runSnapshotTests() {
    suite("SnapshotTests") {
        let kt = KnowledgeTask(normalizedTitle: "t", lastCompletedAt: .now)
        kt.allowances = [Allowance(rule: "ok", createdAt: .now),                       // active
                         Allowance(rule: "pending", createdAt: .now, needsConfirmation: true)] // not yet active
        let snap = KnowledgeTaskSnapshot(kt)
        expect(snap.normalizedTitle == "t", "title copied")
        expect(snap.activeAllowanceRules == ["ok"], "only confirmed allowances are active")
    }
}
