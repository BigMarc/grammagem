import Foundation

/// A text-expansion snippet: type a short trigger, get a longer expansion.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

/// Local store for text-expansion snippets (a paid feature). Persisted to disk;
/// snippet contents never leave the device.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet]

    private let key = "GrammarGem.snippets"
    private let d = UserDefaults.standard

    init() {
        if let raw = d.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: raw) {
            snippets = decoded
        } else {
            snippets = []
        }
    }

    func add(trigger: String, expansion: String) {
        let t = trigger.trimmingCharacters(in: .whitespaces)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return }
        snippets.append(Snippet(trigger: t, expansion: e))
        persist()
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist()
    }

    /// Resolve a trigger to its expansion (used by the snippet hotkey path).
    func expansion(for trigger: String) -> String? {
        snippets.first { $0.trigger == trigger }?.expansion
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(snippets) {
            d.set(raw, forKey: key)
        }
    }
}
