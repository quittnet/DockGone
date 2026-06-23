import AppKit
import Combine

/// Central app state and action router, shared by the SwiftUI window, the
/// MenuBarExtra, and the app delegate.
///
/// Not `@MainActor`-annotated (avoids static-singleton isolation friction); every
/// `@Published` mutation happens on the main thread — the call sites are SwiftUI
/// or main-thread delegate hops, and the async restore writes back via
/// `MainActor.run`.
final class AppModel: ObservableObject {

    static let shared = AppModel()

    let store = ProfileStore.shared

    @Published var isRestoring = false
    @Published var lastWarnings: [String] = []
    @Published var showComposer = false
    @Published var showSettings = false
    @Published var isTrusted = AccessibilityManager.isTrusted

    private init() {}

    // MARK: Accessibility

    func refreshTrust() { isTrusted = AccessibilityManager.isTrusted }

    @discardableResult
    func ensureTrusted(for action: String) -> Bool {
        refreshTrust()
        if isTrusted { return true }
        AccessibilityManager.presentBlockedActionAlert(action: action)
        return false
    }

    // MARK: Capture / save

    func saveCurrentLayout() {
        guard ensureTrusted(for: "save the current layout") else { return }
        let apps = LayoutEngine.captureCurrentLayout()
        guard !apps.isEmpty else {
            TextPrompt.info(title: "Nothing to save",
                            message: "No app windows were found to capture.")
            return
        }
        guard let name = TextPrompt.ask(
            title: "Save Layout",
            message: "Name this layout profile (e.g. Work, Study, Deep Focus). "
                + "Saving over an existing name updates it.",
            defaultValue: suggestedProfileName()),
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        store.saveProfile(named: name, apps: apps)
    }

    func suggestedProfileName() -> String {
        let existing = Set(store.profiles.map { $0.name.lowercased() })
        if let preset = ["Work", "Study", "Deep Focus"].first(where: {
            !existing.contains($0.lowercased())
        }) {
            return preset
        }
        var n = 1
        while existing.contains("layout \(n)") { n += 1 }
        return "Layout \(n)"
    }

    // MARK: Restore

    func restore(_ profile: LayoutProfile) {
        guard !isRestoring, ensureTrusted(for: "restore a layout") else { return }
        beginRestore(profile)
    }

    func restoreProfile(id: UUID) {
        guard let profile = store.profile(id: id) else { return }
        restore(profile)
    }

    /// Used by automation triggers (display change / launch): restore silently,
    /// only if Accessibility is already granted.
    func restoreProfileSilently(id: UUID) {
        guard !isRestoring, AccessibilityManager.isTrusted,
              let profile = store.profile(id: id) else { return }
        beginRestore(profile)
    }

    /// Called on the main thread; flips state, runs the async restore off-main,
    /// then writes results back on the main actor.
    private func beginRestore(_ profile: LayoutProfile) {
        isRestoring = true
        lastWarnings = []
        Task {
            let outcomes = await LayoutEngine.restore(profile)
            await MainActor.run {
                self.lastWarnings = outcomes.compactMap { $0.warning }
                self.isRestoring = false
            }
        }
    }

    // MARK: Arrange

    func arrange(_ action: WindowArranger.Action) {
        guard ensureTrusted(for: "arrange the window") else { return }
        WindowArranger.apply(action)
    }

    // MARK: Global shortcuts

    /// (Re)apply the global snap hotkeys to match the preference.
    func applyArrangeShortcuts() {
        if Prefs.arrangeShortcutsEnabled {
            HotKeyManager.shared.registerArrangeShortcuts { action in
                // Fired globally; silently no-op until Accessibility is granted.
                if AccessibilityManager.isTrusted { WindowArranger.apply(action) }
            }
        } else {
            HotKeyManager.shared.unregisterAll()
        }
    }
}
