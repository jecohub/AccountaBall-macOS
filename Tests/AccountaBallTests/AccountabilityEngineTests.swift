import Foundation
import SwiftData
@testable import AccountaBall

/// Mutable clock holder so a `now` closure can read an updatable time from
/// inside nested test scopes (the engine captures the Box, the test mutates it).
private final class Box {
    var now = Date()
}

private class MultiMockAI: AIService {
    var nextResult: MultiTaskResult = .offTask(label: "")
    func classify(task: String, screenText: String) async throws -> BallState { .onTask }
    func classifyMulti(tasks: [TaskItem], screenText: String, allowanceRulesByIndex: [Int: [String]]) async throws -> MultiTaskResult { nextResult }
    func evaluateExcuse(excuse: String, tasks: [TaskItem], screenText: String) async throws -> ExcuseVerdict { ExcuseVerdict(justified: true, taskIndex: nil, rule: "") }
    func summarizeTask(title: String, context: String, steps: [String], durationSeconds: TimeInterval, previous: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)?) async throws -> TaskRecap { TaskRecap(summary: "", steps: [], duration: durationSeconds, comparison: nil) }
    func matchTask(query: String, candidates: [(id: String, title: String, summary: String)]) async throws -> (id: String, confident: Bool)? { nil }
    func healthCheck() async -> Bool { true }
    func summarizeSession(perTask: [PerTaskSessionInput]) async throws -> [PerTaskComment] { [] }
    func summarizeFreeBall(transcript: [FreeBallTranscriptEntry], pastRecaps: [FreeBallPastRecap]) async throws -> FreeBallSummary { FreeBallSummary(narrative: "", categories: [], insight: "", workingOn: [], people: [], codeContext: [], openThreads: []) }
}

@MainActor
func runAccountabilityEngineTests() {
    let capture = ScreenCaptureService()
    let ocr = OCRService()
    let notif = NotificationService()

    func make() -> (AppState, AccountabilityEngine) {
        let s = AppState()
        s.tasks = [
            TaskItem(task: "write proposal", context: "for client"),
            TaskItem(task: "review slides",  context: "deck")
        ]
        s.startSession()
        let e = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        return (s, e)
    }

    suite("AccountabilityEngineTests") {
        var (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .onTask, "single offTask does not flip state")
        expect(state.appPhase == .session, "single offTask does not change phase")

        (state, engine) = make()
        let box1 = Box()
        engine.now = { box1.now }
        engine.processResult(.offTask(label: ""))
        box1.now = box1.now.addingTimeInterval(16)   // hold the SAME off-task screen ≥15s
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .offTask, "two consecutive offTask flips to offTask")
        expect(state.appPhase == .offTask, "two consecutive offTask sets offTask phase")

        (state, engine) = make()
        engine.processResult(.offTask(label: ""))
        engine.processResult(.onTask(index: 0, label: ""))
        engine.processResult(.offTask(label: ""))
        expect(state.ballState == .onTask, "onTask in between resets suspicion")

        (state, engine) = make()
        engine.processResult(.onTask(index: 1, label: ""))
        expect(state.activeTaskIndex == 1, "onTask sets activeTaskIndex")
        expect(state.ballState == .onTask, "onTask sets ballState to onTask")

        (state, engine) = make()
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.tasks[0].timeOnTask == AppConstants.cycleSeconds, "onTask accumulates one cycle of time")
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.tasks[0].timeOnTask == AppConstants.cycleSeconds * 2, "second onTask accumulates another cycle")

        (state, engine) = make()
        engine.processResult(.onTask(index: 1, label: ""))
        expect(state.tasks[1].timeOnTask == AppConstants.cycleSeconds, "onTask on task 1 accumulates time on task 1")
        expect(state.tasks[0].timeOnTask == 0, "task 0 not affected")

        (state, engine) = make()
        engine.processResult(.done(index: 0, label: ""))
        expect(state.tasks[0].isComplete == true, "done marks task complete")

        (state, engine) = make()
        engine.processResult(.done(index: 0, label: ""))
        engine.processResult(.done(index: 1, label: ""))
        expect(state.appPhase == .complete, "all done triggers complete phase")

        (state, engine) = make()
        let box2 = Box()
        engine.now = { box2.now }
        engine.processResult(.offTask(label: ""))
        box2.now = box2.now.addingTimeInterval(16)
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .offTask, "two offTask enters offTask phase")
        // Still-off-task reads keep the prompt up (the user must answer or return
        // to work) — they don't escalate further.
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .offTask, "still-off-task reads keep the prompt up")
        // But returning to a declared task while the prompt is up auto-dismisses
        // it and resumes — AccountaBall keeps actively checking the screen.
        engine.processResult(.onTask(index: 0, label: ""))
        expect(state.appPhase == .session, "returning to a task auto-dismisses the prompt")
        expect(state.activeTaskIndex == 0, "auto-resume sets the active task")
        expect(state.ballState == .onTask, "auto-resume restores the on-task ball")

        (state, engine) = make()
        let box3 = Box()
        engine.now = { box3.now }
        engine.processResult(.offTask(label: ""))
        box3.now = box3.now.addingTimeInterval(16)
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .offTask, "confirmed offTask phase")
        engine.resumeAfterExcuse()
        expect(state.ballState == .onTask, "resumeAfterExcuse restores onTask ball")
        expect(state.appPhase == .session, "resumeAfterExcuse restores session phase")
        engine.processResult(.offTask(label: ""))
        expect(state.appPhase == .session, "suspicion reset by resumeAfterExcuse")
    }

    // 3-state QA fix: capturing holds an App Nap activity so the per-second UI
    // timers (e.g. the break countdown) tick reliably while the app is backgrounded.
    suite("EngineAppNapToken") {
        let (_, engine) = make()
        expect(engine.isPreventingAppNap == false, "no activity token before start")
        engine.start()
        expect(engine.isPreventingAppNap == true, "start() holds an App Nap activity")
        engine.stop()
        expect(engine.isPreventingAppNap == false, "stop() releases it")
    }
}

