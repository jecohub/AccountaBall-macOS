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
        let t0 = Date()
        let t1 = t0.addingTimeInterval(30)
        let cap = Capture(firstSeenAt: t0, lastSeenAt: t1, text: "hello",
                          mode: "task", appHint: "Xcode", taskIndex: 0, sessionId: sid)
        ctx.insert(cap)
        try? ctx.save()
        let fetched = (try? ctx.fetch(FetchDescriptor<Capture>())) ?? []
        expect(fetched.count == 1, "one Capture persisted")
        expect(fetched.first?.mode == "task", "mode round-trips")
        expect(fetched.first?.taskIndex == 0, "taskIndex round-trips")
        expect(fetched.first?.sessionId == sid, "sessionId round-trips")
        expect(fetched.first?.text == "hello", "text round-trips")
        expect(fetched.first?.appHint == "Xcode", "appHint round-trips")
        expect(fetched.first?.seconds == 30, "seconds computed after fetch")

        let project = Project(title: "Windows port")
        let thread = Thread(title: "fix panel sizing")
        project.threads.append(thread)
        ctx.insert(project)
        try? ctx.save()
        let projects = (try? ctx.fetch(FetchDescriptor<Project>())) ?? []
        expect(projects.count == 1, "one Project persisted")
        expect(projects.first?.threads.count == 1, "thread related via cascade")
        expect(projects.first?.status == "active", "default status active")
        expect(projects.first?.threads.first?.status == "open", "default thread status open")
    }
}
