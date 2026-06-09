import SwiftData
@testable import AccountaBall

@MainActor
func runFreeBallPersistenceTests() {
    suite("FreeBallPersistence") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let session = FreeBallSession(startedAt: .now)
        session.cycleCount = 12
        session.narrative = "Mostly coding."
        session.categories = [CategorySpan(label: "Coding", minutes: 45),
                              CategorySpan(label: "Email", minutes: 10)]
        session.insight = "You code in long blocks."
        let cap = FreeBallCapture(firstSeenAt: .now, lastSeenAt: .now, text: "hello world")
        session.captures.append(cap)
        ctx.insert(session)
        try? ctx.save()

        let fetched = (try? ctx.fetch(FetchDescriptor<FreeBallSession>())) ?? []
        expect(fetched.count == 1, "one FreeBallSession persisted")
        expect(fetched.first?.captures.count == 1, "capture related")
        expect(fetched.first?.categories.count == 2, "categories round-trip")
        expect(fetched.first?.categories.first?.label == "Coding", "category label round-trip")
        expect(fetched.first?.narrative == "Mostly coding.", "narrative round-trip")
    }
}
