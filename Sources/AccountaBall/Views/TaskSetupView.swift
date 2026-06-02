import SwiftUI

struct TaskSetupView: View {
    @EnvironmentObject var state: AppState
    @State private var showValidationError = false

    private let maxRows = 5

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

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

                // Rows
                VStack(spacing: 8) {
                    ForEach(0..<maxRows, id: \.self) { i in
                        TaskRowView(
                            index: i,
                            isUnlocked: isRowUnlocked(i),
                            showError: showValidationError
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Let's go button
                Button("Let's go!") { handleLetsGo() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!hasAtLeastOneCompleteRow)
                    .opacity(hasAtLeastOneCompleteRow ? 1 : 0.4)
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
        withAnimation { state.appPhase = .session }
        state.startSession()
    }
}

struct TaskRowView: View {
    @EnvironmentObject var state: AppState
    let index: Int
    let isUnlocked: Bool
    let showError: Bool

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

    var body: some View {
        HStack(spacing: 12) {
            RowField(text: task, placeholder: "Task \(index + 1)", showError: showError && isUnlocked && taskEmpty)
            RowField(text: context, placeholder: "Context", showError: showError && isUnlocked && contextEmpty)
        }
        .opacity(isUnlocked ? 1 : 0.3)
        .disabled(!isUnlocked)
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
