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
            } else {
                // Verdict shown — the user dismisses it themselves.
                Button("Got it") {
                    dbg("verdict dismissed by user -> resume")
                    engine.resumeAfterExcuse()
                }
                .buttonStyle(PrimaryButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.88))
        .onAppear { startWindow() }
    }

    /// (Re)start the 2-minute response window. Runs fresh every time the prompt appears.
    private func startWindow() {
        dbg("offtask prompt appeared (activeTasks=\(state.activeTasks.count), screenTextLen=\(lastScreenText.count))")
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: responseWindow)
            } catch {
                return  // cancelled (e.g. the user submitted) — do NOT resume
            }
            guard !Task.isCancelled, state.appPhase == .offTask else { return }
            dbg("offtask 2-min timeout fired -> resume")
            engine.resumeAfterExcuse()
        }
    }

    private func submitExcuse() {
        guard !excuseText.isEmpty, !isEvaluating else {
            dbg("submit ignored (empty=\(excuseText.isEmpty), evaluating=\(isEvaluating))")
            return
        }
        let excuse = excuseText
        timeoutTask?.cancel()
        isEvaluating = true
        dbg("excuse submitted: \(excuse)")
        Task { @MainActor in
            // Route through the engine so the JustificationEvent is persisted and,
            // when justified, an Allowance + KnowledgeTask link is created.
            let justified = await engine.handleExcuse(
                excuse,
                tasks: state.activeTasks,
                screenText: lastScreenText
            )
            dbg("excuse verdict: \(justified ? "JUSTIFIED" : "NOT_JUSTIFIED")")
            isEvaluating = false
            // On justified, the engine already resumed (phase -> .session) and this
            // view is dismissed. On not-justified, show the angry verdict; the user
            // dismisses it with "Got it".
            if !justified {
                withAnimation { stage = .rejected }
                dbg("verdict shown (rejected) — waiting for user to dismiss")
            }
        }
    }
}
