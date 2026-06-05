import SwiftUI

struct TaskSetupView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    @State private var showValidationError = false

    private let maxRows = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with mini ball
                HStack {
                    BasketballView(size: 36, showFace: .happy)
                    Text("What are we conquering today?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Column headers
                HStack(spacing: 12) {
                    Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Context").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Rows — scrollable so the inline "you did this before" match cards
                // can expand without pushing the pinned "Let's go!" off-screen.
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<maxRows, id: \.self) { i in
                            TaskRowView(
                                engine: engine,
                                index: i,
                                isUnlocked: isRowUnlocked(i),
                                showError: showValidationError
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)

                // Let's go button — pinned below the scroll area, always reachable.
                Button("Let's go!") { handleLetsGo() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!hasAtLeastOneCompleteRow)
                    .opacity(hasAtLeastOneCompleteRow ? 1 : 0.4)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            // Ensure at least 1 empty row exists
            if state.tasks.isEmpty {
                state.tasks = Array(repeating: TaskItem(), count: maxRows)
            }
        }
    }

    private func isRowUnlocked(_ i: Int) -> Bool {
        if i == 0 { return true }
        return state.tasks.indices.contains(i - 1) && state.tasks[i - 1].isFilledIn
    }

    private var hasAtLeastOneCompleteRow: Bool {
        state.tasks.contains { $0.isFilledIn }
    }

    private func handleLetsGo() {
        // Remove empty rows before saving
        let filled = state.tasks.filter { $0.isFilledIn }
        guard !filled.isEmpty else { showValidationError = true; return }
        state.tasks = filled
        state.saveTasks()
        state.startSession()
        // Open the engine's WorkSession so timeline entries, the completion recap,
        // and completion history actually persist (engine.currentSession drives
        // record()/finalizeSessionRecap()/summarizeCompletion()).
        engine.beginSession(tasks: filled)
        withAnimation { state.appPhase = .session }
    }
}

struct TaskRowView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine
    let index: Int
    let isUnlocked: Bool
    let showError: Bool

    // v3 — cross-session match (Task 17)
    @State private var match: KnowledgeTask?
    @State private var matchDismissed = false
    @State private var showHint = false

    private var task: Binding<String> {
        Binding(
            get: { state.tasks.indices.contains(index) ? state.tasks[index].task : "" },
            set: { if state.tasks.indices.contains(index) { state.tasks[index].task = $0; state.saveTasks() } }
        )
    }

    private var context: Binding<String> {
        Binding(
            get: { state.tasks.indices.contains(index) ? state.tasks[index].context : "" },
            set: { if state.tasks.indices.contains(index) { state.tasks[index].context = $0; state.saveTasks() } }
        )
    }

    private var taskEmpty: Bool { (state.tasks.indices.contains(index) ? state.tasks[index].task : "").isEmpty }
    private var contextEmpty: Bool { (state.tasks.indices.contains(index) ? state.tasks[index].context : "").isEmpty }

    private var taskText: String { state.tasks.indices.contains(index) ? state.tasks[index].task : "" }
    private var contextText: String { state.tasks.indices.contains(index) ? state.tasks[index].context : "" }

    /// Latest completion steps for the matched task — the "how you did it" hint.
    private var matchSteps: [String] {
        match?.completions.sorted { $0.completedAt > $1.completedAt }.first?.steps ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                RowField(text: task, placeholder: "Task \(index + 1)", showError: showError && isUnlocked && taskEmpty)
                RowField(text: context, placeholder: "Context", showError: showError && isUnlocked && contextEmpty)
            }
            if let match { matchCard(match) }
        }
        .opacity(isUnlocked ? 1 : 0.3)
        .disabled(!isUnlocked)
        // Debounced cross-session lookup: re-runs (and cancels prior) whenever the
        // task/context text changes; `.task` gives us free cancellation.
        .task(id: "\(taskText)|\(contextText)") {
            guard isUnlocked, !taskEmpty, !contextEmpty, !matchDismissed else {
                match = nil; return
            }
            try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms debounce
            guard !Task.isCancelled else { return }
            match = await engine.proposeMatch(for: taskText)
            showHint = false
        }
    }

    @ViewBuilder
    private func matchCard(_ kt: KnowledgeTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Looks like “\(kt.originalTitles.last ?? kt.normalizedTitle)” — a task you finished before. Bring back what you learned?")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Yes") {
                    Task {
                        await engine.linkKnowledgeTask(kt, to: index)
                        matchDismissed = true
                        match = nil
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("No, fresh task") {
                    matchDismissed = true
                    match = nil
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)
            }

            if !matchSteps.isEmpty {
                Button {
                    withAnimation { showHint.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showHint ? "chevron.down" : "chevron.right")
                        Text("Here's how you did it last time")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.9))
                }
                .buttonStyle(.plain)

                if showHint {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(matchSteps, id: \.self) { step in
                            Text("• \(step)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.leading, 14)
                    .transition(.opacity)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

struct RowField: View {
    @Binding var text: String
    let placeholder: String
    let showError: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showError ? Color.red.opacity(0.7) : Color.clear, lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity)
    }
}
