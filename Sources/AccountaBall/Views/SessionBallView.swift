import SwiftUI

struct SessionBallView: View {
    @EnvironmentObject var state: AppState
    var onTap: () -> Void
    var onOffTaskDismiss: () -> Void

    @State private var yOffset: CGFloat = 100
    @State private var pulsing = false
    @State private var sessionSeconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Basketball (half off screen to the right)
            HStack {
                Spacer()
                ZStack {
                    BasketballView(size: 80)

                    // Timer overlay on visible half
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
                    .frame(width: 50)
                }
                .frame(width: 80)
                .offset(x: 40)  // half off screen
                .offset(y: yOffset)
                .scaleEffect(pulsing ? 1.05 : 1.0)
                .onTapGesture { onTap() }
                .gesture(DragGesture().onChanged { v in yOffset += v.translation.height })
            }
        }
        .ignoresSafeArea()
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

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
