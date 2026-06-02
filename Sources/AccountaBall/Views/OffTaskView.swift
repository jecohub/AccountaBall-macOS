import SwiftUI

struct OffTaskView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService
    var lastScreenText: String

    @State private var rotated = false
    @State private var excuseText = ""
    @State private var message: String? = nil
    @State private var isEvaluating = false
    @State private var timeoutTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 14) {
            // Speech bubble
            SpeechBubble(text: message ?? "What are you doing?")
                .transition(.opacity)

            // Ball flips from timer-back to angry-face-front
            BasketballView(size: 80, showFace: rotated ? .angry : .none)
                .rotation3DEffect(.degrees(rotated ? 0 : 180), axis: (0, 1, 0))

            // Excuse input
            if rotated && message == nil {
                VStack(spacing: 8) {
                    TextField("What are you doing?", text: $excuseText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                        .onSubmit { submitExcuse() }

                    Button(isEvaluating ? "Checking..." : "Submit") { submitExcuse() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(excuseText.isEmpty || isEvaluating)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .onAppear { startCreep() }
    }

    private func startCreep() {
        // Start 60s timeout — if ignored, resume the session automatically.
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard state.appPhase == .offTask else { return }
            engine.resumeAfterExcuse()
        }
        // Flip the ball around to reveal the angry face.
        withAnimation(.easeInOut(duration: 0.6)) { rotated = true }
    }

    private func submitExcuse() {
        guard !excuseText.isEmpty else { return }
        timeoutTask?.cancel()
        isEvaluating = true
        Task { @MainActor in
            let justified = (try? await aiService.evaluateExcuse(
                excuse: excuseText,
                tasks: state.activeTasks,
                screenText: lastScreenText
            )) ?? false
            withAnimation {
                message = justified ? "Okay, carry on 👍" : "Get back to work."
            }
            try? await Task.sleep(for: .seconds(2))
            engine.resumeAfterExcuse()
        }
    }
}
