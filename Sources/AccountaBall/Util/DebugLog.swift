import Foundation

/// Lightweight diagnostic logger. Appends to
/// ~/Library/Application Support/AccountaBall/logs/accountaball.log AND stderr
/// so behaviour can be inspected after running the app.
enum DebugLog {
    static let logDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home
            .appendingPathComponent("Library/Application Support/AccountaBall/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var logURL: URL {
        logDirectory.appendingPathComponent("accountaball.log")
    }

    static var rotatedLogURL: URL {
        logDirectory.appendingPathComponent("accountaball.log.1")
    }

    /// 5 MB rotation threshold.
    static let rotationThreshold: Int = 5_000_000

    static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "…"
    }

    static func shouldRotate(sizeBytes: Int) -> Bool {
        sizeBytes > rotationThreshold
    }

    /// Writes a timestamped multi-line block under one dbg call.
    static func dbgBlock(_ title: String, _ lines: [String]) {
        let ts = ISO8601DateFormatter().string(from: .now)
        let header = "\(ts)  \(title)"
        let body = lines.map { "  \($0)" }.joined(separator: "\n")
        dbg("\(header)\n\(body)")
    }
}

/// Appends a timestamped message to the rotated log file (and stderr).
func dbg(_ message: String) {
    NSLog("[AccountaBall] \(message)")
    let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = DebugLog.logURL

    // Rotate if current file exceeds threshold.
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
       let size = attrs[.size] as? Int,
       DebugLog.shouldRotate(sizeBytes: size) {
        let rotated = DebugLog.rotatedLogURL
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }

    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    } else {
        try? data.write(to: url)
    }
}
