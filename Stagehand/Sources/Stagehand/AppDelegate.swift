import AppKit

/// Owns the menu bar item and routes every user action. The menu is rebuilt on
/// each open (`menuNeedsUpdate`) so the profile list, login-item state and last
/// restore warnings are always current.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    /// Warnings from the most recent restore, surfaced as disabled rows so the
    /// user learns which apps were skipped without an interrupting dialog.
    private var lastRestoreWarnings: [String] = []
    /// True while a restore is running, to disable re-entry and show progress.
    private var isRestoring = false

    private let firstLaunchKey = "Stagehand.didShowAccessibilityExplainer"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        ProfileManagerWindowController.shared.onRestore = { [weak self] profile in
            self?.beginRestore(profile)
        }
        requestAccessibilityIfFirstLaunch()
    }

    /// On first launch only, explain the Accessibility requirement before the
    /// system's own prompt appears. After that we stay quiet unless the user
    /// tries an action that needs it.
    private func requestAccessibilityIfFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstLaunchKey) else { return }
        defaults.set(true, forKey: firstLaunchKey)
        if !AccessibilityManager.isTrusted {
            AccessibilityManager.presentFirstLaunchExplainer()
        }
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Stagehand window layouts")

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // — Saved profiles —
        let profiles = ProfileStore.shared.profiles
        if profiles.isEmpty {
            let empty = NSMenuItem(title: "No saved profiles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Restore Layout", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for profile in profiles {
                let item = NSMenuItem(
                    title: "  \(profile.name)",
                    action: #selector(restoreProfile(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                item.toolTip = "\(profile.apps.count) apps · \(profile.windowCount) windows"
                item.isEnabled = !isRestoring
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // — Capture —
        let save = NSMenuItem(title: isRestoring ? "Restoring…" : "Save current layout…",
                              action: #selector(saveCurrentLayout),
                              keyEquivalent: "s")
        save.target = self
        save.isEnabled = !isRestoring
        menu.addItem(save)

        let manage = NSMenuItem(title: "Manage Profiles…",
                                action: #selector(showProfileManager),
                                keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        // — Last-restore warnings —
        if !lastRestoreWarnings.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Last restore", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for warning in lastRestoreWarnings {
                let item = NSMenuItem(title: "  ⚠︎ \(warning)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // — Accessibility status —
        let trusted = AccessibilityManager.isTrusted
        let axItem = NSMenuItem(
            title: trusted ? "Accessibility: Granted" : "Enable Accessibility…",
            action: trusted ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: "")
        axItem.target = self
        axItem.isEnabled = !trusted
        if !trusted { axItem.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                             accessibilityDescription: nil) }
        menu.addItem(axItem)

        // — Login item —
        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Stagehand",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func saveCurrentLayout() {
        guard ensureTrusted(for: "save the current layout") else { return }

        let apps = LayoutEngine.captureCurrentLayout()
        guard !apps.isEmpty else {
            presentInfo("Nothing to save",
                        "No app windows were found to capture.")
            return
        }

        guard let name = promptForText(
            title: "Save Layout",
            message: "Name this layout profile (e.g. Work, Study, Deep Focus). "
                + "Saving over an existing name updates it.",
            defaultValue: suggestedProfileName())
        else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let windowCount = apps.reduce(0) { $0 + $1.windows.count }
        ProfileStore.shared.saveProfile(named: trimmed, apps: apps)
        presentInfo("Layout saved",
                    "“\(trimmed)” captured \(apps.count) apps and \(windowCount) windows.")
    }

    @objc private func restoreProfile(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let profile = ProfileStore.shared.profile(id: id) else { return }
        beginRestore(profile)
    }

    private func beginRestore(_ profile: LayoutProfile) {
        guard !isRestoring else { return }
        guard ensureTrusted(for: "restore a layout") else { return }

        isRestoring = true
        lastRestoreWarnings = []
        Task { @MainActor in
            let outcomes = await LayoutEngine.restore(profile)
            self.lastRestoreWarnings = outcomes.compactMap { $0.warning }
            self.isRestoring = false
        }
    }

    @objc private func showProfileManager() {
        ProfileManagerWindowController.shared.show()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityManager.triggerSystemPrompt()
        AccessibilityManager.openSystemSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            if LoginItem.requiresApproval {
                presentInfo("Approval needed",
                            "Enable Stagehand under System Settings ▸ General ▸ Login Items.")
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                presentInfo("Couldn't change login item", error.localizedDescription)
            }
        }
    }

    // MARK: Helpers

    /// Confirms Accessibility is granted before an action; otherwise prompts and
    /// returns false so the caller can bail out.
    private func ensureTrusted(for action: String) -> Bool {
        guard AccessibilityManager.isTrusted else {
            AccessibilityManager.presentBlockedActionAlert(action: action)
            return false
        }
        return true
    }

    /// A friendly default name that won't collide with existing profiles.
    private func suggestedProfileName() -> String {
        let bases = ["Work", "Study", "Deep Focus"]
        let existing = Set(ProfileStore.shared.profiles.map { $0.name.lowercased() })
        return bases.first { !existing.contains($0.lowercased()) } ?? "Layout"
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func presentInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Menu refresh

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
