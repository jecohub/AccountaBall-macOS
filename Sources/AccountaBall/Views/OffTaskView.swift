import SwiftUI

struct OffTaskView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService
    var lastScreenText: String

    private enum Stage { case asking, accepted, rejected }

    @State private var stage: Stage = .asking
    @State private var excuseText = ""
    @State private var isEvaluating = false
    @State private var timeoutTask: Task<Void, Never>? = nil

    // 2-minute window to respond before AccountaBall gives up and minimizes.
    private let responseWindow: Duration = .seconds(120)

    private var bubbleText: String {
        switch stage {
        case .asking:   return "What are you doing?"
        case .accepted: return "Carry on"
        case .rejected: return "You should get back to your tasks"
        }
    }

    private var moodEmoji: String {
        switch stage {
        case .asking:   return "🤨"   // judgemental
        case .accepted: return "👍"
        case .rejected: return "😠"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SpeechBubble(text: bubbleText)
                .transition(.opacity)

            // Basketball with a mood emoji as its face.
            ZStack {
                BasketballView(size: 80)
                Text(moodEmoji)
                    .font(.system(size: 38))
            }
            .transition(.opacity)

            // Excuse input — only while asking.
            if stage == .asking {
                VStack(spacing: 8) {
                    TextField("Type what you're doing…", text: $excuseText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                        .onSubmit { submitExcuse() }

                    Button(isEvaluating ? "Checking…" : "Submit") { submitExcuse() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(excuseText.isEmpty || isEvaluating)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .onAppear { startWindow() }
    }

    /// (Re)start the 2-minute response window. Runs fresh every time the prompt appears.
    private func startWindow() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: responseWindow)
            guard state.appPhase == .offTask else { return }
            engine.resumeAfterExcuse()
        }
    }

    private func submitExcuse() {
        guard !excuseText.isEmpty, !isEvaluating else { return }
        timeoutTask?.cancel()
        isEvaluating = true
        Task { @MainActor in
            let justified = (try? await aiService.evaluateExcuse(
                excuse: excuseText,
                tasks: state.activeTasks,
                screenText: lastScreenText
            )) ?? false
            isEvaluating = false
            withAnimation { stage = justified ? .accepted : .rejected }
            // Hold the verdict on screen briefly, then minimize back to the edge ball.
            try? await Task.sleep(for: .seconds(2))
            engine.resumeAfterExcuse()
        }
    }
}
