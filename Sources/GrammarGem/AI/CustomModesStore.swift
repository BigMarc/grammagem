import Foundation

/// User-created Writing Modes (paid) plus per-app Mode overrides for App-Aware
/// switching. Persisted locally; the built-in modes live in `ModeRegistry`.
@MainActor
final class CustomModesStore: ObservableObject {
    @Published private(set) var customModes: [WritingMode]
    /// bundleID -> mode id (overrides the default App-Aware mapping).
    @Published private(set) var appOverrides: [String: String]

    private let modesKey = "GrammarGem.customModes"
    private let mapKey = "GrammarGem.appModeOverrides"
    private let d = UserDefaults.standard

    init() {
        if let raw = d.data(forKey: modesKey),
           let decoded = try? JSONDecoder().decode([WritingMode].self, from: raw) {
            customModes = decoded
        } else {
            customModes = []
        }
        appOverrides = (d.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
    }

    /// Built-in + custom modes (custom ones are always paid).
    func allModes() -> [WritingMode] { ModeRegistry.all + customModes }

    /// Returns false (no-op) if the name or prompt is empty, or the name
    /// collides with an existing built-in/custom mode — so an empty-prompt mode
    /// can't slip through to the LLM as an empty system prompt.
    @discardableResult
    func addCustom(name: String, prompt: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedPrompt.isEmpty else { return false }
        guard !allModes().contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return false }
        let mode = WritingMode(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: trimmed,
            systemPrompt: trimmedPrompt,
            isPaid: true,
            lengthCap: nil,
            autoFormat: "Custom"
        )
        customModes.append(mode)
        persistModes()
        return true
    }

    func removeCustom(id: String) {
        customModes.removeAll { $0.id == id }
        appOverrides = appOverrides.filter { $0.value != id }
        persistModes()
        persistMap()
    }

    func setOverride(bundleID: String, modeID: String) {
        let b = bundleID.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { return }
        appOverrides[b] = modeID
        persistMap()
    }

    func clearOverride(bundleID: String) {
        appOverrides.removeValue(forKey: bundleID)
        persistMap()
    }

    private func persistModes() {
        if let raw = try? JSONEncoder().encode(customModes) {
            d.set(raw, forKey: modesKey)
        }
    }

    private func persistMap() {
        d.set(appOverrides, forKey: mapKey)
    }
}
