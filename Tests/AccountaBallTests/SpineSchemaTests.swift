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
        expect(projects.first?.threads.count == 1, "thread persisted via relationship")
        expect(projects.first?.status == "active", "default status active")
        expect(projects.first?.threads.first?.status == "open", "default thread status open")

        ctx.delete(project)
        try? ctx.save()
        expect(((try? ctx.fetch(FetchDescriptor<Project>())) ?? []).isEmpty, "project deleted")
        expect(((try? ctx.fetch(FetchDescriptor<AccountaBall.Thread>())) ?? []).isEmpty, "cascade removed orphaned thread")

        let pid = UUID(); let tid = UUID(); let sid2 = UUID()
        let contrib = Contribution(at: .now, projectId: pid, threadId: tid,
                                   sessionId: sid2, sessionKind: "task", minutes: 25,
                                   summary: "Reshaped the confirm card")
        let r0 = Date()
        let judgment = Judgment(at: .now, captureRangeStart: r0, captureRangeEnd: r0,
                                modelProposal: "{\"project\":\"Windows port\"}",
                                userDecision: "accepted")
        ctx.insert(contrib); ctx.insert(judgment)
        try? ctx.save()
        let contribs = (try? ctx.fetch(FetchDescriptor<Contribution>())) ?? []
        expect(contribs.first?.minutes == 25, "contribution minutes round-trip")
        expect(contribs.first?.projectId == pid, "contribution projectId round-trip")
        expect(contribs.first?.threadId == tid, "contribution threadId round-trip")
        expect(contribs.first?.sessionKind == "task", "contribution sessionKind round-trip")
        let judgments = (try? ctx.fetch(FetchDescriptor<Judgment>())) ?? []
        expect(judgments.first?.userDecision == "accepted", "judgment decision round-trip")
        expect(judgments.first?.modelProposal.contains("Windows port") == true, "judgment proposal round-trip")
        expect(judgments.first?.captureRangeStart == r0, "judgment captureRangeStart round-trip")
    }
}
