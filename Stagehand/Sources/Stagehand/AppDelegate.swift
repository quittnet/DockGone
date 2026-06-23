import AppKit

/// Minimal app-delegate, attached via `@NSApplicationDelegateAdaptor`. SwiftUI
/// owns the windows, menus and menu-bar item now; this only handles the few
/// things that aren't scene-shaped: the first-launch Accessibility explainer,
/// global hotkeys, and the display-change / launch automation triggers.
///
/// The class is intentionally not `@MainActor`-annotated (so it cleanly conforms
/// to NSApplicationDelegate); calls into the main-actor `AppModel` hop on via
/// `Task { @MainActor in … }`, which is safe since these all run on the main
/// thread already.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var displayTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            if !Prefs.didShowAccessibilityExplainer {
                Prefs.didShowAccessibilityExplainer = true
                if !AccessibilityManager.isTrusted {
                    AccessibilityManager.presentFirstLaunchExplainer()
                }
            }
            AppModel.shared.applyArrangeShortcuts()
            self.scheduleLaunchRestore()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Keep running as a menu-bar item after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: Automation triggers

    @objc private func displaysChanged() {
        guard let id = Prefs.displayChangeProfileID else { return }
        // Displays fire several notifications as they settle; debounce with a
        // cancellable task so we restore once, after the dust clears.
        displayTask?.cancel()
        displayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            AppModel.shared.restoreProfileSilently(id: id)
        }
    }

    private func scheduleLaunchRestore() {
        guard let id = Prefs.launchRestoreProfileID else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            AppModel.shared.restoreProfileSilently(id: id)
        }
    }
}
