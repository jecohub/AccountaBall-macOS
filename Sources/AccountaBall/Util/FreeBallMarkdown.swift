import Foundation

/// Render a FreeBallRecap to a self-contained Markdown document. Sections with no
/// items are omitted. Pure + unit-tested; used by the export action.
enum FreeBallMarkdown {
    static func render(recap r: FreeBallRecap) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        let mins = Int((r.duration / 60).rounded())
        var out = "# FreeBall — \(df.string(from: r.date))\n\n_\(mins)m session_\n"
        if !r.narrative.isEmpty { out += "\n\(r.narrative)\n" }
        if !r.categories.isEmpty {
            out += "\n## Time\n"
            for c in r.categories.sorted(by: { $0.minutes > $1.minutes }) { out += "- \(c.label): \(c.minutes)m\n" }
        }
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            out += "\n## \(title)\n"
            for i in items { out += "- \(i)\n" }
        }
        section("Working on", r.workingOn)
        section("People & conversations", r.people)
        section("Code context", r.codeContext)
        section("Open threads", r.openThreads)
        if !r.insight.isEmpty { out += "\n## Insight\n\(r.insight)\n" }
        return out
    }
}
