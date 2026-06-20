import Foundation

/// Privacy-friendly, fully-local usage insights. Counts *how often* features are
/// used — never *what* was written. Stored only on this Mac.
@MainActor
final class UsageStats: ObservableObject {
    struct Snapshot: Codable, Equatable {
        var totalCorrections = 0
        var totalAIActions = 0
        var totalWords = 0
        var activeDays = 0              // distinct days with ≥1 action (lifetime)
        var firstUseDay: String?       // "yyyy-MM-dd" of first ever action
        var perDay: [String: Int] = [:] // "yyyy-MM-dd" -> actions that day
    }

    /// What a Grammarly-style subscription runs per year (USD) — used only for the
    /// honest, local "subscription you didn't pay" figure. GrammarGem is one-time.
    static let comparableAnnualSubscriptionUSD = 144.0

    @Published private(set) var data: Snapshot

    private let key = "GrammarGem.usageStats"
    private let d = UserDefaults.standard

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    init() {
        if let raw = d.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: raw) {
            data = decoded
        } else {
            data = Snapshot()
        }
    }

    func recordCorrection(words: Int) {
        data.totalCorrections += 1
        data.totalWords += max(0, words)
        bumpToday()
        persist()
    }

    func recordAIAction(words: Int) {
        data.totalAIActions += 1
        data.totalWords += max(0, words)
        bumpToday()
        persist()
    }

    /// A playful, clearly-estimated "time saved" figure (local only).
    var estimatedMinutesSaved: Int {
        (data.totalCorrections * 8 + data.totalAIActions * 45) / 60
    }

    // MARK: - Value loop (streak / milestones / subscription-you-didn't-pay)

    /// Consecutive days, ending today or yesterday, with at least one action.
    var currentStreak: Int { Self.streak(perDay: data.perDay, asOf: Date()) }

    /// The Grammarly subscription you DIDN'T pay: their annual price prorated over
    /// how long you've owned GrammarGem. Honest, local, illustrative — and it only
    /// grows, which is the point of a one-time purchase (see the value plan §5).
    var subscriptionAvoidedUSD: Int {
        Self.subscriptionAvoidedUSD(
            firstUseDay: data.firstUseDay, asOf: Date(),
            annualPrice: Self.comparableAnnualSubscriptionUSD)
    }

    /// The next correction milestone and progress toward it (for a nudge/badge).
    var nextMilestone: (target: Int, label: String, progress: Double) {
        Self.nextMilestone(corrections: data.totalCorrections)
    }

    // MARK: - Pure helpers (unit-testable; no UserDefaults / wall clock)

    static func streak(perDay: [String: Int], asOf now: Date) -> Int {
        let cal = Calendar.current
        func used(_ day: Date) -> Bool { (perDay[fmt.string(from: day)] ?? 0) > 0 }
        var day = now
        if !used(day) {
            // Streak is still alive if used yesterday but not yet today.
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            if !used(day) { return 0 }
        }
        var streak = 0
        while used(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    static func subscriptionAvoidedUSD(firstUseDay: String?, asOf now: Date, annualPrice: Double) -> Int {
        guard let first = firstUseDay, let firstDate = fmt.date(from: first) else { return 0 }
        let days = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: now).day ?? 0)
        return Int((Double(days) / 365.0 * annualPrice).rounded())
    }

    static func nextMilestone(corrections: Int) -> (target: Int, label: String, progress: Double) {
        let targets = [100, 500, 1_000, 5_000, 10_000, 50_000, 100_000]
        let target = targets.first { $0 > corrections } ?? (((corrections / 100_000) + 1) * 100_000)
        let previous = targets.last { $0 <= corrections } ?? 0
        let span = max(1, target - previous)
        let progress = min(1.0, Double(corrections - previous) / Double(span))
        let label = target >= 1_000 ? "\(target / 1_000)k corrections" : "\(target) corrections"
        return (target, label, progress)
    }

    /// Counts for the last 7 calendar days, oldest → newest, for a small chart.
    func last7Days() -> [(label: String, count: Int)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = Self.fmt.string(from: day)
            let short = day.formatted(.dateTime.weekday(.narrow))
            return (label: short, count: data.perDay[key] ?? 0)
        }
    }

    func reset() {
        data = Snapshot()
        persist()
    }

    private func bumpToday() {
        let k = Self.fmt.string(from: Date())
        if data.perDay[k] == nil {            // first action on a brand-new day
            data.activeDays += 1
            if data.firstUseDay == nil { data.firstUseDay = k }
        }
        data.perDay[k, default: 0] += 1
        // Keep only ~60 days of history.
        if data.perDay.count > 70 {
            let keep = Set((0..<60).compactMap { off -> String? in
                guard let day = Calendar.current.date(byAdding: .day, value: -off, to: Date()) else { return nil }
                return Self.fmt.string(from: day)
            })
            data.perDay = data.perDay.filter { keep.contains($0.key) }
        }
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) {
            d.set(raw, forKey: key)
        }
    }
}
