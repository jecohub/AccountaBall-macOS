import SwiftUI

struct RootCoordinatorView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService

    @State private var showWhatsUp = false

    var body: some View {
        ZStack {
            switch state.appPhase {
            case .idle, .welcome:
                WelcomeView()
                    .transition(.opacity)

            case .setup:
                TaskSetupView()
                    .transition(.opacity)

            case .session:
                SessionBallView(
                    onTap: { withAnimation { showWhatsUp = true } },
                    onOffTaskDismiss: {}
                )
                .transition(.opacity)
                .overlay {
                    if showWhatsUp {
                        WhatsUpView(onDismiss: { withAnimation { showWhatsUp = false } })
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

            case .offTask:
                SessionBallView(onTap: {}, onOffTaskDismiss: {})
                    .overlay(alignment: .trailing) {
                        OffTaskView(
                            engine: engine,
                            aiService: aiService,
                            lastScreenText: engine.lastScreenText
                        )
                        .transition(.opacity)
                    }

            case .progress:
                AccountaProgressView(onBack: { withAnimation { state.appPhase = .session } })
                    .transition(.opacity)

            case .complete:
                CompletionView(
                    onRestart: {
                        state.loadTasks()
                        withAnimation { state.appPhase = .welcome }
                    },
                    onQuit: { NSApp.terminate(nil) }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.appPhase)
        .onAppear {
            if state.appPhase == .idle {
                state.loadTasks()
                withAnimation { state.appPhase = .welcome }
            }
        }
    }
}
