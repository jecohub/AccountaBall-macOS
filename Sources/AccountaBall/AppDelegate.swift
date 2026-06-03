import AppKit
import SwiftUI
import SwiftData

public class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let state = AppState()
    var engine: AccountabilityEngine?
    let notificationService = NotificationService()
    var modelContainer: ModelContainer?

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { await notificationService.requestPermission() }

        let env = ProcessInfo.processInfo.environment
        let captureService = ScreenCaptureService()
        let ocrService = OCRService()

        // AI provider factory — env-driven. See design Section 7.
        // No auto-fallback: if the requested provider is misconfigured, we set
        // `setupHint` and construct the local Ollama service so the app at
        // least launches and the user sees the hint. The view in Task 17 will
        // surface `setupHint` to the user.
        let provider = env["AI_PROVIDER"] ?? "ollama"
        let aiService: AIService = {
            switch provider {
            case "openrouter":
                guard let key = env["OPENROUTER_API_KEY"] else {
                    dbg("FATAL: OPENROUTER_API_KEY not set")
                    state.setupHint = "Set OPENROUTER_API_KEY, or run with AI_PROVIDER=ollama"
                    return OllamaAIService()
                }
                let model = env["OPENROUTER_MODEL"] ?? "anthropic/claude-haiku-4-5"
                return OpenRouterAIService(apiKey: key, model: model)
            default:
                let host = env["OLLAMA_HOST"] ?? "http://localhost:11434"
                let model = env["OLLAMA_MODEL"] ?? "qwen2.5:7b"
                return OllamaAIService(host: host, model: model)
            }
        }()

        // v3 — SwiftData container for WorkSession / TimelineEntry persistence.
        // Hard-fail on disk failure so we don't silently lose the session log.
        let container: ModelContainer
        do {
            container = try AccountaBallStore.makeContainer()
        } catch {
            fatalError("AccountaBall: failed to build ModelContainer: \(error)")
        }
        self.modelContainer = container

        // Initialize engine synchronously so it's ready for the SwiftUI hierarchy.
        let eng = AccountabilityEngine(
            state: state,
            captureService: captureService,
            ocrService: ocrService,
            aiService: aiService,
            notificationService: notificationService
        )
        eng.modelContext = container.mainContext
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
