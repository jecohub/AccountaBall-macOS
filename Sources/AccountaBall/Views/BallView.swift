import SwiftUI

struct BallView: View {
    let state: BallState
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(ballColor)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            HStack(spacing: 12) {
                Circle().fill(.white).frame(width: eyeSize, height: eyeSize)
                Circle().fill(.white).frame(width: eyeSize, height: eyeSize)
            }
            .offset(y: -10)

            mouthView
                .offset(y: 12)
        }
        .scaleEffect(isPulsing ? 1.08 : 1.0)
        .onChange(of: state) { _, newState in
            withAnimation(
                newState == .offTask
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default
            ) {
                isPulsing = newState == .offTask
            }
        }
    }

    private var ballColor: Color {
        switch state {
        case .idle:    return .gray.opacity(0.6)
        case .onTask:  return .green
        case .offTask: return .orange
        case .done:    return .yellow
        }
    }

    private var eyeSize: CGFloat { state == .offTask ? 9 : 7 }

    private var mouthView: some View {
        let w: CGFloat = state == .done ? 28 : 20
        let h: CGFloat = state == .done ? 14 : 10
        let clockwise = state == .offTask
        let lineWidth: CGFloat = state == .done ? 3 : 2
        return Path { path in
            path.addArc(
                center: CGPoint(x: w / 2, y: h / 2),
                radius: w / 2,
                startAngle: .degrees(0),
                endAngle: .degrees(180),
                clockwise: clockwise
            )
        }
        .stroke(.white, lineWidth: lineWidth)
        .frame(width: w, height: h)
    }
}
