import SwiftUI

/// The calm one-time AMBIGUOUS check card. When classification can't decide
/// whether the current activity is part of the declared task, AccountaBall asks
/// once — mirror, not boss. "Yes" creates an allowance and resumes; "No" logs a
/// confirmed drift and shows the OFF card. Tone is calm, no exclamation marks.
struct AmbiguousAskView: View {
    @EnvironmentObject var state: AppState
    var engine: AccountabilityEngine

    @State private var reason = ""

    private var taskLabel: String { state.activeTasks.first?.task ?? "your task" }

    var body: some View {
        VStack(spacing: 14) {
            SpeechBubble(text: "Quick check — is this part of \(taskLabel)?")

            // Basketball with a thinking face — calm, not judgemental.
            ZStack {
                BasketballView(size: 72)
                Text("🤔")
                    .font(.system(size: 34))
            }

            TextField("what's it for? (optional)", text: $reason)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
                .onSubmit { engine.acceptAmbiguous(reason: reason) }

            VStack(spacing: 8) {
                Button("Yes, it's related") {
                    dbg("ambiguous accepted (reason=\"\(reason)\")")
                    engine.acceptAmbiguous(reason: reason)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("No, I drifted") {
                    dbg("ambiguous rejected -> confirmed drift")
                    engine.rejectAmbiguous()
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
