import Foundation

/// The user's personal dictionary — names, brand terms, jargon GrammarGem should
/// never "correct". Feeds Harper's ignore-list and the LLM context. Capped at 25
/// entries on free, unlimited on paid (enforced by `FeatureGate`, not here).
@MainActor
final class PersonalDictionary: ObservableObject {
    @Published private(set) var entries: [String]

    private let key = "GrammarGem.personalDictionary"
    private let defaults = UserDefaults.standard

    init() {
        entries = defaults.stringArray(forKey: key) ?? []
    }

    func contains(_ word: String) -> Bool {
        entries.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// Append a trimmed, de-duplicated entry. Cap enforcement happens upstream.
    func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !contains(w) else { return }
        entries.append(w)
        persist()
    }

    func remove(_ word: String) {
        entries.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    private func persist() {
        defaults.set(entries, forKey: key)
    }
}
