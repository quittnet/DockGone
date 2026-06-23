import AppKit
import SwiftUI

/// Hosts `ProfileManagerView` in a single reusable window. Because Stagehand is
/// an `.accessory` app it never has a normal window by default; we create one on
/// demand and bring the app forward so the window can take focus.
final class ProfileManagerWindowController: NSWindowController {

    static let shared = ProfileManagerWindowController()

    /// Set by AppDelegate so the SwiftUI "Restore" button routes through the same
    /// progress/warning path as the menu.
    var onRestore: ((LayoutProfile) -> Void)?

    /// Set by AppDelegate so the window's "Save Current Layout" button reuses the
    /// same capture + name-prompt flow as the menu bar.
    var onSaveCurrentLayout: (() -> Void)?

    private var didInstallContent = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stagehand Profiles"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        // Build the SwiftUI host once and keep it. Rebuilding on every open would
        // throw away the view's @State (current selection, an in-progress rename).
        // Track this with a flag rather than `contentView == nil` — a freshly
        // created NSWindow already ships with a default empty contentView, so the
        // nil check never fired and the window came up blank. onRestore is read
        // lazily inside the closure, so installing it after init is fine.
        if !didInstallContent {
            let view = ProfileManagerView(
                store: ProfileStore.shared,
                onRestore: { [weak self] profile in self?.onRestore?(profile) },
                onSaveCurrentLayout: { [weak self] in self?.onSaveCurrentLayout?() }
            )
            let host = NSHostingView(rootView: view)
            host.frame = window?.contentView?.bounds ?? .zero
            host.autoresizingMask = [.width, .height]
            window?.contentView = host
            didInstallContent = true
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
