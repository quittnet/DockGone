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
        let view = ProfileManagerView(store: ProfileStore.shared) { [weak self] profile in
            self?.onRestore?(profile)
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