@MainActor
func runEngineSessionTests() {
    suite("EngineSessionTests") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "test", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx

        engine.beginSession(tasks: [TaskItem(task: "test", context: "")])
        expect(engine.currentSession != nil, "session is active after beginSession")
        expect(engine.currentSession?.taskTitles == ["test"], "task titles snapshotted")

        engine.record(taskIndex: 0, label: "x")
        engine.record(taskIndex: 0, label: "y")
        let entryLabels = Set(engine.currentSession?.entries.map { $0.label } ?? [])
        expect(engine.currentSession?.entries.count == 2, "two timeline entries recorded")
        expect(entryLabels == ["x", "y"], "both labels stored (order-independent — SwiftData @Relationship arrays don't guarantee insertion order)")
        expect(engine.currentSession?.entries.allSatisfy { $0.taskIndex == 0 } == true, "task index stored on every entry")

        engine.endSession()
        expect(engine.currentSession == nil, "currentSession is nil after endSession")
        expect(engine.currentSession == nil, "session ended cleanly")
    }

    suite("EngineSessionTests_labelCapture") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "test", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        engine.beginSession(tasks: s.tasks)

        engine.processResult(.onTask(index: 0, label: "writing"))
        expect(engine.lastActivityLabel == "writing", "onTask label captured")

        engine.processResult(.offTask(label: "twitter"))
        expect(engine.lastActivityLabel == "twitter", "offTask label captured")
        expect(engine.currentSession?.entries.contains(where: { $0.label == "twitter" }) == true, "offTask entry recorded with label")
    }

    suite("EngineDriftLimitTests") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let state = AppState()
        state.tasks = [TaskItem(task: "write proposal", context: "")]
        state.startSession()
        let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        engine.beginSession(tasks: state.tasks)

        guard let session = engine.currentSession else {
            expect(false, "session active after beginSession"); return
        }

        // Seed two confirmed off-task drifts and one ambiguous event. Mirror how
        // the engine logs an event: insert into ctx AND append to the session's
        // justifications, then save.
        func seed(kind: String) {
            let event = JustificationEvent(
                at: .now, excuse: "x", justified: false, inferredTaskIndex: nil,
                activity: "y", rule: "", kind: kind
            )
            ctx.insert(event)
            session.justifications.append(event)
        }
        seed(kind: "offtask")
        seed(kind: "offtask")
        seed(kind: "ambiguous")
        try? ctx.save()

        expect(engine.driftCount == 2, "driftCount counts only kind==offtask")
        state.driftLimit = 2
        expect(engine.commitmentBroken == true, "commitmentBroken true at limit")
        state.driftLimit = 3
        expect(engine.commitmentBroken == false, "commitmentBroken false under limit")
    }

    suite("AppStateDriftLimitPersistence") {
        let key = "accountaball.driftLimit.v1"

        // Persists across save/load.
        UserDefaults.standard.removeObject(forKey: key)
        let a = AppState()
        a.driftLimit = 5
        // AppState()'s default-value init does NOT fire didSet, so constructing `b` does not overwrite a's persisted value before loadDriftLimit() reads it.
        let b = AppState()
        b.loadDriftLimit()
        expect(b.driftLimit == 5, "loadDriftLimit reads back the persisted value")

        // Unset key defaults to 3.
        UserDefaults.standard.removeObject(forKey: key)
        let c = AppState()
        c.loadDriftLimit()
        expect(c.driftLimit == 3, "unset drift limit defaults to 3")
        UserDefaults.standard.removeObject(forKey: key)  // cleanup

        // didSet clamps out-of-range assignments to 1...10 (single source of truth).
        UserDefaults.standard.removeObject(forKey: key)
        let s = AppState()
        s.driftLimit = 50
        expect(s.driftLimit == 10, "driftLimit clamps high values to 10 on assignment")
        s.driftLimit = 0
        expect(s.driftLimit == 1, "driftLimit clamps low values to 1 on assignment")
        s.driftLimit = -5
        expect(s.driftLimit == 1, "driftLimit clamps negatives to 1 on assignment")
        UserDefaults.standard.removeObject(forKey: key)  // cleanup
    }

    // Task 5: entering the confirmed off-task prompt logs exactly one drift
    // (kind=="offtask") the moment the break/resume card surfaces — independent
    // of any later button press or typed excuse.
    suite("EngineConfirmedDriftLogged") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let state = AppState()
        state.tasks = [TaskItem(task: "write proposal", context: "")]
        state.startSession()
        let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        let driftBox = Box()
        engine.now = { driftBox.now }
        engine.beginSession(tasks: state.tasks)
        // Drop the settle window so the two off reads aren't suppressed.
        engine.resetSettleWindowToPast()

        engine.processResult(.offTask(label: "YouTube music"))   // starts the dwell clock
        driftBox.now = driftBox.now.addingTimeInterval(16)       // same screen, ≥15s
        engine.processResult(.offTask(label: "YouTube music"))   // dwell confirms the drift
        expect(engine.driftCount == 1, "entering offTask logs one confirmed drift")
        expect(state.appPhase == .offTask, "phase is offTask")

        // A third still-off read while already in .offTask must NOT log again —
        // the prompt is already up, the drift was the entry transition.
        engine.processResult(.offTask(label: "YouTube music"))
        expect(engine.driftCount == 1, "still-off reads while prompt is up do not re-log a drift")
    }

    suite("EngineReturnToWorkDoesNotInflateDrift") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let state = AppState()
        state.tasks = [TaskItem(task: "write proposal", context: "")]
        state.startSession()
        let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        let returnBox = Box()
        engine.now = { returnBox.now }
        engine.beginSession(tasks: state.tasks)
        engine.resetSettleWindowToPast()

        // Drift into .offTask (same screen held ≥15s -> confirmed drift, prompt up).
        engine.processResult(.offTask(label: "YouTube"))
        returnBox.now = returnBox.now.addingTimeInterval(16)
        engine.processResult(.offTask(label: "YouTube"))
        expect(engine.driftCount == 1, "entering offTask logs one confirmed drift")
        expect(state.appPhase == .offTask, "phase is offTask while prompt is up")

        // User returns to work on their own while the prompt is showing.
        engine.processResult(.onTask(index: 0, label: "back to it"))

        expect(engine.driftCount == 1, "returning to work does not inflate drift count")
        expect(engine.currentSession?.justifications.contains { $0.kind == "auto-return" } == true,
               "returned-to-work event is recorded with kind auto-return")
        expect(state.appPhase == .session, "auto-resumed back to session")
    }

    // Task 6: AMBIGUOUS ask-once flow. An ambiguous read resets suspicion (not a
    // confirmed drift), raises ONE calm ask, dedupes by activity, and resolves via
    // accept (-> allowance, no drift) or reject (-> confirmed drift).
    suite("EngineAmbiguousAskOnce") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()

        @MainActor
        func makeEngine() -> (AppState, AccountabilityEngine) {
            let state = AppState()
            state.tasks = [TaskItem(task: "build the deck", context: "")]
            state.startSession()
            let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
            engine.modelContext = ctx
            engine.beginSession(tasks: state.tasks)
            engine.resetSettleWindowToPast()
            return (state, engine)
        }

        // 1. First ambiguous read raises one calm ask, and is NOT a confirmed drift.
        do {
            let (state, engine) = makeEngine()
            engine.processResult(.ambiguous(label: "Excel budget sheet"))
            expect(state.appPhase == .ambiguous, "first ambiguous read raises the calm ask (.ambiguous phase)")
            expect(engine.driftCount == 0, "ambiguous is not a confirmed drift")
        }

        // 2. Ask once: after resuming, the SAME ambiguous label is not re-asked.
        do {
            let (state, engine) = makeEngine()
            engine.processResult(.ambiguous(label: "Excel budget sheet"))
            expect(state.appPhase == .ambiguous, "first ambiguous read asks")
            engine.resumeAfterExcuse()
            engine.resetSettleWindowToPast()
            expect(state.appPhase == .session, "resumed back to session")
            engine.processResult(.ambiguous(label: "Excel budget sheet"))
            expect(state.appPhase == .session, "same ambiguous label is not re-asked (stays in session)")
        }

        // 3. Reject = confirmed drift -> OFF break/resume card.
        do {
            let (state, engine) = makeEngine()
            engine.processResult(.ambiguous(label: "Excel budget sheet"))
            engine.rejectAmbiguous()
            expect(engine.driftCount == 1, "rejecting an ambiguous ask records a confirmed drift")
            expect(state.appPhase == .offTask, "reject shows the OFF break/resume card")
        }

        // 4. Accept = take their word -> allowance, no drift, resume.
        do {
            let (state, engine) = makeEngine()
            engine.processResult(.ambiguous(label: "Excel budget sheet"))
            let driftBefore = engine.driftCount
            engine.acceptAmbiguous(reason: "budget for the deck")
            let justifiedAmbiguous = engine.currentSession?.justifications.contains {
                $0.kind == "ambiguous" && $0.justified
            } ?? false
            expect(justifiedAmbiguous, "accept logs a kind=ambiguous justified event")
            expect(engine.driftCount == driftBefore, "accept does not increment drift")
            let rules = engine.allowanceRulesByIndex(for: state.activeTasks)
            expect(rules[0]?.contains("budget for the deck") == true, "accept creates an allowance with the rule on task 0")
            expect(state.appPhase == .session, "accept resumes the session")
        }
    }

    // Task 7: timed 5-minute break. takeBreak() returns to .session and goes
    // quiet — off reads during the window neither prompt nor log a drift. After
    // the window elapses, normal suspicion accrual resumes. Completion is still
    // honored during a break, and returning to work early credits on-task time.
    suite("EngineTimedBreak") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()

        @MainActor
        func makeEngine() -> (AppState, AccountabilityEngine, Box) {
            let state = AppState()
            state.tasks = [TaskItem(task: "write proposal", context: "")]
            state.startSession()
            let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
            engine.modelContext = ctx
            let box = Box()
            engine.now = { box.now }
            engine.beginSession(tasks: state.tasks)
            return (state, engine, box)
        }

        // 1. During a break: two off reads neither prompt nor log a drift, even
        //    past the settle window.
        do {
            let (state, engine, box) = makeEngine()
            engine.takeBreak()
            expect(state.appPhase == .session, "break returns to session")
            // Advance past the settle window but still well within the 5-min break
            // so the break (not the settle window) is what suppresses.
            box.now = box.now.addingTimeInterval(engine.settleWindow + 1)
            engine.processResult(.offTask(label: "YouTube"))
            engine.processResult(.offTask(label: "YouTube"))
            expect(state.appPhase == .session, "no prompt during break")
            expect(engine.driftCount == 0, "no drift logged during break")
        }

        // 2. breakSecondsRemaining is non-nil (~breakSeconds) right after takeBreak,
        //    nil once the break elapses.
        do {
            let (_, engine, box) = makeEngine()
            engine.takeBreak()
            if let rem = engine.breakSecondsRemaining {
                expect(rem > AppConstants.breakSeconds - 1 && rem <= AppConstants.breakSeconds,
                       "breakSecondsRemaining ~breakSeconds right after takeBreak")
            } else {
                expect(false, "breakSecondsRemaining non-nil during the break")
            }
            box.now = box.now.addingTimeInterval(AppConstants.breakSeconds + 1)
            expect(engine.breakSecondsRemaining == nil, "breakSecondsRemaining nil after the break elapses")
        }

        // 3. After the break elapses, normal behavior resumes (suspicion accrues
        //    again, prompting on the second off read).
        do {
            let (state, engine, box) = makeEngine()
            engine.takeBreak()
            box.now = box.now.addingTimeInterval(AppConstants.breakSeconds + 1)
            engine.processResult(.offTask(label: "YouTube"))
            box.now = box.now.addingTimeInterval(16)   // hold the same off-task screen ≥15s
            engine.processResult(.offTask(label: "YouTube"))
            expect(state.appPhase == .offTask, "normal prompting resumes after the break elapses")
            expect(engine.driftCount == 1, "a drift is logged after the break elapses")
        }

        // 4. Completion is still honored during a break.
        do {
            let (state, engine, _) = makeEngine()
            engine.takeBreak()
            engine.processResult(.done(index: 0, label: "shipped it"))
            expect(state.tasks[0].isComplete == true, "completion honored during a break")
        }

        // 5. Returning to work early during a break credits on-task time.
        do {
            let (state, engine, _) = makeEngine()
            engine.takeBreak()
            engine.processResult(.onTask(index: 0, label: "back to it"))
            expect(state.tasks[0].timeOnTask == AppConstants.cycleSeconds, "early return-to-work during break credits one cycle")
            expect(state.activeTaskIndex == 0, "early return sets active task")
        }
    }

    // Task 10: a prompt ignored past the response window records an honest
    // kind="auto-return" row (justified, NOT a drift) and resumes watching.
    suite("EngineAutoReturnFromPrompt") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let state = AppState()
        state.tasks = [TaskItem(task: "write proposal", context: "")]
        state.startSession()
        let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        engine.modelContext = ctx
        engine.beginSession(tasks: state.tasks)

        // Arrange WITHOUT logging a drift: a single off-task read inside the settle
        // window (the default after beginSession) sets lastActivityLabel and bumps
        // suspicion to 1 only — it does NOT transition or log a drift. Then put the
        // app in the .offTask prompt phase directly.
        engine.processResult(.offTask(label: "Reddit"))
        expect(engine.driftCount == 0, "arrange: single in-settle off read logs no drift")
        state.appPhase = .offTask

        engine.autoReturnFromPrompt()
        expect(state.appPhase == .session, "auto-return resumes session")
        expect(engine.driftCount == 0, "auto-return is logged, not a drift")
        let kinds = engine.currentSession?.justifications.map { $0.kind } ?? []
        expect(kinds.contains("auto-return"), "an auto-return row exists")
        let autoReturn = engine.currentSession?.justifications.first { $0.kind == "auto-return" }
        expect(autoReturn?.justified == true, "auto-return is justified")
        expect(autoReturn?.rule == "resumed watching", "auto-return uses rule=resumed watching")
        expect(autoReturn?.activity == "Reddit", "auto-return carries the last activity label")
    }

    // 3-state QA fix: a drift is confirmed only after the user stays on the SAME
    // off-task screen for `driftConfirmSeconds`. Brief glances and hopping between
    // off-task screens never confirm; returning to work restarts the clock.
    suite("EngineDriftDwell") {
        guard let container = try? AccountaBallStore.makeContainer(inMemory: true) else {
            expect(false, "container builds"); return
        }
        let ctx = container.mainContext
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()

        @MainActor
        func makeEngine() -> (AppState, AccountabilityEngine, Box) {
            let state = AppState()
            state.tasks = [TaskItem(task: "write proposal", context: "")]
            state.startSession()
            let engine = AccountabilityEngine(state: state, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
            engine.modelContext = ctx
            let box = Box()
            engine.now = { box.now }
            engine.beginSession(tasks: state.tasks)
            engine.resetSettleWindowToPast()
            return (state, engine, box)
        }

        // 1. Same screen <15s does not confirm.
        do {
            let (state, engine, _) = makeEngine()
            engine.processResult(.offTask(label: "yt"))
            engine.processResult(.offTask(label: "yt"))
            expect(state.appPhase == .session, "same-screen <15s does not confirm a drift")
            expect(engine.driftCount == 0, "no drift logged under the dwell threshold")
        }

        // 2. Same screen ≥15s confirms once.
        do {
            let (state, engine, box) = makeEngine()
            engine.processResult(.offTask(label: "yt"))
            box.now = box.now.addingTimeInterval(16)
            engine.processResult(.offTask(label: "yt"))
            expect(state.appPhase == .offTask, "same-screen ≥15s confirms the drift")
            expect(engine.driftCount == 1, "exactly one drift logged on confirm")
        }

        // 3. Continuous off-task time accumulates across label changes / OCR wobble.
        do {
            let (state, engine, box) = makeEngine()
            engine.processResult(.offTask(label: "yt"))
            box.now = box.now.addingTimeInterval(8)
            engine.processResult(.offTask(label: "twitter"))
            box.now = box.now.addingTimeInterval(8)   // 16s continuously off-task across labels
            engine.processResult(.offTask(label: "twitter"))
            expect(state.appPhase == .offTask, "sustained off-task confirms across label changes (OCR-wobble fix)")
            expect(engine.driftCount == 1, "one drift after 15s of continuous off-task")
        }

        // 3b. OCR wobble on ONE static screen (label changes every cycle) still confirms.
        do {
            let (state, engine, box) = makeEngine()
            engine.processResult(.offTask(label: "YouTube — video A"))
            box.now = box.now.addingTimeInterval(8)
            engine.processResult(.offTask(label: "YouTube — video A (recommended)"))
            box.now = box.now.addingTimeInterval(8)
            engine.processResult(.offTask(label: "YouTube — watching, 2 min in"))
            expect(state.appPhase == .offTask, "label wobble on one screen still confirms a drift")
            expect(engine.driftCount == 1, "one drift after 15s on the same screen despite label drift")
        }

        // 4. On-task between off reads restarts the streak.
        do {
            let (state, engine, box) = makeEngine()
            engine.processResult(.offTask(label: "yt"))
            box.now = box.now.addingTimeInterval(10)
            engine.processResult(.onTask(index: 0, label: "work"))
            box.now = box.now.addingTimeInterval(10)
            engine.processResult(.offTask(label: "yt"))
            expect(state.appPhase == .session, "on-task between reads restarts the off-task streak")
            expect(engine.driftCount == 0, "no drift after the streak was restarted")
        }
    }

    suite("EngineSessionTests_noContextIsNoop") {
        // Engine built without a modelContext (test stub path) should not crash
        // when beginSession/record/endSession are called.
        let capture = ScreenCaptureService()
        let ocr = OCRService()
        let notif = NotificationService()
        let s = AppState()
        s.tasks = [TaskItem(task: "t", context: "")]
        s.startSession()
        let engine = AccountabilityEngine(state: s, captureService: capture, ocrService: ocr, aiService: MultiMockAI(), notificationService: notif)
        // modelContext intentionally nil
        engine.beginSession(tasks: s.tasks)
        expect(engine.currentSession == nil, "beginSession is a no-op without context")
        engine.record(taskIndex: 0, label: "x")
        expect(true, "record is a no-op without session")
        engine.endSession()
        expect(true, "endSession is a no-op without session")
    }
}
