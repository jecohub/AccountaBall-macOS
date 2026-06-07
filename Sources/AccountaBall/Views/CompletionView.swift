import SwiftUI

struct CompletionView: View {
    @EnvironmentObject var state: AppState
    @State private var animationPhase = 0
    @State private var ballX: CGFloat = 0.8   // fraction of screen width
    @State private var ballY: CGFloat = 0.6
    @State private var ballSize: CGFloat = 40
    @State private var ballRotation: Double = 0
    @State private var showHoop = false
    @State private var netDrop: CGFloat = 0
    @State private var confetti: [ConfettiPiece] = []
    @State private var showSummary = false

    var onRestart: () -> Void
    var onQuit: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Hoop (left side)
                if showHoop {
                    HoopView(netDrop: netDrop)
                        .position(x: geo.size.width * 0.12, y: geo.size.height * 0.4)
                        .transition(.opacity)
                }

                // Confetti
                ForEach(confetti) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size)
                        .position(x: piece.x, y: piece.y)
                        .opacity(piece.opacity)
                }

                // Basketball
                if animationPhase < 3 {
                    BasketballView(size: ballSize)
                        .rotationEffect(.degrees(ballRotation))
                        .position(x: geo.size.width * ballX, y: geo.size.height * ballY)
                }

                // Summary
                if showSummary {
                    VStack(spacing: 24) {
                        Text("🏀")
                            .font(.system(size: 60))
                        Text("Session Complete!")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)

                        VStack(spacing: 8) {
                            StatRow(label: "Total time", value: sessionDuration)
                            StatRow(label: "Tasks finished", value: "\(state.tasks.count) / \(state.tasks.count)")
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // v3.1 — session timeline + per-task commentary
                        if let recap = state.sessionRecap {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Transparency log first — the honest record of every
                                    // check (◐ ambiguous-clarified, ● confirmed drift,
                                    // ○ auto-return) is the first thing the user sees.
                                    // The enumeration index (\.offset on the enumerated
                                    // tuple) is the ForEach id — unique/stable, and NOT
                                    // CheckLogItem.offset (which can collide).
                                    if !recap.checks.isEmpty {
                                        Text("Your checks").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                                        ForEach(Array(recap.checks.enumerated()), id: \.offset) { _, c in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(icon(for: c.kind)).font(.system(size: 12))
                                                Text(String(format: "%02d:%02d", Int(c.offset)/60, Int(c.offset)%60))
                                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                                                    .frame(width: 44, alignment: .leading)
                                                Text("\(c.activity) — \(c.note)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }

                                    // Drift summary line — the pre-commitment made visible.
                                    HStack {
                                        Text("Drift \(recap.driftCount) of \(recap.driftLimit)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(recap.commitmentBroken ? .red.opacity(0.9) : .white.opacity(0.7))
                                        Spacer()
                                    }.padding(.top, 4)

                                    if recap.commitmentBroken {
                                        Text("✕ Commitment broken — you set a limit of \(recap.driftLimit), you hit \(recap.driftCount).")
                                            .font(.system(size: 12)).foregroundStyle(.red.opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    // Per-task commentary first — it's the high-value
                                    // takeaway. The timeline (which can run to many rows)
                                    // follows so it never pushes the comments below the
                                    // fold of this scroll area.
                                    if !recap.perTask.isEmpty {
                                        Text("Per task").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                                        ForEach(Array(recap.perTask.enumerated()), id: \.offset) { _, c in
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(c.taskTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                                Text(c.comment).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                                                if let s = c.suggestion { Text("💡 " + s).font(.system(size: 11)).foregroundStyle(.orange.opacity(0.9)) }
                                            }
                                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                    if !recap.ranges.isEmpty {
                                        Text("Timeline").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                                        ForEach(Array(recap.ranges.enumerated()), id: \.offset) { _, r in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text(String(format: "%02d:%02d", Int(r.startOffset)/60, Int(r.startOffset)%60) + "–" + String(format: "%02d:%02d", Int(r.endOffset)/60, Int(r.endOffset)%60))
                                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                                    .frame(width: 96, alignment: .leading)
                                                Text(r.label + (r.taskIndex == nil ? "  (off-task)" : ""))
                                                    .font(.system(size: 12)).foregroundStyle(r.taskIndex == nil ? .orange.opacity(0.85) : .white.opacity(0.85))
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                        }

                        VStack(spacing: 12) {
                            Button("Start a new session") { onRestart() }
                                .buttonStyle(PrimaryButtonStyle())
                            Button("Quit") { onQuit() }
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(40)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onAppear { runAnimation(in: geo.size) }
        }
    }

    private var sessionDuration: String {
        // Prefer the frozen duration captured at completion (sessionStartTime is
        // nil by now); fall back to a live count only if we're somehow still running.
        let secs: TimeInterval
        if let frozen = state.lastSessionDuration {
            secs = frozen
        } else if let start = state.sessionStartTime {
            secs = Date().timeIntervalSince(start)
        } else {
            return "--:--"
        }
        let s = Int(secs)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    private func icon(for kind: String) -> String {
        switch kind { case "ambiguous": return "◐"; case "auto-return": return "○"; default: return "●" }
    }

    private func runAnimation(in size: CGSize) {
        // Shoot the ball: right side → arc → left hoop
        let duration = 1.2
        withAnimation(.easeOut(duration: 0.2)) { showHoop = true }
        withAnimation(.timingCurve(0.17, 0.67, 0.35, 1.0, duration: duration)) {
            ballX = 0.12; ballY = 0.4; ballSize = 30
        }
        withAnimation(.linear(duration: duration)) { ballRotation = -720 }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Swish
            withAnimation(.easeOut(duration: 0.3)) { netDrop = 20 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring()) { netDrop = 0 }
                // Confetti burst
                confetti = (0..<30).map { _ in
                    ConfettiPiece(
                        x: size.width * 0.12 + CGFloat.random(in: -100...100),
                        y: size.height * 0.4 + CGFloat.random(in: -60...60),
                        color: [.orange, .white, .yellow, .red, .blue].randomElement()!,
                        size: CGFloat.random(in: 6...14),
                        opacity: 1
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.6)) {
                        confetti = confetti.map { var p = $0; p.opacity = 0; return p }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(duration: 0.5)) { showSummary = true }
                    animationPhase = 3
                }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x, y: CGFloat
    var color: Color
    var size: CGFloat
    var opacity: Double
}

struct HoopView: View {
    var netDrop: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // Rim
            Circle()
                .stroke(Color.orange, lineWidth: 4)
                .frame(width: 50, height: 50)

            // Net
            Canvas { ctx, size in
                let netLines = 6
                for i in 0..<netLines {
                    let x = size.width * CGFloat(i) / CGFloat(netLines - 1)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height + netDrop))
                    ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
            }
            .frame(width: 50, height: 30)
            .offset(y: 25)
        }
    }
}

struct StatRow: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.semibold)
        }
    }
}

/// Per-task recap: total time, AI summary, steps, and (if any) a faster/slower
/// comparison vs. the last time this task was completed. Used by the completion
/// summary and the progress panel.
struct RecapCard: View {
    let title: String
    let recap: TaskRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(recap.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !recap.summary.isEmpty {
                Text(recap.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !recap.steps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recap.steps, id: \.self) { step in
                        Text("• \(step)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            if let comparison = recap.comparison, !comparison.isEmpty {
                Text(comparison)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
