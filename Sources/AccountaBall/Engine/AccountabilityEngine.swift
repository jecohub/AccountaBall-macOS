import Foundation
import SwiftData

@MainActor
class AccountabilityEngine {
    private let state: AppState
    private let captureService: ScreenCaptureService
    private let ocrService: OCRService
    private let aiService: AIService
    private let notificationService: NotificationService
    private var captureTask: Task<Void, Never>?
    private var suspicionCount: Int = 0
    private(set) var lastScreenText: String = ""
    private var healthPollTask: Task<Void, Never>?

    /// Injectable clock for deterministic settle-window tests.
    var now: () -> Date = { Date() }
    let settleWindow: TimeInterval = 15
    private var settleUntil: Date = .distantPast

    /// Activity-scoped "Give me 2 minutes" grace. While the user stays on the
    /// off-task activity they explicitly asked to continue, off-task reads are
    /// suppressed. Switching to a *different* activity ends the grace and
    /// re-checks immediately — the breather is for that one screen, not a blanket
    /// pass to do anything off-task.
    private var graceActivity: String?
    private var graceUntil: Date = .distantPast
    private var inActivityGrace: Bool { graceActivity != nil && now() < graceUntil }

    // v3 — persistence
    var modelContext: ModelContext?
    var currentSession: WorkSession?
    private(set) var lastActivityLabel: String = ""

    /// Activities we've already raised an ambiguous "is this related?" ask about
    /// this session. AMBIGUOUS asks ONCE per activity — once answered (or matched
    /// to a grace), the same screen stays silent. Reset on `beginSession`.
    private var askedActivities: Set<String> = []

    /// Confirmed drifts this session = off-task JustificationEvents. Derived so it
    /// can never desync from the record the recap shows.
    var driftCount: Int {
        (currentSession?.justifications.filter { $0.kind == "offtask" }.count) ?? 0
    }

    /// The pre-committed limit was reached. The in-the-moment user cannot change
    /// `state.driftLimit` (it's set only at setup), so this is tamper-proof.
    var commitmentBroken: Bool { driftCount >= state.driftLimit }

    // Revived allowances awaiting one-time user confirmation on reuse (Task 18).
    private var pendingConfirms: [(title: String, kt: KnowledgeTask, allowance: Allowance)] = []

    init(
        state: AppState,
        captureService: ScreenCaptureService,
        ocrService: OCRService,
        aiService: AIService,
        notificationService: NotificationService
    ) {
        self.state = state
        self.captureService = captureService
        self.ocrService = ocrService
        self.aiService = aiService
        self.notificationService = notificationService
    }

