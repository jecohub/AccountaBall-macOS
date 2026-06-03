import Foundation

enum TaskMatcher {
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = lowered.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        let collapsed = stripped.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return collapsed
    }

    /// Returns the candidate id whose normalized title (or any normalized original) equals
    /// the normalized query. nil if none — caller then tries the AI semantic match.
    static func cheapMatch(_ query: String,
                           in candidates: [(id: String, normalized: String, originals: [String])]) -> String? {
        let q = normalize(query)
        for c in candidates {
            if c.normalized == q { return c.id }
            if c.originals.map(normalize).contains(q) { return c.id }
        }
        return nil
    }
}
