import Foundation

// MARK: - Persisted layout model
//
// These are the on-disk JSON shapes. They are intentionally plain Codable
// structs with no AppKit types so the file format stays stable and readable.

/// A window rectangle in the global *Accessibility* coordinate space: origin is
/// the top-left of the main display, +y points down. We both read and write
/// through the Accessibility API, so storing these raw values means a restore
/// lands a window exactly where it was captured (as long as the display
/// arrangement is unchanged).
struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// One captured window belonging to an app.
struct SavedWindow: Codable, Equatable {
    var title: String
    var frame: WindowFrame
    var minimized: Bool

    /// CGDirectDisplayID the window's centre fell on at capture time. Recorded
    /// for diagnostics and as a fallback; restore positions by absolute frame.
    var displayID: UInt32?

    /// Managed Space id the window was on at capture time, when the (private)
    /// CoreGraphics API was able to report it. Informational only — macOS has
    /// no supported way to move a window between Spaces, so restore does not
    /// act on this. Surfaced in the UI so the user can see it.
    var spaceID: UInt64?
}

/// One captured application and all of its standard windows.
struct SavedApp: Codable, Equatable {
    var bundleID: String
    var name: String
    /// Absolute path to the .app at capture time. Used as a fallback when the
    /// bundle id can no longer be resolved on disk.
    var bundlePath: String?
    var windows: [SavedWindow]
}

/// A named layout the user can save and restore.
struct LayoutProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var apps: [SavedApp]

    init(id: UUID = UUID(), name: String, apps: [SavedApp]) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = self.createdAt
        self.apps = apps
    }

    /// Total window count across all apps — handy for the menu subtitle.
    var windowCount: Int { apps.reduce(0) { $0 + $1.windows.count } }
}
