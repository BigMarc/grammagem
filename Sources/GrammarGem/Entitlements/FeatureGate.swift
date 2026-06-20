import Foundation

/// The runtime gate every paid path goes through. Combines current `Entitlements`
/// (from the license) with a local daily counter for the free tier's AI allowance.
@MainActor
final class FeatureGate: ObservableObject {
    enum Decision: Equatable {
        case allowed
        case denied(String)
    }

    private let license: LicenseManager
    private let counter = DailyCounter()

    /// Bumped to nudge SwiftUI when the counter changes (it's stored externally).
    @Published private(set) var usageTick = 0

    init(license: LicenseManager) {
        self.license = license
    }

    var entitlements: Entitlements { license.entitlements }

    // MARK: - AI gating (rewrite / tone / Ask / translate / paid Modes share this)

    func authorizeAI(_ action: AIAction) -> Decision {
        let ent = entitlements

        // Paid Modes are unavailable on free (only Polish ships free).
        if case .applyMode(let mode) = action, mode.isPaid, !ent.allModes {
            return .denied("“\(mode.name)” mode is part of the lifetime upgrade.")
        }

        if ent.unlimitedAIActions { return .allowed }

        guard remainingAIActionsToday > 0 else {
            return .denied("You've used today's \(ent.dailyAIActionCap) free AI actions. Upgrade for unlimited.")
        }
        return .allowed
    }

    func recordAIActionUsed() {
        guard !entitlements.unlimitedAIActions else { return }
        counter.increment()
        usageTick &+= 1
    }

    var aiActionsUsedToday: Int { counter.countToday() }

    var remainingAIActionsToday: Int {
        let ent = entitlements
        if ent.unlimitedAIActions { return Int.max }
        return max(0, ent.dailyAIActionCap - counter.countToday())
    }

    // MARK: - Other gates

    func availableModes() -> [WritingMode] {
        ModeRegistry.available(for: license.tier)
    }

    var appAwareEnabled: Bool { entitlements.appAwareSwitching }
    var snippetsEnabled: Bool { entitlements.snippets }

    /// Can the user add another personal-dictionary entry given the current count?
    func canAddDictionaryEntry(currentCount: Int) -> Decision {
        if currentCount < entitlements.dictionaryCap { return .allowed }
        return .denied("Free dictionary holds \(entitlements.dictionaryCap) entries. Upgrade for unlimited.")
    }
}

/// Free-tier AI action counter. Persists `{date, count}` in UserDefaults and
/// resets at local midnight (compares the stored local date string to today's).
final class DailyCounter {
    private let key = "GrammarGem.aiActions.daily"
    private let defaults = UserDefaults.standard

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent // tracks the live local zone (travel/TZ change)
        return f
    }()

    private func today() -> String { Self.formatter.string(from: Date()) }

    func countToday() -> Int {
        guard let stored = defaults.dictionary(forKey: key),
              let date = stored["date"] as? String, date == today()
        else { return 0 }
        return stored["count"] as? Int ?? 0
    }

    func increment() {
        let next = countToday() + 1
        defaults.set(["date": today(), "count": next], forKey: key)
    }

    func reset() { defaults.removeObject(forKey: key) }
}
