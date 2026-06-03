import Foundation

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
        case .onTask(let index, _):
            suspicionCount = 0
            state.activeTaskIndex = index
            state.ballState = .onTask
            if state.tasks.indices.contains(index) {
                state.tasks[index].timeOnTask += 5  // 5s per capture cycle
            }

        case .offTask(_):
            suspicionCount += 1
            state.activeTaskIndex = nil
            dbg("offTask result (suspicion=\(suspicionCount))")
            if suspicionCount >= 2 {
                dbg("ENTER offTask phase")
                state.ballState = .offTask
                state.appPhase = .offTask
                notificationService.sendOffTaskNudge(task: state.activeTasks.first?.task ?? "")
            }

        case .done(let index, _):
            stop()
            state.completeTaskAt(index: index)
        }
    }
}
