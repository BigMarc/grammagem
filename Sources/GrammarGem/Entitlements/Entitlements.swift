import Foundation

/// A single value object derived from license tier that every paid path checks.
/// Free is deliberately useful (full Harper grammar, system-wide) while the AI
/// superpowers + multi-device are the upgrade triggers (spec §5).
struct Entitlements: Equatable {
    let tier: Tier

    /// Layer-1 grammar is ALWAYS free + unlimited (the open-source core).
    var unlimitedGrammar: Bool { true }

    /// Layer-2 AI actions: unlimited when paid; capped per day on free.
    var unlimitedAIActions: Bool { tier.isPaid }
    var dailyAIActionCap: Int {
        tier.isPaid ? Int.max : AppConfig.Limits.freeDailyAIActions
    }

    /// Writing Modes: free gets Polish only; paid gets all + custom.
    var allModes: Bool { tier.isPaid }

    /// Paid-only features.
    var appAwareSwitching: Bool { tier.isPaid }
    var snippets: Bool { tier.isPaid }
    var canUseLargeModel: Bool { tier.isPaid }

    /// Personal dictionary: 25 entries free, unlimited paid.
    var dictionaryCap: Int {
        tier.isPaid ? Int.max : AppConfig.Limits.freeDictionaryCap
    }

    var deviceCap: Int { tier.deviceCap }
}
