import Foundation
import Sparkle

/// Wraps Sparkle's updater. It background-checks the appcast on grammagem.app and
/// publishes `updateAvailableVersion` when a newer, EdDSA-verified build exists, so
/// the menu bar can show an "Update available" button. Triggering an update runs
/// Sparkle's verified download + install flow.
///
/// The updater is only started inside the packaged `.app` (where the Info.plist
/// carries `SUFeedURL` + `SUPublicEDKey`); under `swift run`, tests, or the
/// self-test binaries it stays inert so nothing crashes.
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    @Published private(set) var updateAvailableVersion: String?

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            return // not the packaged app — no updater
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// User-initiated check — shows Sparkle's UI (used by the menu item and the
    /// "Update" button on the availability banner).
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailableVersion = nil
    }
}

// MARK: - Headless update self-test (build pipeline / CI)

/// Checks `feedURL` for a newer version with no UI and prints the result, then
/// exits. Used to verify the appcast + signature + version-comparison path.
enum UpdaterSelfTest {
    static func run(feedURL: String) {
        let delegate = UpdateProbeDelegate(feed: feedURL)
        UpdateProbeDelegate.retained = delegate
        UpdateProbeDelegate.controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        UpdateProbeDelegate.controller?.updater.checkForUpdateInformation()
        RunLoop.main.run() // Sparkle's network check needs the run loop; delegate exits.
    }
}

private final class UpdateProbeDelegate: NSObject, SPUUpdaterDelegate {
    static var controller: SPUStandardUpdaterController?
    static var retained: UpdateProbeDelegate?
    let feed: String
    init(feed: String) { self.feed = feed; super.init() }

    func feedURLString(for updater: SPUUpdater) -> String? { feed.isEmpty ? nil : feed }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("UPDATE_FOUND: \(item.displayVersionString)")
        exit(0)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("UPDATE_NONE")
        exit(0)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("UPDATE_ERROR: \(error.localizedDescription)")
        exit(1)
    }
}
