import Foundation

/// Decide whether two consecutive OCR reads show effectively the same screen.
/// At a 3s cadence, adjacent cycles are usually near-identical (same window,
/// only a clock/cursor differs). Treating those as one block keeps the stored
/// transcript honest ("full text, full session") without thousands of dupes.
enum FreeBallDedup {
    /// Jaccard similarity over lowercased word sets. 1.0 = identical sets, 0 = disjoint.
    static func similarity(_ a: String, _ b: String) -> Double {
        let sa = Set(tokens(a)), sb = Set(tokens(b))
        if sa.isEmpty && sb.isEmpty { return 1.0 }
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    static func isSameScreen(_ a: String, _ b: String, threshold: Double = AppConstants.freeBallDedupThreshold) -> Bool {
        similarity(a, b) >= threshold
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
