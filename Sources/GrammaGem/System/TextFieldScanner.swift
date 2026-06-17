import Foundation
import AppKit
import ApplicationServices

/// A text element discovered in the frontmost window via the Accessibility tree.
struct ScannedField {
    let element: AXUIElement
    let roleName: String
    let label: String
    let text: String
    let isFocused: Bool
}

/// Walks the Accessibility tree of the frontmost window and collects every
/// editable text element (text fields, text areas, combo/search boxes) with
/// content — so GrammaGem can check *all* the text on screen, not just the one
/// the cursor is in. Bounded so huge web/Electron trees can't stall the app.
enum TextFieldScanner {
    static func scan(
        pid: pid_t, focused: AXUIElement?,
        maxFields: Int = 30, maxVisited: Int = 4000
    ) -> [ScannedField] {
        let axApp = AXUIElementCreateApplication(pid)
        guard let root = window(of: axApp) ?? optional(axApp) else { return [] }
        var out: [ScannedField] = []
        var visited = 0
        walk(root, focused: focused, depth: 0, out: &out, visited: &visited,
             maxFields: maxFields, maxVisited: maxVisited)
        return out
    }

    private static func optional(_ el: AXUIElement) -> AXUIElement? { el }

    private static func window(of axApp: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, attr as CFString, &ref) == .success,
               let ref { return (ref as! AXUIElement) }
        }
        return nil
    }

    private static func walk(
        _ el: AXUIElement, focused: AXUIElement?, depth: Int,
        out: inout [ScannedField], visited: inout Int, maxFields: Int, maxVisited: Int
    ) {
        if out.count >= maxFields || visited >= maxVisited || depth > 70 { return }
        visited += 1

        let role = string(el, kAXRoleAttribute) ?? ""
        if role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String {
            if let value = string(el, kAXValueAttribute),
               value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                let label = string(el, kAXTitleAttribute)
                    ?? string(el, kAXDescriptionAttribute)
                    ?? string(el, kAXPlaceholderValueAttribute)
                    ?? roleLabel(role)
                let isFocused = focused != nil && CFEqual(el, focused!)
                out.append(ScannedField(
                    element: el, roleName: roleLabel(role),
                    label: label, text: value, isFocused: isFocused))
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let kids = childrenRef as? [AXUIElement] {
            for k in kids {
                if out.count >= maxFields || visited >= maxVisited { break }
                walk(k, focused: focused, depth: depth + 1, out: &out,
                     visited: &visited, maxFields: maxFields, maxVisited: maxVisited)
            }
        }
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func roleLabel(_ role: String) -> String {
        switch role {
        case kAXTextAreaRole as String: return "Text area"
        case kAXComboBoxRole as String: return "Combo box"
        default: return "Text field"
        }
    }
}
