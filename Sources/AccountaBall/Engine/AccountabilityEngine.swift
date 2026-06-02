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
        captureTask = captureService.startLoop(
            interval: 5,
            panelTitle: "AccountaBall"
        ) { [weak self] image in
            guard let self else { return }
            let text = await self.ocrService.extractText(from: image)
            guard !text.isEmpty else { return }
            let result = (try? await self.aiService.classify(
                task: self.state.currentTask,
                screenText: text
            )) ?? .onTask
            await self.processAIResult(result)
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        suspicionCount = 0
    }

    func processAIResult(_ result: BallState) {
        switch result {
        case .onTask:
            suspicionCount = 0
            if state.ballState == .offTask {
                state.ballState = .onTask
            }
        case .offTask:
            suspicionCount += 1
            if suspicionCount >= 2 {
                state.ballState = .offTask
                notificationService.sendOffTaskNudge(task: state.currentTask)
            }
        case .done:
            stop()
            if let idx = state.tasks.firstIndex(where: { !$0.isComplete }) {
                state.completeTaskAt(index: idx)
            } else {
                state.endSession()
                state.appPhase = .complete
            }
        case .idle:
            break
        }
    }
}
