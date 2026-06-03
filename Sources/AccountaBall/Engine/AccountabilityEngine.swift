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
        }
    }
}
