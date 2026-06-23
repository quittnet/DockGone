import AppKit
import ApplicationServices

// MARK: - Private symbols
//
// macOS exposes no public API for (a) the CGWindowID behind an AXUIElement or
// (b) which Space a window lives on. Both are long-standing private symbols
// that every window manager (yabai, Rectangle's space probes, Amethyst…) links
// against. We declare them with @_silgen_name; they resolve at runtime from
// already-loaded system frameworks. Every call site degrades gracefully if the
// symbol ever misbehaves, so a future macOS that drops them only loses the
// (optional) Space annotation, never the core capture/restore.

/// Returns the CGWindowID for a given accessibility window element.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

private typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

/// Maps window ids to the Space id(s) they appear on. `mask` 0x7 selects all
/// Space types (user, fullscreen, system). Returns a CFArray of CFNumbers.
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID,
                                     _ mask: Int32,
                                     _ windowIDs: CFArray) -> Unmanaged<CFArray>?

// MARK: - AX convenience

enum AX {

    /// Read an attribute, returning the raw CoreFoundation value or nil.
    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyAttribute(element, attribute) as? Bool
    }

    /// All windows of an application element, in the app's z-order.
    static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(appElement, kAXWindowsAttribute as String) else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// The on-screen frame of a window, or nil if it doesn't expose one.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = copyAttribute(window, kAXPositionAttribute as String),
              let sizeValue = copyAttribute(window, kAXSizeAttribute as String),
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Move + resize a window. Position is set twice — once before and once
    /// after the size — because some apps clamp the position against the old
    /// size on the first pass and only honour the final value once resized.
    @discardableResult
    static func setFrame(_ window: AXUIElement, _ rect: CGRect) -> Bool {
        var position = rect.origin
        var size = rect.size

        var ok = true
        if let posValue = AXValueCreate(.cgPoint, &position) {
            ok = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue) == .success && ok
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            ok = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success && ok
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        return ok
    }

    static func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
    }

    /// True only for ordinary document/app windows — filters out palettes,
    /// sheets and the like so we don't try to persist transient chrome.
    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        string(window, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String)
    }

    /// The CGWindowID behind an AX window element, via the private symbol.
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var wid = CGWindowID(0)
        return _AXUIElementGetWindow(window, &wid) == .success ? wid : nil
    }

    /// The app's focused (frontmost) window, used by the arrange commands so they
    /// act on whatever the user is looking at.
    static func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(appElement, kAXFocusedWindowAttribute as String),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}

// MARK: - Spaces & displays

enum SpaceInfo {

    /// Best-effort Space id for a CGWindowID. Returns nil if the private API is
    /// unavailable or reports nothing.
    static func spaceID(for windowID: CGWindowID) -> UInt64? {
        let connection = CGSMainConnectionID()
        let ids = [NSNumber(value: windowID)] as CFArray
        guard let cfSpaces = CGSCopySpacesForWindows(connection, 0x7, ids)?.takeRetainedValue(),
              let spaces = cfSpaces as NSArray as? [NSNumber],
              let first = spaces.first
        else { return nil }
        return first.uint64Value
    }
}

enum DisplayInfo {

    /// The display whose bounds contain `point`. CGDisplayBounds and AX both use
    /// top-left-origin global coordinates, so no conversion is needed.
    static func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayBounds($0).contains(point) }
    }
}
