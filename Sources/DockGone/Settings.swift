import Cocoa
import Carbon

// Single source of truth for user-configurable preferences. Backed by
// UserDefaults; posts `didChangeNotification` after any mutation so the
// AppDelegate can re-register the global hotkey and freshly opened
// switchers pick up the new look.
final class Prefs {
    static let shared = Prefs()
    static let didChangeNotification = Notification.Name("DockGonePrefsDidChange")

    enum Position: String, CaseIterable, Identifiable {
        case top, center, bottom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .top:    return "Top"
            case .center: return "Center"
            case .bottom: return "Bottom"
            }
        }
    }

    enum LabelMode: String, CaseIterable, Identifiable {
        case selectedOnly, always, never
        var id: String { rawValue }
        var label: String {
            switch self {
            case .selectedOnly: return "Selected only"
            case .always:       return "Always show"
            case .never:        return "Never show"
            }
        }
    }

    private let d = UserDefaults.standard
    private init() {}

    // MARK: - Defaults
    static let defaultIconSize: CGFloat = 64
    static let defaultTint: NSColor    = NSColor.black.withAlphaComponent(0.10)
    static let defaultPosition         = Position.center
    static let defaultLabelMode        = LabelMode.selectedOnly
    static let defaultIncludeTrash     = true
    static let defaultHotkeyKey: UInt32 = UInt32(kVK_Tab)
    static let defaultHotkeyMods: UInt32 = UInt32(optionKey)
    static let defaultSuppressBouncing = true

    // MARK: - Values
    var iconSize: CGFloat {
        get { CGFloat(d.object(forKey: "iconSize") as? Double ?? Double(Self.defaultIconSize)) }
        set { d.set(Double(newValue), forKey: "iconSize"); notify() }
    }

    var tintColor: NSColor {
        get { getColor("tintColor", default: Self.defaultTint) }
        set { setColor(newValue, key: "tintColor") }
    }

    var position: Position {
        get { Position(rawValue: d.string(forKey: "position") ?? "") ?? Self.defaultPosition }
        set { d.set(newValue.rawValue, forKey: "position"); notify() }
    }

    var labelMode: LabelMode {
        get { LabelMode(rawValue: d.string(forKey: "labelMode") ?? "") ?? Self.defaultLabelMode }
        set { d.set(newValue.rawValue, forKey: "labelMode"); notify() }
    }

    var includeTrash: Bool {
        get { d.object(forKey: "includeTrash") as? Bool ?? Self.defaultIncludeTrash }
        set { d.set(newValue, forKey: "includeTrash"); notify() }
    }

    var hotkeyKeyCode: UInt32 {
        get { UInt32(d.object(forKey: "hotkeyKey") as? Int ?? Int(Self.defaultHotkeyKey)) }
        set { d.set(Int(newValue), forKey: "hotkeyKey"); notify() }
    }

    var hotkeyModifiers: UInt32 {
        get { UInt32(d.object(forKey: "hotkeyMods") as? Int ?? Int(Self.defaultHotkeyMods)) }
        set { d.set(Int(newValue), forKey: "hotkeyMods"); notify() }
    }

    var suppressBouncing: Bool {
        get { d.object(forKey: "suppressBouncing") as? Bool ?? Self.defaultSuppressBouncing }
        set { d.set(newValue, forKey: "suppressBouncing"); notify() }
    }

    func resetToDefaults() {
        for key in ["iconSize", "tintColor", "position", "labelMode",
                    "includeTrash", "hotkeyKey", "hotkeyMods", "suppressBouncing"] {
            d.removeObject(forKey: key)
        }
        notify()
    }

    // MARK: - Helpers

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func getColor(_ key: String, default def: NSColor) -> NSColor {
        guard let data = d.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: data)
        else { return def }
        return color
    }

    private func setColor(_ color: NSColor, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: color, requiringSecureCoding: false) else { return }
        d.set(data, forKey: key)
        notify()
    }
}

// MARK: - Hotkey display

enum HotkeyDisplay {
    static func string(modifiers: UInt32, keyCode: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Tab:        return "⇥"
        case kVK_Space:      return "Space"
        case kVK_Return:     return "↩"
        case kVK_Escape:     return "⎋"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_Delete:     return "⌫"
        case kVK_F1...kVK_F20: return "F\(Int(code) - kVK_F1 + 1)"
        default: break
        }
        if let ch = keyCharacter(for: code) { return ch.uppercased() }
        return "Key \(code)"
    }

    // Best-effort translation of a virtual key code to its glyph using the
    // current keyboard layout. Returns nil for non-printables.
    private static func keyCharacter(for keyCode: UInt32) -> String? {
        let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLen = 0
        let status = data.withUnsafeBytes { ptr -> OSStatus in
            guard let layoutPtr = ptr.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return -1 }
            return UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &realLen,
                &chars
            )
        }
        guard status == noErr, realLen > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: realLen)
    }
}
