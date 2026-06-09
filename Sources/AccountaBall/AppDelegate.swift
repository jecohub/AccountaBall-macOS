import AppKit
import SwiftUI
import SwiftData

public class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let state = AppState()
    var engine: AccountabilityEngine?
    var freeBallEngine: FreeBallEngine?
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

        let freeBallEngine = FreeBallEngine(
            state: state,
            captureService: captureService,
            ocrService: ocrService,
            aiService: aiService
        )
        freeBallEngine.modelContext = container.mainContext
        self.freeBallEngine = freeBallEngine

        // Load the pre-committed drift limit at launch (beside the task load that
        // RootCoordinatorView triggers on appear), so the engine's
        // commitmentBroken trigger reads the user's setup value from the start.
        state.loadDriftLimit()

        // A FreeBall session with no endedAt was interrupted (quit/crash). Close it
        // silently and mark it recap-pending so its raw captures aren't lost and it
        // doesn't look "live" forever.
        Task { @MainActor in
            let ctx = container.mainContext
            let dangling = (try? ctx.fetch(FetchDescriptor<FreeBallSession>())) ?? []
            for s in dangling where s.endedAt == nil {
                s.endedAt = .now
                s.recapPending = true
            }
            try? ctx.save()
        }

        // Startup AI reachability probe — if the provider is unreachable at
        // launch, show the AI-unavailable card immediately rather than waiting
        // for the first failed classify cycle (~5s into a session).
        Task { @MainActor in
            if await aiService.healthCheck() == false { eng.enterAIUnavailable() }
        }

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

        // Watch phase changes → resize the panel, and build the end-of-session
        // recap once when we reach `.complete` (covers both the AI `.done` path
        // and the manual progress-panel checkoff). The flag prevents a
        // double-build while we linger on the completion screen; it resets when
        // we leave `.complete` so the next session finalizes too.
        Task { @MainActor in
            var lastPhase: AppPhase = .idle
            var lastConfirm = false
            var didFinalize = false
            while true {
                let phase = self.state.appPhase
                // The allowance "still counts?" card is a sub-state of `.session`
                // (not its own phase) and renders only there — it needs a bigger
                // panel than the tiny session widget. Gate on `.session` so the
                // pending confirm (which is set back in `.setup`) doesn't resize
                // the setup panel before the card is actually shown.
                let showConfirm = self.state.pendingAllowanceConfirm != nil && phase == .session
                if phase != lastPhase || showConfirm != lastConfirm {
                    if showConfirm {
                        self.panel?.resizeForAllowanceConfirm()
                    } else {
                        self.panel?.resize(for: phase)
                    }
                    lastConfirm = showConfirm
                }
                if phase != lastPhase {
                    lastPhase = phase
                    if phase == .complete {
                        if !didFinalize {
                            didFinalize = true
                            // Build the recap from the still-open WorkSession, THEN
                            // close it (endSession nils currentSession).
                            await self.engine?.finalizeSessionRecap()
                            self.engine?.endSession()
                        }
                    } else {
                        didFinalize = false
                    }
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
            rootView: RootCoordinatorView(engine: eng, freeBallEngine: freeBallEngine, aiService: aiService)
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
