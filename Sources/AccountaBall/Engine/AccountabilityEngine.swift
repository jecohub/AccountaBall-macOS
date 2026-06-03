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

    // v3 — persistence
    var modelContext: ModelContext?
    var currentSession: WorkSession?
    private(set) var lastActivityLabel: String = ""

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
            let result = (try? await self.aiService.classifyMulti(tasks: activeTasks, screenText: text, allowanceRulesByIndex: [:])) ?? .offTask(label: "")
            DebugLog.dbgBlock("CYCLE", [
                "ocr=\(DebugLog.truncate(text, max: 200))",
                "prompt: tasks=\(activeTasks.count) allowances=0",
                "parsed=\(result)",
                "state: suspicion=\(self.suspicionCount) activeTaskIndex=\(String(describing: self.state.activeTaskIndex))"
            ])
            self.processResult(result)
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
    }

    // MARK: - v3 session lifecycle

    @MainActor
    func beginSession(tasks: [TaskItem] = []) {
        guard modelContext != nil else { return }
        let session = WorkSession(startedAt: .now)
        session.taskTitles = tasks.map { $0.task }
        modelContext?.insert(session)
        try? modelContext?.save()
        currentSession = session
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
            if suspicionCount >= 2 {
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
        let countOffTaskFinal = session.justifications.filter { !$0.justified }.count
        let completion = TaskCompletion(
            completedAt: .now, duration: duration, summary: recap.summary,
            steps: recap.steps.isEmpty ? steps : recap.steps,
            offTaskCount: countOffTaskFinal
        )
        ctx.insert(completion)
        kt.completions.append(completion)
        kt.lastCompletedAt = .now
        kt.timesCompleted += 1
        try? ctx.save()
    }

    // MARK: - v3 excuse resolution

    @MainActor
    func handleExcuse(_ text: String, tasks: [TaskItem], screenText: String) async {
        let verdict: ExcuseVerdict
        do {
            verdict = try await aiService.evaluateExcuse(excuse: text, tasks: tasks, screenText: screenText)
        } catch {
            dbg("evaluateExcuse failed: \(error)")
            return
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
