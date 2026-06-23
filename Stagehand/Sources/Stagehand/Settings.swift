import Foundation

/// Lightweight, UserDefaults-backed preferences for the Moom-inspired automation
/// features. Profiles themselves live in `ProfileStore`; this just records which
/// profile (if any) is wired to each trigger, plus the global-shortcut toggle.
enum Settings {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let arrangeShortcuts = "Stagehand.arrangeShortcutsEnabled"
        static let displayTrigger   = "Stagehand.displayChangeProfileID"
        static let launchTrigger    = "Stagehand.launchRestoreProfileID"
    }

    /// Whether the global window-arrange hotkeys are active. Default on.
    static var arrangeShortcutsEnabled: Bool {
        get { defaults.object(forKey: Key.arrangeShortcuts) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.arrangeShortcuts) }
    }

    /// Profile to re-apply when the display arrangement changes (nil = off).
    static var displayChangeProfileID: UUID? {
        get { defaults.string(forKey: Key.displayTrigger).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.displayTrigger) }
    }

    /// Profile to restore once shortly after launch / login (nil = off).
    static var launchRestoreProfileID: UUID? {
        get { defaults.string(forKey: Key.launchTrigger).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.launchTrigger) }
    }
}
