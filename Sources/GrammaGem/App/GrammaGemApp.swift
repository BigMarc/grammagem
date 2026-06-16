import SwiftUI
import AppKit

/// App entry point. A menu-bar (`LSUIElement`) SwiftUI app: the only persistent
/// scene is the `MenuBarExtra`; Settings uses the standard scene; Onboarding and
/// Ask are AppKit-hosted windows opened on demand (see `AppState`).
@main
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
