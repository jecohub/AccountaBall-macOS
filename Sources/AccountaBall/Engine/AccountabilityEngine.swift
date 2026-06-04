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

    // v3 — persistence
    var modelContext: ModelContext?
    var currentSession: WorkSession?
    private(set) var lastActivityLabel: String = ""
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
        captureTask = captureService.startLoop(interval: 5, panelTitle: "AccountaBall") { [weak self] image in
            guard let self else { return }
            let text = await self.ocrService.extractText(from: image)
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
                dbg("classifyMulti failed (skipping cycle): \(error)")
                self.enterAIUnavailable(reason: error)
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

    func resumeAfterExcuse() {
        dbg("resumeAfterExcuse -> session")
        suspicionCount = 0
        state.ballState = .onTask
        state.appPhase = .session
        resetSettleWindow()
    }

    // MARK: - AI unavailable

    @MainActor
    func enterAIUnavailable(reason: Error? = nil) {
        guard state.appPhase != .aiUnavailable else { return }
        dbg("AI unavailable: \(reason.map { "\($0)" } ?? "health check failed")")
        stop()
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
                if await aiService.healthCheck() {
                    recoverFromAIUnavailable()
                    return
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @MainActor
    func recoverFromAIUnavailable() {
        guard state.appPhase == .aiUnavailable else { return }
        healthPollTask?.cancel(); healthPollTask = nil
        state.aiUnavailableHint = nil
        dbg("AI recovered -> resuming session")
        state.appPhase = .session
        state.ballState = .onTask
        state.isCapturing = true
        resetSettleWindow()
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

    @MainActor
    func beginSession(tasks: [TaskItem] = []) {
        guard modelContext != nil else { return }
        let session = WorkSession(startedAt: .now)
        session.taskTitles = tasks.map { $0.task }
        modelContext?.insert(session)
        try? modelContext?.save()
        currentSession = session
        resetSettleWindow()
    }

    @MainActor
    func endSession() {
        guard let session = currentSession, let ctx = modelContext else { return }
        session.endedAt = .now
        try? ctx.save()
        currentSession = nil
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
        // While the off-task prompt is showing, ignore capture results — the
        // user's excuse (or the 2-minute timeout) decides what happens next.
        // Otherwise the loop could flip back to .session and dismiss the prompt
        // before the user answers.
        guard state.appPhase != .offTask else {
            dbg("processResult ignored while offTask (result=\(result))")
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
                state.tasks[index].timeOnTask += 5  // 5s per capture cycle
            }

        case .offTask(let label):
            lastActivityLabel = label
            record(taskIndex: nil, label: label)
            suspicionCount += 1
            state.activeTaskIndex = nil
            dbg("offTask result (suspicion=\(suspicionCount))")
            if suspicionCount >= 2, !inSettleWindow, state.appPhase == .session {
                dbg("ENTER offTask phase")
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

        var inputs: [PerTaskSessionInput] = []
        for task in state.tasks {
            let dur = task.timeOnTask
            let normalized = TaskMatcher.normalize(task.task)
            let kt = (try? ctx.fetch(FetchDescriptor<KnowledgeTask>(predicate: #Predicate { $0.normalizedTitle == normalized })))?.first
            let prior = (kt?.completions ?? []).filter { $0.completedAt < session.startedAt }
            let lastDur = prior.sorted { $0.completedAt > $1.completedAt }.first?.duration
            let avg: TimeInterval? = prior.isEmpty ? nil : prior.map { $0.duration }.reduce(0, +) / Double(prior.count)
            let comparison = Self.comparisonString(current: dur, last: lastDur, average: avg)
            let offCount = session.justifications.filter { !$0.justified }.count
            let taskIdx = state.tasks.firstIndex(where: { $0.task == task.task }) ?? -1
            let steps = taskIdx >= 0 ? TimelineCoalescer.labelsForTask(
                index: taskIdx,
                reads: session.entries.sorted { $0.at < $1.at }.map { ($0.taskIndex, $0.label) }
            ) : []
            inputs.append(PerTaskSessionInput(
                title: task.task, durationSeconds: dur,
                lastDurationSeconds: lastDur, averageSeconds: avg,
                offTaskCount: offCount, steps: steps,
                localComparison: comparison
            ))
        }

        var comments: [PerTaskComment] = []
        do {
            comments = try await aiService.summarizeSession(perTask: inputs)
        } catch {
            dbg("summarizeSession failed: \(error)")
        }
        if comments.isEmpty {
            comments = inputs.map { PerTaskComment(taskTitle: $0.title, comment: $0.localComparison, suggestion: nil) }
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

    // MARK: - v3 excuse resolution

    /// Returns whether the excuse was judged justified (so the UI can show the
    /// right verdict stage). On a justified verdict the engine also resumes the
    /// session (sets phase back to `.session`).
    @MainActor
    @discardableResult
    func handleExcuse(_ text: String, tasks: [TaskItem], screenText: String) async -> Bool {
        let verdict: ExcuseVerdict
        do {
            verdict = try await aiService.evaluateExcuse(excuse: text, tasks: tasks, screenText: screenText)
        } catch {
            dbg("evaluateExcuse failed: \(error)")
            return false
        }

        // Always log the interrogation
        if let session = currentSession, let ctx = modelContext {
            let event = JustificationEvent(
                at: .now,
                excuse: text,
                justified: verdict.justified,
                inferredTaskIndex: verdict.taskIndex,
                activity: lastActivityLabel
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
            resumeAfterExcuse()
        }
        // If not justified, keep the existing angry state (no extra action here).
        return verdict.justified
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
