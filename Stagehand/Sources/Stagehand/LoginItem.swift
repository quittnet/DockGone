import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` — the modern (macOS 13+) way to
/// register an app as a login item without a separate helper or a LaunchAgent
/// plist. The system manages the registration; we just toggle it.
enum LoginItem {

    /// Whether Stagehand is currently set to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has explicitly denied the login item in System
    /// Settings — used to point them there instead of silently failing.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Turn launch-at-login on or off. Throws if the system rejects the change
    /// (e.g. the bundle isn't registered with Launch Services yet).
    static func setEnabled(_ enabled: Bool) throws {
        let status = SMAppService.mainApp.status
        if enabled {
            if status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            // unregister() throws kSMErrorJobNotFound when nothing is registered,
            // so only call it when there's actually a registration to remove.
            if status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
