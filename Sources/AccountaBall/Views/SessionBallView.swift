import SwiftUI

struct SessionBallView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    var onTap: () -> Void
    var onOffTaskDismiss: () -> Void

    @State private var pulsing = false
    @State private var sessionSeconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // One-time allowance confirm-on-reuse prompt takes over the ball.
            if let confirm = state.pendingAllowanceConfirm {
                allowanceConfirmCard(confirm)
            } else {
                ballContent
            }
        }
    }

    private var ballContent: some View {
        ZStack {
            BasketballView(size: 80)

            // Timer overlay
            VStack(spacing: 2) {
                Text(formatTime(sessionSeconds))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                if let idx = state.activeTaskIndex, state.tasks.indices.contains(idx) {
                    Divider().frame(width: 50).overlay(.white.opacity(0.5))
                    Text("Task \(idx + 1)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(formatTime(Int(state.tasks[idx].timeOnTask)))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(pulsing ? 1.05 : 1.0)
        .contentShape(Rectangle())   // make the whole widget area tappable
        .onTapGesture { onTap() }
        .onReceive(timer) { _ in
            sessionSeconds += 1
            // Gentle pulse every 4s
            if sessionSeconds % 4 == 0 {
                withAnimation(.easeInOut(duration: 0.3)) { pulsing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) { pulsing = false }
                }
            }
        }
    }

    @ViewBuilder
    private func allowanceConfirmCard(_ confirm: AllowanceConfirm) -> some View {
        VStack(spacing: 12) {
            BasketballView(size: 56, showFace: .happy)
            Text("Still counts toward “\(confirm.taskTitle)”?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(confirm.rule)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Yes") { engine.confirmPendingAllowance() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("No") { engine.rejectPendingAllowance() }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
        .transition(.opacity)
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
