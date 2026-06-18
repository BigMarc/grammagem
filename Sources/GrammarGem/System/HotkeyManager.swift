import Foundation
import Carbon.HIToolbox

/// Registers system-wide global hotkeys via Carbon `RegisterEventHotKey`.
///
/// This is the no-dependency path. The spec lists `KeyboardShortcuts`
/// (Sindre Sorhus) for a nicer recorder UI; you can swap this implementation
/// for that package without touching callers. User-configurable (defaults ⌘; and ⌘').
final class HotkeyManager {
    /// Logical actions a hotkey can fire.
    enum Action { case fix, ask }

    var onAction: ((Action) -> Void)?

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var idToAction: [UInt32: Action] = [:]

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Register the two product hotkeys. Call again to re-register after the
    /// user changes a shortcut.
    func registerDefaults() {
        register(id: 1, keyCode: AppConfig.Hotkey.defaultKeyCode,
                 modifiers: AppConfig.Hotkey.defaultModifiers, action: .fix)
        register(id: 2, keyCode: AppConfig.Hotkey.askKeyCode,
                 modifiers: AppConfig.Hotkey.askModifiers, action: .ask)
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: Action) -> Bool {
        idToAction[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x47474D31), id: id) // 'GGM1'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &ref)
        if status == noErr {
            refs.append(ref)
            return true
        }
        Log.system.error("RegisterEventHotKey failed: \(status)")
        return false
    }

    func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    // MARK: - Carbon event plumbing

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                guard err == noErr else { return err }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let action = mgr.idToAction[hkID.id] {
                    DispatchQueue.main.async { mgr.onAction?(action) }
                }
                return noErr
            },
            1, &spec, selfPtr, &handler)
    }
}
