import Foundation

/// UserDefaults-backed preferences for the automation features. Profiles
/// themselves live in `ProfileStore`; this records which profile (if any) is
/// wired to each trigger, plus the global-shortcut toggle.
enum Prefs {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let arrangeShortcuts = "Stagehand.arrangeShortcutsEnabled"
        static let displayTrigger   = "Stagehand.displayChangeProfileID"
        static let didExplainAX     = "Stagehand.didShowAccessibilityExplainer"
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

    /// Whether the first-launch Accessibility explainer has already been shown.
    static var didShowAccessibilityExplainer: Bool {
        get { defaults.bool(forKey: Key.didExplainAX) }
        set { defaults.set(newValue, forKey: Key.didExplainAX) }
    }
}
