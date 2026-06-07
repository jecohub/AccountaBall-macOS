import SwiftData
@testable import AccountaBall

@MainActor
func runPersistenceTests() {
    suite("PersistenceTests") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let kt = KnowledgeTask(normalizedTitle: "write proposal", lastCompletedAt: .now)
        kt.allowances.append(Allowance(rule: "react tutorials", createdAt: .now))
        kt.completions.append(TaskCompletion(completedAt: .now, duration: 600, summary: "s", steps: ["a"], offTaskCount: 1))
        ctx.insert(kt)
        try? ctx.save()

        let fetched = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>())) ?? []
        expect(fetched.count == 1, "one knowledge task persisted")
        expect(fetched.first?.allowances.count == 1, "allowance related")
        expect(fetched.first?.completions.first?.steps == ["a"], "completion steps round-trip")

        let ev = JustificationEvent(at: .now, excuse: "x", justified: false,
            inferredTaskIndex: nil, activity: "Twitter", rule: "social", kind: "offtask")
        ctx.insert(ev)
        do { try ctx.save() } catch { expect(false, "save justification event") }

        let events = (try? ctx.fetch(FetchDescriptor<JustificationEvent>())) ?? []
        expect(events.count == 1, "one justification event persisted")
        expect(events.first?.kind == "offtask", "JustificationEvent persists kind")
    }
}
