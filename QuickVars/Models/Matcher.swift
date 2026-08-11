import Foundation

/// SPEC.md §9.2 — one function, used by both typed search and voice transcript.
/// No fuzzy/edit-distance matching in V1; aliases carry that load.
enum Matcher {
    struct Match {
        let entry: DecryptedIndexEntry
        /// Higher is better: 3 = exact, 2 = substring, 1 = all-tokens-present.
        let confidence: Int
    }

    private static let stopWords: Set<String> = [
        "whats", "what", "is", "my", "show", "me", "give", "tell",
        "can", "you", "number", "please", "for", "the", "a", "an"
    ]

    static func match(query: String, in items: [DecryptedIndexEntry]) -> [Match] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))

        var results: [Match] = []
        for item in items {
            var best = 0
            for candidate in [item.name] + item.aliases {
                let normalizedCandidate = normalize(candidate)
                guard !normalizedCandidate.isEmpty else { continue }
                if normalizedCandidate == normalizedQuery {
                    best = max(best, 3)
                } else if normalizedCandidate.contains(normalizedQuery) || normalizedQuery.contains(normalizedCandidate) {
                    best = max(best, 2)
                } else {
                    let candidateTokens = Set(normalizedCandidate.split(separator: " ").map(String.init))
                    if queryTokens.isSubset(of: candidateTokens) {
                        best = max(best, 1)
                    }
                }
            }
            if best > 0 {
                results.append(Match(entry: item, confidence: best))
            }
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Strips punctuation/apostrophes and conversational filler words — this is
    /// what turns "Can you give me the VIN for my Audi?" into "vin audi" before
    /// matching starts (source discussion §9.2). Internal, not private: §10's
    /// disambiguation heading ("Which VIN?") reuses this to derive a title.
    static func normalize(_ text: String) -> String {
        let withoutApostrophes = text.replacingOccurrences(of: "'", with: "")
        let tokens = withoutApostrophes
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return tokens.joined(separator: " ")
    }
}
