import SwiftUI

struct RootCoordinatorView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService

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
                // Tapping the edge ball opens the progress panel (the widget is
                // too small to host a centered overlay).
                SessionBallView(
                    onTap: { withAnimation { state.appPhase = .progress } },
                    onOffTaskDismiss: {}
                )
                .transition(.opacity)

            case .offTask:
                OffTaskView(
                    engine: engine,
                    aiService: aiService,
                    lastScreenText: engine.lastScreenText
                )
                .transition(.opacity)

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
