import AppKit
import ApplicationServices

/// Gatekeeper for the Accessibility (AXIsProcessTrusted) permission that the
/// whole app depends on: without it we can neither read window frames nor move
/// windows. Everything here is about asking for that grant *clearly*, once.
enum AccessibilityManager {

    /// Whether the system currently trusts us for Accessibility.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Trigger the system's own "… would like to control this computer" prompt
    /// and add us to the Accessibility list (unchecked) so the user only has to
    /// flip the switch.
    static func triggerSystemPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Deep-link straight to System Settings ▸ Privacy & Security ▸ Accessibility.
    static func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Shown once on first launch (and re-available from the menu). Explains
    /// *why* we need the permission before the OS throws its terse system
    /// prompt, so the request never feels like it came out of nowhere.
    static func presentFirstLaunchExplainer() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Stagehand needs Accessibility access"
        alert.informativeText = """
        Stagehand saves and restores the position and size of your app windows. \
        macOS only lets an app read and move other apps' windows when you grant \
        it Accessibility access.

        Without it, Stagehand can list your profiles but can't capture or restore \
        any layouts.

        Click “Open System Settings”, then enable Stagehand under \
        Privacy & Security ▸ Accessibility.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        // Bring our accessory app forward so the alert isn't lost behind others.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            triggerSystemPrompt()
            openSystemSettings()
        }
    }

    /// Lighter-weight nudge used when an action (Save/Restore) is attempted
    /// while still untrusted.
    static func presentBlockedActionAlert(action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accessibility access required"
        alert.informativeText = """
        Stagehand can't \(action) until you enable it under \
        Privacy & Security ▸ Accessibility.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            triggerSystemPrompt()
            openSystemSettings()
        }
    }
}
