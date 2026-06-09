import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    var freeBallEngine: FreeBallEngine
    @State private var bouncePhase = 0
    @State private var showContent = false
    @State private var ballY: CGFloat = -150
    @State private var squish: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack(alignment: .top) {
                    if showContent {
                        SpeechBubble(text: "Ready to finish your tasks?")
                            .offset(y: -90)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    BasketballView(size: 80, showFace: .happy)
                        .scaleEffect(x: squish > 1 ? squish : 1, y: squish < 1 ? squish : 1)
                        .offset(y: ballY)
                        .onAppear { runBounce() }
                }
                .frame(height: 200)

                if showContent {
                    VStack(spacing: 12) {
                        if !state.tasks.isEmpty {
                            Text("Welcome back — you have \(state.tasks.count) task\(state.tasks.count == 1 ? "" : "s") from last time")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))

                            Button("start fresh") { state.clearSavedTasks() }
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .buttonStyle(.plain)
                        }

                        Button("Let's get started") {
                            withAnimation { state.appPhase = .setup }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("FreeBall") {
                            freeBallEngine.begin()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
            }
            .padding(32)
        }
    }

    private func runBounce() {
        // Phase 1: drop from top
        withAnimation(.easeIn(duration: 0.3)) { ballY = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.05)) { squish = 0.7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeIn(duration: 0.05)) { squish = 1.0 }
                // Phase 2: bounce up 60%
                withAnimation(.easeOut(duration: 0.25)) { ballY = -90 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeIn(duration: 0.2)) { ballY = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.easeOut(duration: 0.05)) { squish = 0.8 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeIn(duration: 0.05)) { squish = 1.0 }
                            // Phase 3: small bounce 30%
                            withAnimation(.easeOut(duration: 0.18)) { ballY = -45 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                withAnimation(.spring(duration: 0.15, bounce: 0.3)) { ballY = 0 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.spring(duration: 0.4)) { showContent = true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            // Pointer triangle pointing down
            Triangle()
                .fill(Color.white)
                .frame(width: 16, height: 8)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
