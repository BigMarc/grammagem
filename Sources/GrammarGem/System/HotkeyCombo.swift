import Foundation
import AppKit
import Carbon.HIToolbox

/// A user-configurable keyboard shortcut: a key code plus Carbon modifier mask,
/// with a human-readable display string (e.g. "⌘;").
struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let defaultFix = HotkeyCombo(
        keyCode: AppConfig.Hotkey.defaultKeyCode,
        carbonModifiers: AppConfig.Hotkey.defaultModifiers,
        display: "⌘;")

    static let defaultAsk = HotkeyCombo(
        keyCode: AppConfig.Hotkey.askKeyCode,
        carbonModifiers: AppConfig.Hotkey.askModifiers,
        display: "⌘'")

    /// Build a combo from a recorded key-down event. Requires at least one
    /// modifier so the shortcut is safe to register globally.
    static func from(event: NSEvent) -> HotkeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }

        let symbol = keySymbol(for: event)
        var display = ""
        if flags.contains(.control) { display += "⌃" }
        if flags.contains(.option) { display += "⌥" }
        if flags.contains(.shift) { display += "⇧" }
        if flags.contains(.command) { display += "⌘" }
        display += symbol
        return HotkeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, display: display)
    }

    private static func keySymbol(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                return chars.uppercased()
            }
            return "key"
        }
    }
}
