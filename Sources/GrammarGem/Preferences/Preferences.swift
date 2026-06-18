import Foundation
import AppKit
import ServiceManagement

/// User-facing app preferences, persisted to UserDefaults. Kept separate from
/// licensing/entitlements so the General settings stay simple.
@MainActor
final class Preferences: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case icon, monogram
        var id: String { rawValue }
        var label: String { self == .icon ? "Icon" : "Monogram" }
    }

    private let d = UserDefaults.standard

    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "pref.playSounds") } }
    @Published var liveUnderlines: Bool { didSet { d.set(liveUnderlines, forKey: "pref.liveUnderlines") } }
    @Published var restoreClipboard: Bool { didSet { d.set(restoreClipboard, forKey: "pref.restoreClipboard") } }
    @Published var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "pref.appearance"); applyAppearance() } }
    @Published var menuBarStyle: MenuBarStyle { didSet { d.set(menuBarStyle.rawValue, forKey: "pref.menuBarStyle") } }

    @Published var fixHotkey: HotkeyCombo { didSet { persist(fixHotkey, "pref.fixHotkey") } }
    @Published var askHotkey: HotkeyCombo { didSet { persist(askHotkey, "pref.askHotkey") } }

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        playSounds = d.object(forKey: "pref.playSounds") as? Bool ?? true
        liveUnderlines = d.object(forKey: "pref.liveUnderlines") as? Bool ?? true
        restoreClipboard = d.object(forKey: "pref.restoreClipboard") as? Bool ?? true
        appearance = Appearance(rawValue: d.string(forKey: "pref.appearance") ?? "") ?? .system
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "pref.menuBarStyle") ?? "") ?? .icon
        fixHotkey = Preferences.load("pref.fixHotkey") ?? .defaultFix
        askHotkey = Preferences.load("pref.askHotkey") ?? .defaultAsk
    }

    private func persist(_ combo: HotkeyCombo, _ key: String) {
        if let raw = try? JSONEncoder().encode(combo) { d.set(raw, forKey: key) }
    }

    private static func load(_ key: String) -> HotkeyCombo? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyCombo.self, from: raw)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Launch-at-login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