    func start() {
        captureTask = captureService.startLoop(interval: AppConstants.cycleSeconds, panelTitle: "AccountaBall") { [weak self] frame in
            guard let self else { return }
            let text = await self.screenText(from: frame)
            guard !text.isEmpty else { return }
            self.lastScreenText = text
            let activeTasks = self.state.activeTasks
            guard !activeTasks.isEmpty else { return }
            let result: MultiTaskResult?
            do {
                result = try await self.aiService.classifyMulti(
                    tasks: activeTasks,
                    screenText: text,
                    allowanceRulesByIndex: self.allowanceRulesByIndex(for: activeTasks)
                )
            } catch {
                if Self.isBenignCancellation(error) {
                    // We cancelled the request (loop tick/stop) — not an outage.
                    dbg("classifyMulti cancelled (benign skip)")
                } else {
                    dbg("classifyMulti failed (skipping cycle): \(error)")
                    self.enterAIUnavailable(reason: error)
                }
                result = nil
            }
            DebugLog.dbgBlock("CYCLE", [
                "ocr=\(DebugLog.truncate(text, max: 200))",
                "prompt: tasks=\(activeTasks.count) allowances=0",
                "parsed=\(result.map { "\($0)" } ?? "nil")",
                "state: suspicion=\(self.suspicionCount) activeTaskIndex=\(String(describing: self.state.activeTaskIndex))"
            ])
            self.processCycle(result)
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        suspicionCount = 0
    }

    /// Build the text we classify from a capture tick: the focused window in full
    /// (primary), plus a truncated pass over the whole screen as lighter
    /// peripheral context (so a relevant reference in another window still
    /// registers). With no focused window, the full screen is the only signal.
    func screenText(from frame: CapturedFrame) async -> String {
        guard let focused = frame.focused else {
            return await ocrService.extractText(from: frame.full)
        }
        let primary = await ocrService.extractText(from: focused)
        let full = await ocrService.extractText(from: frame.full)
        let light = String(full.prefix(AppConstants.peripheralScreenChars))
        if primary.isEmpty { return light }
        if light.isEmpty { return primary }
        return "Active window:\n\(primary)\n\nAlso visible on screen:\n\(light)"
    }

    /// Resume watching after an off-task prompt.
    ///
    /// - Parameter graceForCurrentActivity: when true (the "Give me 2 minutes"
    ///   escape hatch), grant an activity-scoped grace for the current off-task
    ///   activity (`lastActivityLabel`): off-task reads matching it are suppressed
    ///   for `continueAnywayGraceSeconds`, but switching to a different activity
    ///   ends the grace and re-checks. When false ("Back to work"), no grace —
    ///   just the normal short settle breather.
    func resumeAfterExcuse(graceForCurrentActivity: Bool = false) {
        suspicionCount = 0
        state.ballState = .onTask
        state.appPhase = .session
        resetSettleWindow()  // brief unconditional breather in both cases
        if graceForCurrentActivity, !lastActivityLabel.isEmpty {
            graceActivity = lastActivityLabel
            graceUntil = now().addingTimeInterval(AppConstants.continueAnywayGraceSeconds)
            dbg("resumeAfterExcuse -> session (activity grace for \"\(lastActivityLabel)\" +\(Int(AppConstants.continueAnywayGraceSeconds))s)")
        } else {
            clearActivityGrace()
            dbg("resumeAfterExcuse -> session (no grace)")
        }
    }

    private func clearActivityGrace() {
        graceActivity = nil
        graceUntil = .distantPast
    }

    /// Two activity labels refer to the same on-screen activity. Case/whitespace-
    /// insensitive exact match — deterministic decoding (temperature 0) keeps the
    /// label stable per screen, so equality is a reliable "same screen" signal.
    static func activityMatches(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return norm(a) == norm(b)
    }

    /// True for cancellation-class errors (we cancelled the in-flight request as
    /// part of the normal capture lifecycle). These must NOT be treated as a
    /// provider outage — otherwise stopping/ticking the loop spuriously flips the
    /// app into `.aiUnavailable`.
    static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    // MARK: - AI unavailable

    /// The phase we were in when the provider went down, so recovery returns the
    /// user where they were (e.g. the welcome screen if they never started a
    /// session) instead of always dumping them into `.session`.
    private var phaseBeforeUnavailable: AppPhase = .session

    @MainActor
    func enterAIUnavailable(reason: Error? = nil) {
        guard state.appPhase != .aiUnavailable else { return }
        dbg("AI unavailable: \(reason.map { "\($0)" } ?? "health check failed")")
        // Remember where we were so recovery returns there (a fresh launch with
        // the provider down is on .welcome/.setup, not in a session).
        phaseBeforeUnavailable = state.appPhase
        stop()
        // Drop the capturing flag so recovery's `isCapturing = true` is a real
        // false→true edge for the AppDelegate watcher, which re-calls start().
        state.isCapturing = false
        state.aiUnavailableHint = aiHint()
        state.ballState = .idle
        state.appPhase = .aiUnavailable
        startHealthPolling()
    }

    @MainActor
    private func aiHint() -> String {
        "Can't reach the AI. If using Ollama, run it and pull the model (e.g. `ollama run qwen2.5:7b`); or set AI_PROVIDER/OPENROUTER_API_KEY."
    }

    @MainActor
    private func startHealthPolling() {
        healthPollTask?.cancel()
        healthPollTask = Task { @MainActor in
            while !Task.isCancelled {
                // Sleep BEFORE the first check so recovery waits at least one
                // interval. Otherwise an optimistic healthCheck() (e.g.
                // OpenRouter's `!apiKey.isEmpty`) recovers instantly, the next
                // classify fails, and we thrash the card every cycle.
                try? await Task.sleep(for: .seconds(AppConstants.cycleSeconds))
                if Task.isCancelled { return }
                if await aiService.healthCheck() {
                    recoverFromAIUnavailable()
                    return
                }
            }
        }
    }

    @MainActor
    func recoverFromAIUnavailable() {
        guard state.appPhase == .aiUnavailable else { return }
        healthPollTask?.cancel(); healthPollTask = nil
        state.aiUnavailableHint = nil
        // Return to wherever the outage interrupted us. Only re-arm watching when
        // that was an active session; on .welcome/.setup the user hasn't started.
        let target = phaseBeforeUnavailable == .aiUnavailable ? .welcome : phaseBeforeUnavailable
        dbg("AI recovered -> resuming at \(target)")
        state.appPhase = target
        if target == .session {
            state.ballState = .onTask
            state.isCapturing = true
            resetSettleWindow()
        } else {
            state.ballState = .idle
        }
    }

    /// Process one classification *outcome*. `result == nil` means the AI call
    /// failed — skip the cycle entirely (no suspicion bump, never off-task).
    @MainActor
    func processCycle(_ result: MultiTaskResult?) {
        guard let result else { return }
        processResult(result)
    }

    // MARK: - v3 session lifecycle

    private var inSettleWindow: Bool { now() < settleUntil }

    @MainActor
    func resetSettleWindow() { settleUntil = now().addingTimeInterval(settleWindow) }

    /// Test seam: collapse the settle window so off-task reads aren't suppressed.
    func resetSettleWindowToPast() { settleUntil = .distantPast }

    @MainActor
    func beginSession(tasks: [TaskItem] = []) {
        guard modelContext != nil else { return }
        let session = WorkSession(startedAt: .now)
        session.taskTitles = tasks.map { $0.task }
        modelContext?.insert(session)
        try? modelContext?.save()
        currentSession = session
        askedActivities = []
        resetSettleWindow()
    }

    @MainActor
    func endSession() {
        guard let session = currentSession, let ctx = modelContext else { return }
        session.endedAt = .now
        try? ctx.save()
        currentSession = nil
    }

    /// Log a single accountability check as a JustificationEvent. The drift is the
    /// FACT of being off-task (or ambiguous, or auto-returned), recorded the moment
    /// the decision is made — independent of any later button press. `kind`
    /// distinguishes the flow ("offtask" | "ambiguous" | "auto-return"); `driftCount`
    /// (and the transparency log) read these back. Reused by Tasks 6 and 10.
    @MainActor
    private func logCheck(kind: String, justified: Bool, activity: String,
                          excuse: String, rule: String, taskIndex: Int?) {
        guard let session = currentSession, let ctx = modelContext else { return }
        let event = JustificationEvent(at: .now, excuse: excuse, justified: justified,
            inferredTaskIndex: taskIndex, activity: activity, rule: rule, kind: kind)
        ctx.insert(event)
        session.justifications.append(event)
        try? ctx.save()
    }

    @MainActor
    func record(taskIndex: Int?, label: String) {
        guard let session = currentSession, let ctx = modelContext else { return }
        let entry = TimelineEntry(at: .now, taskIndex: taskIndex, label: label)
        session.entries.append(entry)
        ctx.insert(entry)
        try? ctx.save()
    }

    // MARK: - v3 task matching

    @MainActor
    func proposeMatch(for taskText: String) async -> KnowledgeTask? {
        guard let ctx = modelContext else { return nil }
        let allKTs = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>())) ?? []
        let candidates: [(id: String, normalized: String, originals: [String])] =
            allKTs.map { ($0.normalizedTitle, $0.normalizedTitle, $0.originalTitles) }
        // 1. Cheap path
        if let id = TaskMatcher.cheapMatch(taskText, in: candidates),
           let kt = allKTs.first(where: { $0.normalizedTitle == id }) {
            return kt
        }
        // 2. AI fallback
        let aiCandidates: [(id: String, title: String, summary: String)] =
            allKTs.map { ($0.normalizedTitle, $0.originalTitles.last ?? $0.normalizedTitle, $0.completions.sorted { $0.completedAt > $1.completedAt }.first?.summary ?? "") }
        do {
            if let (id, confident) = try await aiService.matchTask(query: taskText, candidates: aiCandidates), confident {
                return allKTs.first(where: { $0.normalizedTitle == id })
            }
        } catch {
            dbg("matchTask failed: \(error)")
        }
        return nil
    }

    @MainActor
    func linkKnowledgeTask(_ kt: KnowledgeTask, to taskIndex: Int) async {
        guard state.tasks.indices.contains(taskIndex) else { return }
        state.tasks[taskIndex].knowledgeRef = kt.id
        // Revive allowances with needsConfirmation
        for i in kt.allowances.indices {
            kt.allowances[i].needsConfirmation = true
        }
        try? modelContext?.save()
        // Queue each revived allowance for one-time confirmation, then surface
        // the first prompt (the rest follow as the user answers).
        let title = state.tasks[taskIndex].task
        for allowance in kt.allowances where allowance.needsConfirmation {
            pendingConfirms.append((title: title, kt: kt, allowance: allowance))
        }
        surfaceNextAllowanceConfirm()
    }

    // MARK: - v3 allowance confirm-on-reuse (Task 18)

    /// Publish the next queued allowance to the UI (or clear when the queue empties).
    @MainActor
    private func surfaceNextAllowanceConfirm() {
        if let next = pendingConfirms.first {
            state.pendingAllowanceConfirm = AllowanceConfirm(taskTitle: next.title, rule: next.allowance.rule)
        } else {
            state.pendingAllowanceConfirm = nil
        }
    }

    /// User confirmed the revived allowance still applies: clear its flag so it
    /// counts again, then advance to the next pending prompt.
    @MainActor
    func confirmPendingAllowance() {
        guard let front = pendingConfirms.first else { return }
        front.allowance.needsConfirmation = false
        try? modelContext?.save()
        pendingConfirms.removeFirst()
        surfaceNextAllowanceConfirm()
    }

    /// User rejected the revived allowance: delete it, then advance.
    @MainActor
    func rejectPendingAllowance() {
        guard let front = pendingConfirms.first else { return }
        front.kt.allowances.removeAll { $0 === front.allowance }
        modelContext?.delete(front.allowance)
        try? modelContext?.save()
        pendingConfirms.removeFirst()
        surfaceNextAllowanceConfirm()
    }

    func processResult(_ result: MultiTaskResult) {
        // While the off-task prompt is showing, keep actively checking the screen:
        // if the user has returned to a declared task, auto-dismiss the prompt and
        // resume — no excuse needed (deterministic decoding makes a single on-task
        // read trustworthy). Off-task / done reads are still ignored so the prompt
        // stays up until the user answers, returns to work, or the 2-min timeout.
        if state.appPhase == .offTask {
            if case .onTask(let index, let label) = result {
                dbg("back on task (\"\(label)\") while prompt up -> auto-resume")
                lastActivityLabel = label
                record(taskIndex: index, label: label)
                state.activeTaskIndex = index
                if state.tasks.indices.contains(index) {
                    state.tasks[index].timeOnTask += AppConstants.cycleSeconds
                }
                // Log the interrogation as self-resolved: the user returned to
                // work on their own, so it's recorded (and counts as justified,
                // not against them).
                if let session = currentSession, let ctx = modelContext {
                    let event = JustificationEvent(
                        at: .now, excuse: "(returned to work)",
                        justified: true, inferredTaskIndex: index,
                        activity: label, rule: "returned to work", kind: "auto-return"
                    )
                    ctx.insert(event)
                    session.justifications.append(event)
                    try? ctx.save()
                }
                resumeAfterExcuse()
            } else {
                dbg("processResult ignored while offTask (still off-task: \(result))")
            }
            return
        }

        switch result {
        case .onTask(let index, let label):
            lastActivityLabel = label
            record(taskIndex: index, label: label)
            suspicionCount = 0
            state.activeTaskIndex = index
            state.ballState = .onTask
            if state.tasks.indices.contains(index) {
                state.tasks[index].timeOnTask += AppConstants.cycleSeconds  // one capture cycle
            }

        case .ambiguous(let label):
            // "Honestly can't tell." Not a confirmed drift — reset suspicion, then
            // ask ONCE per activity (and stay silent if a grace already covers it).
            lastActivityLabel = label
            record(taskIndex: nil, label: label)
            suspicionCount = 0   // ambiguous is not a confirmed drift
            state.activeTaskIndex = nil
            let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if askedActivities.contains(key) || (inActivityGrace && Self.activityMatches(label, graceActivity ?? "")) {
                dbg("ambiguous already asked / in grace (\"\(label)\") — silent")
                return
            }
            guard !inSettleWindow, state.appPhase == .session else { return }
            askedActivities.insert(key)
            dbg("ambiguous — raising one calm ask for \"\(label)\"")
            state.ballState = .offTask
            state.appPhase = .ambiguous

        case .offTask(let label):
            lastActivityLabel = label
            record(taskIndex: nil, label: label)
            // Activity-scoped "Give me 2 minutes": while the user stays on the
            // activity they asked to continue, suppress entirely. If they switch
            // to a different activity, the grace no longer applies — end it and
            // re-check normally.
            if inActivityGrace {
                if Self.activityMatches(label, graceActivity ?? "") {
                    dbg("offTask within activity grace (\"\(label)\") — suppressed")
                    state.activeTaskIndex = nil
                    return
                }
                dbg("offTask activity changed (\"\(label)\" ≠ grace \"\(graceActivity ?? "")\") — ending grace, re-checking")
                clearActivityGrace()
            }
            suspicionCount += 1
            state.activeTaskIndex = nil
            dbg("offTask result (suspicion=\(suspicionCount))")
            if suspicionCount >= 2, !inSettleWindow, state.appPhase == .session {
                dbg("ENTER offTask phase (confirmed drift)")
                logCheck(kind: "offtask", justified: false, activity: label,
                         excuse: "(drifted)", rule: "off-task", taskIndex: nil)
                state.ballState = .offTask
                state.appPhase = .offTask
                notificationService.sendOffTaskNudge(task: state.activeTasks.first?.task ?? "")
            }

        case .done(let index, let label):
            lastActivityLabel = label
            record(taskIndex: index, label: label)
            stop()
            state.completeTaskAt(index: index)
            // Fire-and-forget — don't block the completion animation.
            Task { [weak self] in
                await self?.summarizeCompletion(taskIndex: index)
            }
        }
    }

    // MARK: - v3 session recap (end-of-session breakdown)

    /// Build the end-of-session breakdown: mechanical timeline ranges + one AI
    /// call for per-task commentary. Comparisons are computed locally. Safe to
    /// call once all tasks are complete. Never throws — AI failure degrades to
    /// timeline + local comparison strings.
    @MainActor
    func finalizeSessionRecap() async {
        guard let session = currentSession, let ctx = modelContext else { return }

        let ranges = TimelineCoalescer.ranges(
            sessionStart: session.startedAt,
            entries: session.entries.map { (at: $0.at, taskIndex: $0.taskIndex, label: $0.label) }
        )

        // Session-wide off-task count. True per-task attribution is out of
        // scope, so every task input carries the same total.
        let offCount = session.justifications.filter { !$0.justified }.count
        let sortedReads = session.entries.sorted { $0.at < $1.at }.map { ($0.taskIndex, $0.label) }

        var inputs: [PerTaskSessionInput] = []
        for (taskIdx, task) in state.tasks.enumerated() {
            let dur = task.timeOnTask
            let normalized = TaskMatcher.normalize(task.task)
            let kt = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>(predicate: #Predicate { $0.normalizedTitle == normalized })))?.first
            let prior = (kt?.completions ?? []).filter { $0.completedAt < session.startedAt }
            let lastDur = prior.sorted { $0.completedAt > $1.completedAt }.first?.duration
            let avg: TimeInterval? = prior.isEmpty ? nil : prior.map { $0.duration }.reduce(0, +) / Double(prior.count)
            let comparison = Self.comparisonString(current: dur, last: lastDur, average: avg)
            let steps = TimelineCoalescer.labelsForTask(index: taskIdx, reads: sortedReads)
            inputs.append(PerTaskSessionInput(
                title: task.task, durationSeconds: dur,
                lastDurationSeconds: lastDur, averageSeconds: avg,
                offTaskCount: offCount, steps: steps,
                localComparison: comparison
            ))
        }

        var modelComments: [PerTaskComment] = []
        do {
            modelComments = try await aiService.summarizeSession(perTask: inputs)
        } catch {
            dbg("summarizeSession failed: \(error)")
        }

        // Realign the model's comments to our tasks robustly: emit exactly one
        // card per task, in task order, matching on title (case/whitespace-
        // insensitive). If the model dropped/renamed a task, fall back to that
        // task's authoritative local comparison so no card is silently lost.
        func key(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let comments: [PerTaskComment] = inputs.map { input in
            if let match = modelComments.first(where: { key($0.taskTitle) == key(input.title) }) {
                return match
            }
            return PerTaskComment(taskTitle: input.title, comment: input.localComparison, suggestion: nil)
        }
        state.sessionRecap = SessionRecap(ranges: ranges, perTask: comments)
    }

    static func comparisonString(current: TimeInterval, last: TimeInterval?, average: TimeInterval?) -> String {
        func mins(_ t: TimeInterval) -> String { "\(Int((t/60).rounded()))m" }
        guard let last else { return "First time finishing this — \(mins(current))." }
        let d = DurationDelta.compare(current: current, previous: last)
        var s = d.fasterThanPrevious
            ? "Faster than last time (\(mins(last)) → \(mins(current)))."
            : "Slower than last time (\(mins(last)) → \(mins(current)))."
        if let average { s += " Avg \(mins(average))." }
        return s
    }

    // MARK: - v3 completion summary

    /// On task completion: coalesce the session's timeline into steps, fetch (or
    /// create) the KnowledgeTask, ask the AI for a recap + comparison vs. the
    /// last completion, then persist a `TaskCompletion` linked to the
    /// KnowledgeTask. Fire-and-forget from `processResult(.done)`.
    @MainActor
    func summarizeCompletion(taskIndex: Int) async {
        guard let session = currentSession,
              let ctx = modelContext,
              state.tasks.indices.contains(taskIndex) else { return }

        // 1. Coalesce this session's reads for the index. SwiftData to-many
        // relationships are unordered, so sort by timestamp first — the
        // coalescer assumes chronologically-ordered input.
        let reads: [(Int?, String)] = session.entries
            .sorted { $0.at < $1.at }
            .map { ($0.taskIndex, $0.label) }
        let steps = TimelineCoalescer.labelsForTask(index: taskIndex, reads: reads)
        let duration = state.tasks[taskIndex].timeOnTask

        // 2. Resolve/create KnowledgeTask
        let taskTitle = state.tasks[taskIndex].task
        let normalized = TaskMatcher.normalize(taskTitle)
        let existing = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>(
            predicate: #Predicate { $0.normalizedTitle == normalized }
        )))?.first
        let kt: KnowledgeTask
        if let existing = existing {
            kt = existing
        } else {
            let new = KnowledgeTask(normalizedTitle: normalized, lastCompletedAt: .now)
            new.originalTitles = [taskTitle]
            ctx.insert(new)
            kt = new
        }

        // 3. Find previous completion (if any)
        let previous = kt.completions.sorted { $0.completedAt > $1.completedAt }.first
        let previousTuple: (durationSeconds: TimeInterval, steps: [String], offTaskCount: Int)? =
            previous.map { ($0.duration, $0.steps, $0.offTaskCount) }

        // 4. Call AI (off-main; the engine is @MainActor but the call itself is async)
        let recap: TaskRecap
        do {
            recap = try await aiService.summarizeTask(
                title: taskTitle,
                context: state.tasks[taskIndex].context,
                steps: steps,
                durationSeconds: duration,
                previous: previousTuple
            )
        } catch {
            dbg("summarizeTask failed: \(error)")
            // Fall back to an empty recap
            let countOffTask = session.justifications.filter { !$0.justified }.count
            let completion = TaskCompletion(
                completedAt: .now, duration: duration, summary: "", steps: steps,
                offTaskCount: countOffTask
            )
            ctx.insert(completion)
            kt.completions.append(completion)
            kt.lastCompletedAt = .now
            kt.timesCompleted += 1
            try? ctx.save()
            return
        }

        // 5. Append TaskCompletion
        let storedSteps = recap.steps.isEmpty ? steps : recap.steps
        let countOffTaskFinal = session.justifications.filter { !$0.justified }.count
        let completion = TaskCompletion(
            completedAt: .now, duration: duration, summary: recap.summary,
            steps: storedSteps,
            offTaskCount: countOffTaskFinal
        )
        ctx.insert(completion)
        kt.completions.append(completion)
        kt.lastCompletedAt = .now
        kt.timesCompleted += 1
        try? ctx.save()

        // Publish the recap for the UI (Task 18 recap surfaces in progress + completion).
        state.recaps[taskTitle] = TaskRecap(
            summary: recap.summary, steps: storedSteps,
            duration: duration, comparison: recap.comparison
        )
    }

    // MARK: - Phase 1 AMBIGUOUS resolution (ask once; accept/reject)

    /// The user said the ambiguous activity IS related to their work. We take their
    /// word (no AI gate): create an allowance so we don't re-ask, log a justified
    /// `kind="ambiguous"` check, then resume the session. An empty reason falls
    /// back to the activity label as the allowance rule.
    @MainActor
    func acceptAmbiguous(reason: String) {
        let label = lastActivityLabel
        let rule = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? label : reason
        let taskIndex = state.tasks.firstIndex(where: { !$0.isComplete })   // the task the ask referenced
        logCheck(kind: "ambiguous", justified: true, activity: label, excuse: reason, rule: rule, taskIndex: taskIndex)
        if let idx = taskIndex { createAllowance(rule: rule, forTaskIndex: idx) }
        resumeAfterExcuse()
    }

    /// The user said they drifted. Log a confirmed off-task drift (driftCount++),
    /// then show the OFF break/resume card.
    @MainActor
    func rejectAmbiguous() {
        logCheck(kind: "offtask", justified: false, activity: lastActivityLabel,
                 excuse: "(drifted)", rule: "off-task", taskIndex: nil)
        state.ballState = .offTask
        state.appPhase = .offTask
    }

    /// Find-or-create the KnowledgeTask for a declared task and append an Allowance
    /// carrying `rule`, so future classification cycles treat this activity as
    /// allowed. Shared by `handleExcuse` (justified verdict) and `acceptAmbiguous`.
    @MainActor
    private func createAllowance(rule: String, forTaskIndex idx: Int) {
        guard let ctx = modelContext, state.tasks.indices.contains(idx) else { return }
        let normalized = TaskMatcher.normalize(state.tasks[idx].task)
        let existing = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>(
            predicate: #Predicate { $0.normalizedTitle == normalized })))?.first
        let kt = existing ?? KnowledgeTask(normalizedTitle: normalized, lastCompletedAt: .now)
        if existing == nil {
            kt.originalTitles = [state.tasks[idx].task]
            ctx.insert(kt)
        } else if !kt.originalTitles.contains(state.tasks[idx].task) {
            kt.originalTitles.append(state.tasks[idx].task)
        }
        let allowance = Allowance(rule: rule, createdAt: .now)
        ctx.insert(allowance)
        kt.allowances.append(allowance)
        try? ctx.save()
    }

    // MARK: - v3 excuse resolution

    /// Returns the full verdict (so the UI can show the right stage *and* the
    /// model's reason). On a justified verdict the engine records an Allowance +
    /// KnowledgeTask link. Resuming the session is left to the caller
    /// (`OffTaskView`) so it can show the verdict stage and offer the "Give me 2
    /// minutes" escape hatch on rejection before watching resumes.
    @MainActor
    @discardableResult
    func handleExcuse(_ text: String, tasks: [TaskItem], screenText: String) async -> ExcuseVerdict {
        let verdict: ExcuseVerdict
        do {
            verdict = try await aiService.evaluateExcuse(excuse: text, tasks: tasks, screenText: screenText)
        } catch {
            dbg("evaluateExcuse failed: \(error)")
            return ExcuseVerdict(justified: false, taskIndex: nil, rule: "")
        }
        dbg("excuse verdict: \(verdict.justified ? "JUSTIFIED" : "NOT_JUSTIFIED") rule=\"\(verdict.rule)\"")

        // Always log the interrogation, including the model's reason.
        if let session = currentSession, let ctx = modelContext {
            let event = JustificationEvent(
                at: .now,
                excuse: text,
                justified: verdict.justified,
                inferredTaskIndex: verdict.taskIndex,
                activity: lastActivityLabel,
                rule: verdict.rule
            )
            ctx.insert(event)
            session.justifications.append(event)
            try? ctx.save()
        }

        // On justification, create the allowance and link KnowledgeTask
        if verdict.justified, let taskIndex = verdict.taskIndex, tasks.indices.contains(taskIndex) {
            let taskTitle = tasks[taskIndex].task
            let normalized = TaskMatcher.normalize(taskTitle)
            if let ctx = modelContext {
                // Find or create KnowledgeTask
                let existing = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>(
                    predicate: #Predicate { $0.normalizedTitle == normalized }
                )))?.first
                let kt = existing ?? KnowledgeTask(normalizedTitle: normalized, lastCompletedAt: .now)
                if existing == nil {
                    kt.originalTitles = [taskTitle]
                    ctx.insert(kt)
                } else {
                    if !kt.originalTitles.contains(taskTitle) { kt.originalTitles.append(taskTitle) }
                }
                let allowance = Allowance(rule: verdict.rule, createdAt: .now)
                ctx.insert(allowance)
                kt.allowances.append(allowance)
                try? ctx.save()
            }
        }
        // Resuming (or not) is the view's job — see OffTaskView. Returning the
        // full verdict lets it show "Carry on" vs "Get back to work", the model's
        // reason, and the escape hatch.
        return verdict
    }

    @MainActor
    func allowanceRulesByIndex(for tasks: [TaskItem]) -> [Int: [String]] {
        guard let ctx = modelContext else { return [:] }
        var out: [Int: [String]] = [:]
        for (i, task) in tasks.enumerated() {
            let normalized = TaskMatcher.normalize(task.task)
            if let kt = try? ctx.fetch(FetchDescriptor<KnowledgeTask>(
                predicate: #Predicate { $0.normalizedTitle == normalized }
            )).first {
                let active = kt.allowances.filter { !$0.needsConfirmation }.map { $0.rule }
                if !active.isEmpty { out[i] = active }
            }
        }
        return out
    }
}
