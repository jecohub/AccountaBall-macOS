import SwiftUI
import SwiftData

/// Browse past FreeBall sessions. Tap a row to re-open its full recap; export
/// any row to Markdown. Reads straight from the SwiftData store.
@available(macOS 14, *)
struct FreeBallHistoryView: View {
    @EnvironmentObject var state: AppState
    var modelContext: ModelContext
    var onOpen: (FreeBallRecap) -> Void
    var onBack: () -> Void
    @State private var sessions: [FreeBallSession] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Past sessions").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button("back", action: onBack).font(.caption).foregroundStyle(.white.opacity(0.6)).buttonStyle(.plain)
            }
            if sessions.isEmpty {
                Text("No FreeBall sessions yet.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sessions, id: \.id) { s in row(s) }
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
        .onAppear(perform: load)
    }

    @ViewBuilder private func row(_ s: FreeBallSession) -> some View {
        let recap = FreeBallRecap(from: s)
        Button { onOpen(recap) } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLabel(s)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text(s.narrative.isEmpty ? "(not summarized)" : s.narrative)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                Spacer()
                if s.recapPending { Circle().fill(Color.orange).frame(width: 6, height: 6) }
                Button { FreeBallExport.export(recap) } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain).foregroundStyle(.orange)
            }
            .padding(12).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private func dateLabel(_ s: FreeBallSession) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        let mins = Int(((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 60).rounded())
        return "\(df.string(from: s.startedAt)) · \(mins)m"
    }

    private func load() {
        let all = (try? modelContext.fetch(FetchDescriptor<FreeBallSession>())) ?? []
        sessions = all.filter { $0.endedAt != nil }.sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }
}
