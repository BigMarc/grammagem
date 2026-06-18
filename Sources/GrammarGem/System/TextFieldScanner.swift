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
    /// Stable-ish identity for SwiftUI: AX identifier if present, else role+label+position.
    let stableID: String
}

/// Walks the Accessibility tree of the frontmost window and collects every
/// editable text element (text fields, text areas, combo/search boxes) with
/// content — so GrammaGem can check *all* the text on screen, not just the one
/// the cursor is in. Bounded so huge web/Electron trees can't stall the app, and
/// every cross-process message has a timeout so a wedged app can't hang the scan.
///
/// Safe to call off the main thread (AXUIElement APIs are thread-safe).
enum TextFieldScanner {
    static func scan(
        pid: pid_t, focused: AXUIElement?,
        maxFields: Int = 30, maxVisited: Int = 3000
    ) -> [ScannedField] {
        let axApp = AXUIElementCreateApplication(pid)
        AX.setMessagingTimeout(axApp, 0.3)
        guard let root = AX.copyElement(axApp, kAXFocusedWindowAttribute)
            ?? AX.copyElement(axApp, kAXMainWindowAttribute) else { return [] }
        var out: [ScannedField] = []
        var visited = 0
        walk(root, focused: focused, depth: 0, out: &out, visited: &visited,
             maxFields: maxFields, maxVisited: maxVisited)
        return out
    }

    private static func walk(
        _ el: AXUIElement, focused: AXUIElement?, depth: Int,
        out: inout [ScannedField], visited: inout Int, maxFields: Int, maxVisited: Int
    ) {
        if out.count >= maxFields || visited >= maxVisited || depth > 70 { return }
        visited += 1

        let role = AX.copyString(el, kAXRoleAttribute) ?? ""
        if role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String {
            if let value = AX.copyString(el, kAXValueAttribute),
               value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                let label = AX.copyString(el, kAXTitleAttribute)
                    ?? AX.copyString(el, kAXDescriptionAttribute)
                    ?? AX.copyString(el, kAXPlaceholderValueAttribute)
                    ?? roleLabel(role)
                let isFocused = focused != nil && CFEqual(el, focused!)
                out.append(ScannedField(
                    element: el, roleName: roleLabel(role),
                    label: label, text: value, isFocused: isFocused,
                    stableID: identity(of: el, role: role, label: label)))
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

    /// A SwiftUI-stable identity that survives re-scans and text edits: prefer the
    /// AX identifier, else fall back to role + label + on-screen position.
    private static func identity(of el: AXUIElement, role: String, label: String) -> String {
        if let axID = AX.copyString(el, kAXIdentifierAttribute), !axID.isEmpty {
            return "id:\(axID)"
        }
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
           let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() {
            var point = CGPoint.zero
            if AXValueGetValue(posRef as! AXValue, .cgPoint, &point) {
                return "pos:\(role)|\(label)|\(Int(point.x)),\(Int(point.y))"
            }
        }
        return "rl:\(role)|\(label)"
    }

    private static func roleLabel(_ role: String) -> String {
        switch role {
        case kAXTextAreaRole as String: return "Text area"
        case kAXComboBoxRole as String: return "Combo box"
        default: return "Text field"
        }
    }
}
