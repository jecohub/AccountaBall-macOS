import SwiftUI

struct OffTaskView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService
    var lastScreenText: String

    @State private var slideIn: CGFloat = 0   // 0=edge, 1=1/3 in
    @State private var rotated = false
    @State private var excuseText = ""
    @State private var message: String? = nil
    @State private var isEvaluating = false
    @State private var timeoutTask: Task<Void, Never>? = nil

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                // Speech bubble
                if let msg = message {
                    SpeechBubble(text: msg)
                        .padding(.trailing, 90)
                        .transition(.opacity)
                } else {
                    SpeechBubble(text: "What are you doing?")
                        .padding(.trailing, 90)
                }

                // Ball with rotation (timer back → angry face front)
                BasketballView(size: 80, showFace: rotated ? .angry : .none)
                    .rotation3DEffect(.degrees(rotated ? 0 : 180), axis: (0, 1, 0))
                    .padding(.trailing, 40 - (slideIn * 100))

                // Input
                if rotated && message == nil {
                    VStack(spacing: 8) {
                        TextField("What are you doing?", text: $excuseText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(width: 220)
                            .onSubmit { submitExcuse() }

                        Button(isEvaluating ? "Checking..." : "Submit") { submitExcuse() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(excuseText.isEmpty || isEvaluating)
                    }
                    .padding(.trailing, 50)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { startCreep() }
    }

    private func startCreep() {
        // Start 60s timeout
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard state.appPhase == .offTask else { return }
            engine.resumeAfterExcuse()
        }
        // Animate rotation then slide in
        withAnimation(.easeInOut(duration: 0.6)) { rotated = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 1.5)) { slideIn = 1 }
        }
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
            if justified {
                engine.resumeAfterExcuse()
            } else {
                // Slide back but keep angry for one cycle
                withAnimation(.easeInOut(duration: 0.8)) { slideIn = 0 }
                try? await Task.sleep(for: .seconds(0.8))
                engine.resumeAfterExcuse()
            }
        }
    }
}
