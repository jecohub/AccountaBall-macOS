import SwiftUI

struct AIUnavailableView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // A compact, fixed-width rounded card that hugs its content and floats
        // centered in the (transparent) panel — not a full-bleed black slab.
        VStack(spacing: 14) {
            BasketballView(size: 64, showFace: .angry)

            Text("AI unavailable")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text(state.aiUnavailableHint ?? "Can't reach the AI provider.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text("Retrying automatically…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
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
