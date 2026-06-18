import XCTest
@testable import GrammaGem

final class GrammaGemTests: XCTestCase {

    // MARK: - Tiers / entitlements

    func testDeviceCapsMatchSpec() {
        XCTAssertEqual(Tier.solo.deviceCap, 1)
        XCTAssertEqual(Tier.personal.deviceCap, 2)
        XCTAssertEqual(Tier.studio.deviceCap, 4)
        XCTAssertEqual(Tier.free.deviceCap, 1)
    }

    func testFreeEntitlementsAreLimited() {
        let free = Entitlements(tier: .free)
        XCTAssertFalse(free.unlimitedAIActions)
        XCTAssertEqual(free.dailyAIActionCap, AppConfig.Limits.freeDailyAIActions)
        XCTAssertEqual(free.dictionaryCap, AppConfig.Limits.freeDictionaryCap)
        XCTAssertFalse(free.appAwareSwitching)
        XCTAssertFalse(free.allModes)
        XCTAssertTrue(free.unlimitedGrammar) // grammar is always free
    }

    func testPaidEntitlementsUnlockEverything() {
        let paid = Entitlements(tier: .personal)
        XCTAssertTrue(paid.unlimitedAIActions)
        XCTAssertEqual(paid.dailyAIActionCap, Int.max)
        XCTAssertEqual(paid.dictionaryCap, Int.max)
        XCTAssertTrue(paid.appAwareSwitching)
        XCTAssertTrue(paid.allModes)
    }

    // MARK: - Grammar (Harper stub) rules

    func testHarperFixesRepeatedWordAndCasing() {
        let harper = HarperEngine()
        let input = "hey i wanted to checkin about the the proposal"
        let fixed = harper.correct(input)
        XCTAssertFalse(fixed.contains("the the"), "repeated word should be collapsed")
        XCTAssertTrue(fixed.contains(" I "), "lowercase pronoun i should be capitalized")
        XCTAssertTrue(fixed.contains("check in"), "checkin should split into two words")
    }

    func testIgnoreListSuppressesCorrection() {
        let harper = HarperEngine()
        harper.ignoreList = ["teh"] // pretend "teh" is an intentional brand term
        let suggestions = harper.check("teh launch")
        XCTAssertFalse(suggestions.contains { $0.original.lowercased() == "teh" })
    }

    /// Real Harper does true grammar NSSpellChecker can't: subject-verb
    /// agreement and verb-form correction, applied cleanly in place.
    func testHarperRealGrammarCorrections() {
        let harper = HarperEngine()
        let fixed = harper.correct("She dont like it and she have went home.")
        XCTAssertTrue(fixed.contains("don't"), "dont -> don't")
        XCTAssertTrue(fixed.contains("has"), "have -> has (subject-verb agreement)")
        XCTAssertTrue(fixed.contains("gone"), "went -> gone (past participle)")
        XCTAssertFalse(fixed.contains("went"), "the wrong verb form should be gone")
    }

    /// The trust bug: a mid-sentence spelling fix must keep the original casing.
    func testSpellingReplacementPreservesCase() {
        XCTAssertEqual(SystemGrammarEngine.matchingCase(of: "problemm", in: "Problem"), "problem")
        XCTAssertEqual(SystemGrammarEngine.matchingCase(of: "Teh", in: "the"), "The")
        XCTAssertEqual(SystemGrammarEngine.matchingCase(of: "teh", in: "the"), "the")
        XCTAssertEqual(SystemGrammarEngine.matchingCase(of: "HELLOO", in: "hello"), "HELLO")
    }

    /// Harper returns char (Unicode scalar) offsets; they must map exactly onto
    /// UTF-16 NSRange offsets even past multi-UTF-16-unit scalars (emoji).
    func testHarperCharOffsetsMapToUTF16() {
        let text = "😀 teh"  // 😀 = 1 scalar / 2 UTF-16 units
        let range = HarperEngine.utf16Range(scalarStart: 2, scalarLen: 3, in: text)
        XCTAssertEqual(range, NSRange(location: 3, length: 3))
        XCTAssertEqual((text as NSString).substring(with: range!), "teh")
    }

    // MARK: - Value loop (streak / subscription-avoided / milestones)

    @MainActor
    func testValueLoopMetrics() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        let cal = Calendar.current
        let now = Date()
        func key(_ daysAgo: Int) -> String {
            fmt.string(from: cal.date(byAdding: .day, value: -daysAgo, to: now)!)
        }

        // today + yesterday + 2-days-ago = streak of 3 (the day-4 entry is broken off).
        let perDay = [key(0): 2, key(1): 1, key(2): 5, key(4): 1]
        XCTAssertEqual(UsageStats.streak(perDay: perDay, asOf: now), 3)
        XCTAssertEqual(UsageStats.streak(perDay: [:], asOf: now), 0)
        // Used yesterday but not yet today — streak is still alive.
        XCTAssertEqual(UsageStats.streak(perDay: [key(1): 1], asOf: now), 1)

        // ~1 year of ownership ≈ one year of the subscription you didn't pay.
        XCTAssertEqual(
            UsageStats.subscriptionAvoidedUSD(firstUseDay: key(365), asOf: now, annualPrice: 144), 144)
        XCTAssertEqual(
            UsageStats.subscriptionAvoidedUSD(firstUseDay: nil, asOf: now, annualPrice: 144), 0)

        let m = UsageStats.nextMilestone(corrections: 50)
        XCTAssertEqual(m.target, 100)
        XCTAssertEqual(m.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(UsageStats.nextMilestone(corrections: 100).target, 500)
    }

    // MARK: - Modes

    func testFreeTierGetsOnlyPolishMode() {
        let free = ModeRegistry.available(for: .free)
        XCTAssertEqual(free.map(\.id), ["polish"])
        let paid = ModeRegistry.available(for: .studio)
        XCTAssertGreaterThan(paid.count, 1)
        XCTAssertTrue(paid.contains { $0.id == "email" })
    }

    func testAppAwareModeMapping() {
        XCTAssertEqual(ModeRegistry.mode(forBundleID: "com.apple.mail")?.id, "email")
        XCTAssertEqual(ModeRegistry.mode(forBundleID: "com.microsoft.VSCode")?.id, "code")
        XCTAssertNil(ModeRegistry.mode(forBundleID: "com.unknown.app"))
    }

    // MARK: - Device fingerprint

    func testDeviceFingerprintIsStableAndHashed() {
        let a = DeviceFingerprint.stableID()
        let b = DeviceFingerprint.stableID()
        XCTAssertEqual(a, b, "fingerprint must be stable across calls")
        XCTAssertFalse(a.isEmpty)
        // SHA-256 hex is 64 chars (unless the random fallback path is hit).
        XCTAssertTrue(a.count == 64 || a.count == UUID().uuidString.count)
    }
}
