import Foundation
import SwiftData
@testable import AccountaBall

@MainActor
func runSpineSchemaTests() {
    suite("SpineSchema") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let sid = UUID()
        let cap = Capture(firstSeenAt: .now, lastSeenAt: .now, text: "hello",
                          mode: "task", appHint: "Xcode", taskIndex: 0, sessionId: sid)
        ctx.insert(cap)
        try? ctx.save()
        let fetched = (try? ctx.fetch(FetchDescriptor<Capture>())) ?? []
        expect(fetched.count == 1, "one Capture persisted")
        expect(fetched.first?.mode == "task", "mode round-trips")
        expect(fetched.first?.taskIndex == 0, "taskIndex round-trips")
        expect(fetched.first?.sessionId == sid, "sessionId round-trips")
    }
}
