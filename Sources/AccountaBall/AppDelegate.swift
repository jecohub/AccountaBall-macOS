import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let state = AppState()
    var engine: AccountabilityEngine?
    let notificationService = NotificationService()

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { await notificationService.requestPermission() }

        let env = ProcessInfo.processInfo.environment
        let captureService = ScreenCaptureService()
        let ocrService = OCRService()
        let model = env["OPENROUTER_MODEL"] ?? "anthropic/claude-haiku-4-5"
        let aiService: AIService = OpenRouterAIService(
            apiKey: "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",
            model: model
        )

        // Initialize engine synchronously so it's ready for the SwiftUI hierarchy.
        let eng = AccountabilityEngine(
            state: state,
            captureService: captureService,
            ocrService: ocrService,
            aiService: aiService,
            notificationService: notificationService
        )
        self.engine = eng

        // Watch isCapturing → start/stop the capture loop.
        Task { @MainActor in
            var lastCapturing = false
            while true {
                let capturing = self.state.isCapturing
                if capturing != lastCapturing {
                    lastCapturing = capturing
                    if capturing {
                        self.engine?.start()
                    } else {
                        self.engine?.stop()
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        // Watch phase changes → resize the panel.
        Task { @MainActor in
            var lastPhase: AppPhase = .idle
            while true {
                let phase = self.state.appPhase
                if phase != lastPhase {
                    lastPhase = phase
                    self.panel?.resize(for: phase)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        Task {
            let captureCheck = ScreenCaptureService()
            _ = await captureCheck.requestPermission()
        }

        let panel = FloatingPanel()
        panel.title = "AccountaBall"
        panel.contentView = NSHostingView(
            rootView: RootCoordinatorView(engine: eng, aiService: aiService)
                .environmentObject(state)
        )
        panel.resize(for: .welcome)
        panel.center()
        panel.orderFront(nil)
        self.panel = panel
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false
    }
}
