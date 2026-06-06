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
    @State private var reason = ""          // the model's short reason for the verdict
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

    /// The model's reason for the verdict, surfaced so the user sees *why* —
    /// "Counts as: researching a tool" / "Flagged as: social media".
    private var reasonLabel: String {
        switch stage {
        case .accepted: return "Counts as: \(reason)"
        case .rejected: return "Flagged as: \(reason)"
        case .asking:   return ""
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

            // The model's reason for the verdict (the "why"), shown on the
            // accepted/rejected stages when the model gave one.
            if stage != .asking, !reason.isEmpty {
                Text(reasonLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

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
            } else if stage == .accepted {
                // Justified — acknowledge and resume on the normal settle window.
                Button("Got it") {
                    dbg("accepted verdict dismissed -> resume")
                    engine.resumeAfterExcuse()
                }
                .buttonStyle(PrimaryButtonStyle())
                .transition(.opacity)
            } else {
                // Rejected — nudge back to work, but offer an escape hatch so the
                // user is never trapped. "Back to work" resumes normally;
                // "Give me 2 minutes" grants a grace scoped to *this* activity —
                // switch to something else and AccountaBall checks in again.
                VStack(spacing: 8) {
                    Button("Back to work") {
                        dbg("rejected verdict accepted -> resume (no grace)")
                        engine.resumeAfterExcuse()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Give me 2 minutes") {
                        dbg("rejected verdict overridden -> resume with activity grace")
                        engine.resumeAfterExcuse(graceForCurrentActivity: true)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let verdict = await engine.handleExcuse(
                excuse,
                tasks: state.activeTasks,
                screenText: lastScreenText
            )
            isEvaluating = false
            reason = verdict.rule
            // The engine no longer flips phase on a verdict — it leaves resuming to
            // this view so we can show clear accepted/rejected feedback (with the
            // model's reason) and offer the "Give me 2 minutes" escape hatch. Show
            // the matching stage; the user dismisses it via the buttons above.
            withAnimation { stage = verdict.justified ? .accepted : .rejected }
            dbg("verdict shown (\(verdict.justified ? "accepted" : "rejected"), reason=\"\(verdict.rule)\") — waiting for user to dismiss")
        }
    }
}
