import SwiftUI

struct WhatsUpView: View {
    var onShowLog: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            SpeechBubble(text: "What's up?")
            BasketballView(size: 80, showFace: .happy)

            VStack(spacing: 10) {
                Button("Session log") { onShowLog() }
                    .buttonStyle(PrimaryButtonStyle())

                Button("Nothing") { onDismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}

struct AccountaProgressView: View {
    @EnvironmentObject var state: AppState
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // Session timer
                HStack {
                    Image(systemName: "timer")
                    Text("Session time")
                    Spacer()
                    Text(sessionDuration)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                }
                .foregroundStyle(.white)

                Divider().overlay(.white.opacity(0.2))

                // Task list
                HStack {
                    Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Time").frame(width: 80, alignment: .trailing)
                    Text("Done").frame(width: 44, alignment: .center)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

                ForEach(state.tasks.indices, id: \.self) { i in
                    let task = state.tasks[i]
                    VStack(spacing: 6) {
                        HStack {
                            Text(task.task)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .strikethrough(task.isComplete)
                                .foregroundStyle(task.isComplete ? .white.opacity(0.3) : .white)

                            Text(formatTime(Int(task.timeOnTask)))
                                .frame(width: 80, alignment: .trailing)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))

                            Button {
                                state.completeTaskAt(index: i)
                            } label: {
                                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isComplete ? .orange : .white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44)
                        }

                        if task.isComplete, let recap = state.recaps[task.task] {
                            RecapCard(title: task.task, recap: recap)
                        }
                    }
                }

                Spacer()
                Button("Back to work") { onBack() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private var sessionDuration: String {
        guard let start = state.sessionStartTime else { return "00:00" }
        return formatTime(Int(Date().timeIntervalSince(start)))
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
