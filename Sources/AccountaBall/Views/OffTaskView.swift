import SwiftUI

struct OffTaskView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var aiService: AIService          // kept for coordinator call-site stability
    var lastScreenText: String        // kept for coordinator call-site stability

    @State private var timeoutTask: Task<Void, Never>? = nil

    // 2-minute window to respond before AccountaBall gives up and minimizes.
    private let responseWindow: Duration = .seconds(120)

    private var taskLabel: String { state.activeTasks.first?.task ?? "your task" }

    var body: some View {
        VStack(spacing: 14) {
            SpeechBubble(text: "You've drifted from \(taskLabel).")

            // Basketball with a calm "drifting" face — a mirror, not a scold.
            ZStack {
                BasketballView(size: 80)
                Text("🌀")
                    .font(.system(size: 36))
            }

            VStack(spacing: 8) {
                Button("Take a timed 5-min break") {
                    dbg("offtask -> take a timed break")
                    timeoutTask?.cancel()
                    engine.takeBreak()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Jump back in") {
                    dbg("offtask -> jump back in")
                    timeoutTask?.cancel()
                    engine.resumeAfterExcuse()
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.plain)
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
                return  // cancelled (e.g. the user chose) — do NOT resume
            }
            guard !Task.isCancelled, state.appPhase == .offTask else { return }
            dbg("offtask 2-min timeout fired -> resume")
            // TASK 10 will replace this with engine.autoReturnFromPrompt() (logs an
            // auto-return row). For now, resume so the build compiles and the timeout works.
            engine.resumeAfterExcuse()
        }
    }
}
