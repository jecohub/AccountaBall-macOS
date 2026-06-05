import SwiftUI

struct AIUnavailableView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            BasketballView(size: 64, showFace: .angry)

            Text("AI unavailable")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            if let hint = state.aiUnavailableHint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Can't reach the AI provider.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text("Retrying automatically…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
