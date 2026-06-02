import Foundation

/// Lightweight diagnostic logger. Appends to /tmp/accountaball.log AND stderr
/// so behaviour can be inspected after running the app.
func dbg(_ message: String) {
    NSLog("[AccountaBall] \(message)")
    let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/accountaball.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    } else {
        try? data.write(to: url)
    }
}
