import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showInput = false

    var body: some View {
        VStack(spacing: 6) {
            BallView(state: state.ballState)
                .onTapGesture {
                    if state.ballState == .idle || state.ballState == .onTask {
                        withAnimation(.spring(duration: 0.3)) {
                            showInput.toggle()
                        }
                    }
                }

            if showInput || state.ballState == .idle {
                TaskInputView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(8)
        .onChange(of: state.ballState) { _, newState in
            if newState == .onTask {
                withAnimation { showInput = false }
            }
        }
    }
}
