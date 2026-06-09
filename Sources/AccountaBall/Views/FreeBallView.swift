import SwiftUI

/// Collapsed calm ball during a FreeBall session. Tapping opens the live log.
struct FreeBallBallView: View {
    @EnvironmentObject var state: AppState
    @State private var seconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            BasketballView(size: 80, showFace: .calm)
            Text(elapsed)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .offset(y: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { state.appPhase = .freeBallLog } }
        .onReceive(timer) { _ in seconds += 1 }
    }

    private var elapsed: String { formatElapsed(since: state.freeBallStartTime) }
}

/// Live session log: timer + End Session. No content shown (nothing analyzed yet).
struct FreeBallSessionView: View {
    @EnvironmentObject var state: AppState
    var engine: FreeBallEngine
    @State private var seconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            BasketballView(size: 56, showFace: .calm)
            Text(formatElapsed(since: state.freeBallStartTime))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .onReceive(timer) { _ in seconds += 1 }
            Text("watching…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Button("End Session") {
                Task { await engine.end() }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("back") { withAnimation { state.appPhase = .freeBall } }
                .font(.caption).foregroundStyle(.white.opacity(0.6)).buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// Post-session recap: narrative + categorized breakdown + insight.
struct FreeBallRecapView: View {
    @EnvironmentObject var state: AppState
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if state.freeBallSummarizing {
                VStack(spacing: 12) {
                    BasketballView(size: 56, showFace: .calm)
                    Text("making sense of your session…")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                }
            } else if let recap = state.freeBallRecap {
                content(recap)
            }
        }
    }

    @ViewBuilder private func content(_ recap: FreeBallRecap) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Here's where your time went")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text(formatElapsed(seconds: Int(recap.duration)))
                    .font(.caption).foregroundStyle(.white.opacity(0.5))

                if recap.recapPending {
                    Text("Couldn't reach the AI to summarize — your session was saved and can be summarized later.")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                } else {
                    if !recap.narrative.isEmpty {
                        Text(recap.narrative)
                            .font(.system(size: 14)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !recap.categories.isEmpty {
                        breakdown(recap.categories)
                    }
                    if !recap.insight.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("what FreeBall noticed").font(.caption).foregroundStyle(.white.opacity(0.5))
                            Text(recap.insight).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    contextSection("Working on", recap.workingOn)
                    contextSection("People & conversations", recap.people)
                    contextSection("Code context", recap.codeContext)
                    contextSection("Open threads / next steps", recap.openThreads)
                }

                HStack {
                    Button("Export") { FreeBallExport.export(recap) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Done", action: onDone)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder private func contextSection(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.white.opacity(0.5))
                ForEach(items, id: \.self) {
                    Text("• \($0)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func breakdown(_ cats: [CategorySpan]) -> some View {
        let sorted = cats.sorted { $0.minutes > $1.minutes }
        let maxMin = max(sorted.first?.minutes ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, c in
                HStack {
                    Text(c.label).font(.system(size: 13)).foregroundStyle(.white).frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(c.minutes) / CGFloat(maxMin))
                    }
                    .frame(height: 12)
                    Text("\(c.minutes)m").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - shared formatting

func formatElapsed(seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
func formatElapsed(since start: Date?) -> String {
    guard let start else { return "00:00" }
    return formatElapsed(seconds: Int(Date().timeIntervalSince(start)))
}
