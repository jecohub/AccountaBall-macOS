import SwiftUI

struct TaskInputView: View {
    @EnvironmentObject var state: AppState
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("What are you working on?", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit { submit() }

            if !inputText.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 220)
        .onAppear { isFocused = true }
    }

    private func submit() {
        state.submitTask(inputText)
        inputText = ""
    }
}
