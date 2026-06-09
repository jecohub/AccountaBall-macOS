import Foundation
import AppKit

/// Write a FreeBall recap to ~/Documents/AccountaBall/FreeBall/<file>.md and
/// reveal it in Finder. The folder becomes a browsable, grep-able archive.
enum FreeBallExport {
    static func filename(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmm"
        return "freeball-\(df.string(from: date)).md"
    }

    /// Returns the written file URL, or nil on failure.
    @discardableResult
    static func export(_ recap: FreeBallRecap) -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("AccountaBall/FreeBall", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename(for: recap.date))
        do {
            try FreeBallMarkdown.render(recap: recap).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return url
        } catch { return nil }
    }
}
