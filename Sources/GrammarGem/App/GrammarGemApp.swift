import SwiftUI
import AppKit

/// Process entry point. A hidden `--mlx-selftest` flag loads the on-device model
/// and runs one real generation (verifies the MLX runtime + metallib headlessly),
/// then exits. Otherwise the normal menu-bar app launches.
@main
enum GrammaGemMain {
    static func main() {
        if CommandLine.arguments.contains("--mlx-selftest") {
            MLXSelfTest.run()
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--update-selftest") {
            let feed = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : ""
            UpdaterSelfTest.run(feedURL: feed)
            return
        }
        GrammaGemApp.main()
    }
}

/// Headless verification of the on-device LLM (used by CI / the build pipeline).
enum MLXSelfTest {
    static func run() {
        let sample = "me and him was going to the store for to buy some milks"
        let engine = MLXEngine(modelDirectoryProvider: {
            ModelManager.completedModelDirectory(repo: AppConfig.Model.defaultRepo)
        })
        guard engine.isReady else {
            FileHandle.standardError.write(Data("SELFTEST_FAIL: model not present\n".utf8))
            exit(2)
        }
        let sem = DispatchSemaphore(value: 0)
        var line = "SELFTEST_FAIL: unknown"
        Task.detached {
            do { line = "SELFTEST_OK: " + (try await engine.run(.rewriteClarity, on: sample)) }
            catch { line = "SELFTEST_FAIL: \(error.localizedDescription)" }
            sem.signal()
        }
        sem.wait()
        print(line)
        exit(line.hasPrefix("SELFTEST_OK") ? 0 : 1)
    }
}

/// App entry point. A menu-bar (`LSUIElement`) SwiftUI app: the only persistent
/// scene is the `MenuBarExtra`; Settings uses the standard scene; Onboarding and
/// Ask are AppKit-hosted windows opened on demand (see `AppState`).
struct GrammaGemApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(app)
                .frame(width: 560, height: 520)
        }
    }
}

/// Runs launch-time wiring (hotkeys, permissions, license validation).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}
